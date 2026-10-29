# Training, evaluating and predicting.
#
# One call trains every model in the specification, because comparing two architectures on
# the same data is the question people actually have, and doing it by hand means writing
# the same loop twice and hoping the splits matched.

#' Train the models in a specification
#'
#' Trains every model the specification asks for, in order, each with its own data
#' pipeline - so two models may differ in input size or tiling and still be compared
#' fairly, on the same data.
#'
#' Validation data is never augmented. Measuring a model on distorted images measures the
#' distortion.
#'
#' This blocks until training finishes. With `verbose = TRUE` each epoch is reported as it
#' completes, which on anything longer than a few minutes is the difference between
#' waiting and wondering.
#'
#' @param spec A [platypus_spec()].
#' @param device `"cuda"`, `"cpu"`, or `NULL` to use a GPU when one is present.
#' @param num_workers Processes used to read and decode images. `"auto"` picks a small
#'   number based on the machine. This matters more than it sounds: reading in the main
#'   process alone leaves the GPU waiting on the disk, and on the Data Science Bowl at
#'   128x128 that is the difference between 35 seconds an epoch and under 10. Set `0` to
#'   avoid multiprocessing entirely if it causes trouble.
#' @param strict_data Treat an incomplete sample as an error. Set `FALSE` to train on the
#'   rest and be told what was skipped.
#' @param check_masks Read a sample of the training masks before training, and refuse when
#'   a class the specification declares appears in none of them. A colormap or set of
#'   labels that matches none of the labelled tissue is the quietest way a run wastes a
#'   day: every mask reads as background, the loss falls because background is most of a
#'   medical image, and the model learns to answer "nothing here". Set `FALSE` only when
#'   the missing class is real but rarer than the sample - and see [inspect_masks()] first,
#'   which asks the same question over as much of the data as you like.
#' @param verbose Report each epoch as it finishes.
#' @return A `platypus_fit`.
#' @export
#' @examples
#' \dontrun{
#' fit <- platypus_fit(spec, verbose = TRUE)
#' evaluate(fit)
#' masks <- predict(fit, "unet")
#' }
platypus_fit <- function(spec, device = NULL, num_workers = "auto", strict_data = TRUE,
                         check_masks = TRUE, verbose = FALSE) {
  if (!inherits(spec, "platypus_spec")) {
    stop("`spec` must come from `platypus_spec()`; see `?platypus_spec`.", call. = FALSE)
  }

  built <- shim()$build_engine(spec$py, device = device,
                               num_workers = resolve_workers(num_workers),
                               strict_data = strict_data,
                               check_masks = isTRUE(check_masks))
  if (!isTRUE(built$ok)) abort_engine(built)

  # Said before the wait, not after: a run that quietly fell back to the processor looks
  # exactly like a run that is simply slow, and the difference is an hour.
  device <- shim()$device_report()
  if (isTRUE(device$gpu_present_but_unusable)) {
    warning(
      "Training on the processor: this machine has a GPU, but the installed PyTorch ",
      "build\n  cannot use it. For a GTX 10-series card or older, restart R and call ",
      "platypus_use_torch(\"pascal\").\n  See ?platypus_device.",
      call. = FALSE, immediate. = TRUE
    )
  }

  result <- shim()$run_fit(built$engine, verbose = verbose)
  if (!isTRUE(result$ok)) abort_engine(result)

  structure(
    list(
      engine = built$engine,
      spec = spec,
      task = spec_task(spec),
      models = unlist(result$models),
      history = rows_to_frame(result$history),
      stop_reasons = result$stop_reasons,
      device = device
    ),
    class = "platypus_fit"
  )
}

#' Which task a built specification describes
#'
#' Read from the Python object rather than remembered from the R one, because a
#' specification can also arrive from a YAML file where no R constructor was involved.
#'
#' @noRd
spec_task <- function(spec) {
  task <- tryCatch(shim()$spec_as_dict(spec$py)$task, error = function(e) NULL)
  if (is.null(task) || !nzchar(task)) "semantic_segmentation" else as.character(task)
}

#' @export
print.platypus_fit <- function(x, ...) {
  cat("platypus fit\n")
  cat("  models   :", paste(x$models, collapse = ", "), "\n")
  cat("  device   :", x$device$device, paste0("(torch ", x$device$torch, ")"), "\n")
  if (nrow(x$history)) {
    epochs <- tapply(x$history$epoch, x$history$model, max)
    cat("  epochs   :", paste(sprintf("%s=%d", names(epochs), epochs), collapse = ", "), "\n")
  }
  for (model in names(x$stop_reasons)) {
    cat("  stopped  :", model, "-", x$stop_reasons[[model]], "\n")
  }
  cat("  next     : evaluate(fit), predict(fit, \"", x$models[[1]], "\")\n", sep = "")
  invisible(x)
}

#' Compare the trained models
#'
#' One row per model: what it is, how big it is, how long it trained, and how it scored.
#'
#' The `loss` column is only comparable between models trained on the same loss, which is
#' why `loss_function` is there beside it. A Focal-Tversky of 0.05 is not better than a
#' CCE-Dice of 0.14; it is not even the same question.
#'
#' The metrics have a condition of their own and `load_shape` is it. Each model is scored on
#' the grid it reads at, so a model at `input_shape = c(512, 512)` is measured against a
#' truth reduced to 512 while one that tiles 2048 is measured against the truth as stored.
#' Both numbers are a real Dice of a real prediction against a real mask, and they are not
#' answers to the same question: measured on retinal vessels, that difference reported a
#' resized model as **+0.0187 better** where the honest figure was **+0.0033**, and the bias
#' runs the other way on clDice because upsampling smooths a prediction. When the rows
#' disagree about the grid this warns, once; the column is there either way, because a table
#' outlives the session that printed it.
#'
#' `at = "source"` is the answer to that warning rather than a workaround for it: every
#' prediction goes back onto the grid of the file it came from and is scored against the
#' truth as stored, so the rows answer one question and `load_shape` reads `source`. The
#' grid is the files' own and you cannot name another, which is deliberate - a grid you
#' name resamples the **truth**, so the thing both models are judged against would itself
#' become an interpolation somebody chose. Here only predictions move, and what that costs
#' is in `predict()`: interpolation softens a boundary, and where reading cropped anatomy
#' away the mask comes back padded with background, which means *not examined*. For a
#' comparison that is correct rather than unfair - a model whose field of view missed the
#' organ did not segment it - but a 0 arriving that way is a result and not a fault. The
#' loss is not reported there: a loss belongs to the objective a model trained with, on the
#' grid it trained on.
#'
#' @section What the one row pools:
#'
#' The **mean over cases**, since the engine's `0.8.0a40`. A case's own score is a ratio of
#' sums - where a case arrived in tiles their overlap counts are added and the formula applied
#' once, which is reassembly rather than a choice of average - and the split's figure is the
#' mean of those. So this row is exactly `mean(evaluate_cases(fit)$dice)`, which is what
#' anybody comparing the two expected and did not previously get: the engine divided an
#' epoch's totals by the number of batches, so a short last batch weighed more than the
#' others and the figure moved with `batch_size`. On a tiled run the difference was larger
#' still, because tiles were averaged rather than reassembled - worth +0.033 to +0.049 of Dice
#' on the retinal-vessel runs.
#'
#' [evaluate_cases()] pools a **group** differently again, by adding the counts of the images
#' in it, which is the better statistic for a patient rather than a slice. `maju116/rplatypus#196`.
#'
#' @section A note on the name:
#' `evaluate` is also exported by the **evaluate** package, which knitr depends on, so the
#' two mask each other depending on which was attached last. It is a generic here, so
#' `evaluate(fit)` dispatches on the fit's class whichever one you reach - and
#' `rplatypus::evaluate(fit)` says so outright. The name is kept because it is the word for
#' what this does; `platypus_fit()` carries a prefix only because `fit` is a generic in the
#' tidymodels packages and a plain `fit` would have been theirs to own.
#'
#' @param object A [platypus_fit()].
#' @param split Which data to score on: `"validation"`, `"train"` or `"test"`.
#' @param at Which grid to score on. `"model"` is each model's own `load_shape`, and
#'   leaving this unset is that. `"source"` puts every prediction back on the grid of the
#'   file it came from and scores it against the truth as stored, which is the form in
#'   which rows from models of different shapes answer one question. Segmentation only: a
#'   detection table has no grid to choose and says so rather than ignoring the argument.
#' @param ... Unused.
#' @return A data frame, one row per model.
#' @export
#' @examples
#' \dontrun{
#' evaluate(fit)                      # one row per model, on the validation split
#' evaluate(fit, split = "test")
#'
#' # Two models of different shapes compared on one grid - the files' own.
#' evaluate(fit, at = "source")
#'
#' # A split with no masks is refused by name rather than scored against nothing;
#' # `predict()` still works on it.
#' }
evaluate <- function(object, ...) UseMethod("evaluate")

#' @rdname evaluate
#' @export
evaluate.platypus_fit <- function(object, split = "validation", at = NULL, ...) {
  result <- if (identical(object$task, "object_detection")) {
    if (!is.null(at)) {
      stop("`at` is for segmentation: a detection table reports average precision over ",
           "boxes, which are in the source image's coordinates already and have no grid ",
           "to choose.", call. = FALSE)
    }
    shim()$detection_table(object$engine, split = split)
  } else {
    # `at` chooses the grid a mask is scored on, and a label is not on a grid at all - so
    # for this task it is refused by name rather than forwarded and ignored. The detection
    # branch above refuses it for a neighbouring reason: boxes are already in the source
    # image's coordinates.
    if (identical(object$task, "classification") && !is.null(at)) {
      stop("`at` chooses the grid a mask is scored on, and this fit answers with one label ",
           "per image. There is no grid for the answer to be on and nothing to rescore, so ",
           "the table is the same whatever `at` would have said.", call. = FALSE)
    }
    shim()$evaluation_table(object$engine, split = split, at = at)
  }
  if (!isTRUE(result$ok)) abort_engine(result)
  rows_to_frame(result$table)
}

#' Predict masks, boxes, objects or labels
#'
#' One function per fit rather than one per task, because the question - *what does this
#' model say about this split* - is the same one. What comes back is not: a mask for
#' segmentation, a table of boxes for detection, a label map of objects for instances, and
#' a row per image for classification. The arguments that describe a grid are refused where
#' there is no grid, by name, rather than accepted and ignored.
#'
#' @section Which grid the answer is on:
#'
#' `space = "model"` returns everything on the grid the model worked at, stacked into one
#' array. That is what training saw, and it is the only form that can be a single array,
#' because a stack needs one shape.
#'
#' `space = "source"` maps each prediction back onto the grid of the scan it was computed
#' from - undoing the resampling and the crop - and therefore returns a **list**, one mask per
#' scan. This is what you want for anything that has to meet the original data: laying a mask
#' over the scan in a viewer, writing it beside the scan with [save_volumes()], or measuring it
#' in millilitres of the scan's own voxels. Scans differ in size, so the list is not a
#' limitation being worked around - resizing them to a common shape is exactly how a mask ends
#' up describing anatomy it was not computed from.
#'
#' Two things are lost mapping back, and neither can be recovered. Interpolation softens a
#' boundary, so the mask returns slightly smoother than the model drew it. And where reading
#' cropped anatomy away, the mask comes back padded with background - which means *not
#' examined*, not *nothing there*. Give the model an `input_shape` that covers the anatomy if
#' that distinction matters.
#'
#' @section One at a time, when the split will not fit:
#'
#' The default returns everything together, which for a tiled run is the whole split at full
#' resolution: 200 fundus photographs at 2048 x 2048 is about 6.7 GB before anything is drawn,
#' and the engine's own `predict` was killed by exactly that. Two arguments avoid it.
#'
#' `cases` names the ones wanted. `each` hands them over one at a time and keeps only what the
#' function gives back. They compose: `cases` says which, `each` says what to do with them.
#'
#' The saving is in memory and not in time. The engine's stream is sequential, so asking for
#' two cases out of two hundred still runs the model over two hundred - it simply never holds
#' more than one answer at once.
#'
#' @param object A [platypus_fit()].
#' @param model Which model, by the name given in the specification. Defaults to the
#'   first one trained.
#' @param split Which data to predict on.
#' @param type `"class"` gives the class index per pixel, which is the mask to look at;
#'   `"probability"` keeps the per-class channel. `"channels"` is for an **instance** model
#'   only and means the model's own output before any decoding: the class channels are
#'   probabilities and a flow field's components are **raw**, which is why they are not
#'   called probabilities here - a softmax across a flow component and a class returns a
#'   number that means nothing. Read them with [flow_to_colours()].
#'
#'   On an instance fit, `"class"` is a label map of **objects**, numbered from 1, and
#'   `"probability"` is refused by name for the reason above.
#'
#'   With `regions` **or** `classes_from` - the two namings that make a pixel's classes
#'   independent - `"class"` is **refused** rather than computed. The channels are
#'   independent binary questions and do not compete, so the most likely one is not an
#'   answer: a pixel may be in three classes and naming one of them drops the rest with
#'   nothing in the result to say so. Ask for `"probability"` and write it with
#'   [save_class_masks()].
#'
#'   This page named `regions` alone until `maju116/rplatypus#252`, and so did the refusal:
#'   a `classes_from` fit got the most likely channel, which gives every background pixel a
#'   class, because there is no background channel for it to lose to. The question is asked
#'   of the engine now rather than of either field.
#'
#'   On a **classification** fit the two readings are a table and a matrix rather than two
#'   arrays: `"class"` gives one row per image with the answer and how sure the model was,
#'   and `"probability"` gives one row per image and one column per class. `"channels"` is
#'   refused - a classifier has no channels, only one number per class, and those numbers
#'   are the probabilities.
#' @param decode Which decoding turns the predicted channels into objects, by the name used
#'   in the model's `decode` list. Unset takes the model's first, which is the engine's own
#'   default rather than one restated here. **Instance models only**; for anything else it
#'   is refused, because a semantic or detection fit decodes nothing.
#' @param space `"model"` or `"source"`; see above. Note that the two return different
#'   shapes of thing, an array and a list, because they are different things. Refused on a
#'   detection, instance or classification fit, each for its own reason - boxes are in the
#'   source image's coordinates already, an object identity cannot survive resampling, and
#'   a label is not on a grid at all.
#' @param cases Case names to predict, as [evaluate_cases()] reports them. With this the
#'   result is a **named list** of just those, in the order asked for. A name that is not in
#'   the split is an error rather than a missing entry. Both this and `each` exist so that a
#'   split of full-resolution masks never has to be in memory at once, so both are refused
#'   on a classification fit, where the whole answer is one row per image.
#' @param each A function called as `each(case, mask)` once per image, instead of the
#'   predictions being returned together. Whatever it returns is collected under the case's
#'   name; return `NULL` from it and nothing accumulates. This is the form that does not
#'   need the split to fit in memory.
#' @param ... Unused.
#' @return With `space = "model"`: for `"class"`, an integer array of
#'   `image x height x width`, classes numbered from 1 to match the colormap; for
#'   `"probability"`, the same with a trailing class axis. Tiled models return images at their
#'   original size, reassembled.
#'
#'   With `space = "source"`: a list of such arrays, one per scan, each on that scan's grid,
#'   **named by case**. The name and the mask come out of one step of the engine's own
#'   stream, so they cannot be misaligned - which matters because the usual next move is to
#'   join them to something else per case, and a list paired by position is one dropped
#'   batch away from naming the wrong picture.
#'
#'   On an **instance** fit: a list of integer label maps **named by case**, objects numbered
#'   from 1 and 0 for background, one entry per image. A list rather than an array for the
#'   reason the detection one is a list, and named rather than ordered because a list paired
#'   against case names by position is one dropped batch away from naming the wrong picture.
#'   Draw them with [overlay_instances()] and measure them with [instance_sizes()].
#'
#'   On a **classification** fit: for `"class"`, a data frame of one row per image with
#'   `key` (the name the split calls it, which is what joins this to anything else), `label`
#'   (what it was labelled, or `NA` on a split that carries no labelling), `predicted` and
#'   `probability` - the probability of the class that was chosen, not of the right one. For
#'   `"probability"`, a numeric matrix of images by classes, with the keys as row names and
#'   the class names as columns, in the order `classes` was written.
#'
#'   **With `labels_from`, where a label is a set, `"class"` is a longer frame instead**:
#'   one row per image *per class*, with `key`, `class`, and `label` and `predicted` as
#'   logicals. It is a different answer rather than the same answer with a longer string,
#'   and this is the shape that says so - an image with none of the findings is a row of
#'   `FALSE` per class rather than an empty cell, which could also mean unread. Summarise
#'   per class with one `tapply`, or reshape it if you want it wide.
#'
#'   There is no `probability` column on that route, and it is missing on purpose: that
#'   column is the chosen class's own number, and with independent questions nothing was
#'   chosen. `"probability"` is the whole of the answer there and comes back as the same
#'   matrix, one column per class.
#' @export
#' @examples
#' \dontrun{
#' masks <- predict(fit, "unet")                     # an array, on the model's grid
#' masks <- predict(fit, "unet", space = "source")   # a list, on each scan's own grid
#'
#' # The two worst cases, without holding the other 198.
#' cases <- evaluate_cases(fit, split = "validation")
#' worst <- cases$case[order(cases$dice)][1:2]
#' two <- predict(fit, split = "validation", cases = worst)
#'
#' # Or walk the split, keeping one number per image and none of the masks.
#' coverage <- predict(fit, split = "validation", each = function(case, mask) mean(mask > 1))
#'
#' # `space = "source"` returns a list and not an array, which is the API being
#' # honest: scans differ in size, a stacked array needs one shape, and resizing
#' # them to match is how a mask ends up describing anatomy it was not computed from.
#' }
predict.platypus_fit <- function(object, model = NULL, split = "test",
                                 type = c("class", "probability", "channels"),
                                 space = c("model", "source"),
                                 cases = NULL, each = NULL, decode = NULL, ...) {
  # Asked before `match.arg` assigns to them: in R, `missing()` on a formal argument stops
  # being true once the argument has been assigned to, so reading it after the two lines
  # below reports "the caller passed this" for every caller. The first version did exactly
  # that and refused the plain `predict(fit)` that every user makes first.
  asked_type <- !missing(type)
  asked_space <- !missing(space)
  type <- match.arg(type)
  space <- match.arg(space)
  model <- model %||% object$models[[1]]
  if (!model %in% object$models) {
    stop("no model called '", model, "'; this fit has: ",
         paste(object$models, collapse = ", "), call. = FALSE)
  }
  # Asked of every task rather than of the ones that fall through to the bottom of this
  # function, which is where it used to sit: the detection branch returns before reaching
  # it, so `predict(fit, decode = )` on a detector was accepted and silently ignored.
  if (!is.null(decode) && !identical(object$task, "instance_segmentation")) {
    stop("`decode` is how predicted channels become objects, which only an instance model ",
         "does. This fit is ", object$task, ".", call. = FALSE)
  }

  if (identical(object$task, "object_detection")) {
    if (asked_type || asked_space) {
      stop("`type` and `space` are about masks. A detector returns boxes, always in each ",
           "image's own pixels - there is no other space they could be in that anyone ",
           "would want.", call. = FALSE)
    }
    found <- shim()$detections(object$engine, model, split = split)
    if (!isTRUE(found$ok)) abort_engine(found)
    return(as_box_frames(found$detections))
  }

  if (identical(object$task, "classification")) {
    if (asked_space) {
      stop("`space` chooses the grid a mask comes back on, and this fit answers with one ",
           "label per image. There is no grid for a label to sit on and no inverse to map ",
           "it through, so neither value of `space` would mean anything.", call. = FALSE)
    }
    if (identical(type, "channels")) {
      stop("`type = \"channels\"` exists for an instance model, whose vector channels are ",
           "not probabilities. A classifier's output is one number per class and those ",
           "numbers *are* probabilities, so `type = \"probability\"` is the ask - a matrix ",
           "with a row per image and a column per class.", call. = FALSE)
    }
    if (!is.null(cases) || !is.null(each)) {
      stop("`cases` and `each` walk a split's masks, one at a time, so that a whole set ",
           "of them never has to be in memory at once. One label per image is already ",
           "small: this returns a row per image, so subset the result or walk its rows ",
           "instead.", call. = FALSE)
    }
    found <- shim()$classification_answers(object$engine, model, split = split)
    if (!isTRUE(found$ok)) abort_engine(found)
    classes <- as.character(unlist(found$classes))
    keys <- vapply(found$rows, function(row) as.character(row$key), character(1))

    if (identical(type, "probability")) {
      # A matrix rather than a data frame, because every column is the same quantity and a
      # caller plotting an ROC curve or taking a row-wise maximum wants it that way. Named
      # on both margins: the keys are what joins this to anything else they hold, and the
      # class order is the specification's rather than whatever order a row's `p_` keys
      # happened to iterate in.
      probabilities <- t(vapply(found$rows, function(row) {
        vapply(classes, function(klass) as.numeric(row[[paste0("p_", klass)]]),
               numeric(1), USE.NAMES = FALSE)
      }, numeric(length(classes))))
      dimnames(probabilities) <- list(keys, classes)
      return(probabilities)
    }

    # **A set of labels is a different answer and not the same answer with a longer
    # string**, so it comes back in a different shape: one row per image per class, with
    # `label` and `predicted` as logicals. The alternatives were measured against what a
    # reader does with it. A wide frame needs two columns per class - the truth and the
    # answer - and names them by pasting, which is how a class called `Mass_label` becomes
    # ambiguous. A list column holds the sets but nothing in base R aggregates it. Long
    # form joins to anything by `key`, summarises per class with one `tapply`, and is the
    # only shape in which "this image has none of the findings" is four rows of FALSE
    # rather than an empty cell that could also mean unread.
    #
    # **And that last clause is why `label` is NA rather than FALSE on an unlabelled
    # split** (`rplatypus#245`). The argument above rests on FALSE meaning *measured and
    # absent*, so the shape only keeps "none of them" apart from "unread" if "unread" is
    # written as something else. `0.8.0a52` made an unlabelled classification test split
    # reachable - a CSV of `key, images`, which is the ordinary shape of a prediction set -
    # and the engine marks it by sending `labels: NULL` where a film carrying no finding
    # sends an empty list. Both arrive here as `character(0)`, so the distinction has to be
    # read from the NULL rather than from what `%in%` makes of it.
    #
    # There is no `probability` column on this route and that is the engine's decision
    # rather than an omission here: that column is the chosen class's own number, and with
    # independent questions nothing was chosen. `type = "probability"` above is the whole
    # of the answer, and it needs no branch - the `p_<class>` keys are in both shapes.
    if (isTRUE(found$multilabel)) {
      answers <- do.call(rbind, lapply(found$rows, function(row) {
        said <- as.character(unlist(row$predicted))
        # NA for a split nobody labelled, and it is read from the NULL rather than from
        # the emptiness: `character(0)` is what both an unlabelled image and a film
        # carrying none of the findings reduce to, and `classes %in% character(0)` is
        # FALSE either way. `NA` keeps the column logical, so `tapply` and `table` go on
        # working and a split with no labelling is visible rather than reading as a
        # dataset in which nothing is ever present.
        truth <- if (is.null(row$labels)) {
          rep(NA, length(classes))
        } else {
          classes %in% as.character(unlist(row$labels))
        }
        data.frame(
          key = as.character(row$key),
          # `classes` rather than the row's own order, so two rows are comparable and the
          # class index is the specification's.
          class = classes,
          label = truth,
          predicted = classes %in% said,
          stringsAsFactors = FALSE
        )
      }))
      rownames(answers) <- NULL
      return(answers)
    }

    # Named by case rather than returned in the split's order alone, which is the lesson
    # `rplatypus#223` cost on the semantic path: a prediction handed back as a bare
    # sequence has to be paired with whatever else the caller holds by position, and one
    # dropped last batch names the wrong picture. `label` is NA on a split that carries no
    # labelling, which is what a test set often is.
    answers <- rows_to_frame(lapply(found$rows, function(row) {
      row[c("key", "label", "predicted", "probability")]
    }))
    return(answers)
  }

  if (identical(object$task, "instance_segmentation")) {
    if (asked_space) {
      stop("`space` is about a mask on a grid, and an instance result is objects. The ",
           "engine decodes them on the model's own grid, and there is no inverse that ",
           "could put an object identity back on the scan's grid: resampling a label map ",
           "interpolates between object numbers, so object 3 and object 5 become a rim of ",
           "object 4. Use the maps as they come, or `target_spacing` so the model's grid ",
           "is the one you want.", call. = FALSE)
    }
    if (identical(type, "probability")) {
      stop("an instance model's channels are not all probabilities, so `type = ",
           "\"probability\"` would be a name for something that is not one: the class ",
           "channels are probabilities and the vector channels - a flow field's components ",
           "- are raw, because a softmax across a flow component and a class returns a ",
           "number that means nothing. Ask for `type = \"channels\"`, which says what it ",
           "gives.", call. = FALSE)
    }
    if (identical(type, "channels")) {
      found <- shim()$instance_channels(object$engine, model, split = split)
      if (!isTRUE(found$ok)) abort_engine(found)
      return(found$channels)
    }
    found <- shim()$instance_predictions(object$engine, model, split = split,
                                         decode = decode)
    if (!isTRUE(found$ok)) abort_engine(found)
    # Named by case rather than returned in the split's order alone. The engine's own list
    # is unnamed, and anything that pairs two sequences by position is one `drop_last` away
    # from naming the wrong picture - which is why `predict_stream` exists on the semantic
    # side. The names come from the same two objects the engine pairs internally.
    maps <- lapply(found$maps, function(one) array(as.integer(one), dim = dim(one)))
    names(maps) <- unlist(found$cases)
    return(maps)
  }
  if (identical(type, "channels")) {
    stop("`type = \"channels\"` exists for an instance model, whose vector channels are ",
         "not probabilities. For this fit the channels *are* probabilities, so ask for ",
         "`type = \"probability\"`.", call. = FALSE)
  }

  # Overlapping classes have no class index to return: each channel is an independent
  # question, the channels do not compete, and an `argmax` across them names one of the
  # classes a pixel is in and drops the others. The shape cannot answer this - sigmoid
  # channels and a softmax's channels are the same array - so it is read off the
  # specification this fit carries, which is a lever R owns rather than one it borrows.
  # ASKED of the engine rather than inferred from one field. This read
  # `length(as.list(object$spec)$data$regions)` until `maju116/rplatypus#252`, and
  # `classes_from` makes the channels independent exactly as `regions` does - so a
  # `classes_from` fit got an argmax over sigmoids with no background channel, which gives
  # every background pixel a class and nothing downstream can see it. The engine has one
  # switch for this and says so in `SegmentationData.multilabel`'s own docstring.
  facts <- if (identical(type, "class")) shim()$data_facts(object$spec$py) else NULL
  if (isTRUE(facts$multilabel)) {
    # And the message names the naming the caller actually used. It said `regions`
    # unconditionally, which was the same mistake as the guard one line up: a reader with a
    # `classes_from` specification would have gone looking for a field they never wrote.
    stop("this specification names overlapping classes (`", facts$naming, "`), so there ",
         "is no one class per pixel to return - each channel is an independent question ",
         "and a pixel may be in several at once. Ask for `type = \"probability\"`, which ",
         "gives one channel per class in the order they were written, and ",
         "`save_class_masks()` writes those one file per class. `inspect_masks()` names ",
         "the channels.", call. = FALSE)
  }

  if (is.null(cases) && is.null(each)) {
    result <- shim()$predictions(object$engine, model, split = split,
                                 as_class = identical(type, "class"), space = space)
    if (!isTRUE(result$ok)) abort_engine(result)
    # Named in source space, where the answer is a list and a caller holding anything else
    # per case - a pixel size, a reference measurement, a path - would otherwise have to
    # pair two sequences by position. That is what the paragraph in this function's own help
    # page warns about, and it was true of this branch until `maju116/rplatypus#223`. Model
    # space is one stacked array, so there is nothing to name.
    if (identical(space, "source")) {
      masks <- result$masks
      names(masks) <- as.character(unlist(result$cases))
      return(masks)
    }
    return(result$masks)
  }

  if (!is.null(each) && !is.function(each)) {
    stop("`each` has to be a function called as each(case, mask)", call. = FALSE)
  }
  if (!is.null(cases)) {
    cases <- as.character(cases)
    if (!length(cases)) {
      stop("`cases` is empty, so there is nothing to predict", call. = FALSE)
    }
  }

  # Collected into an environment rather than with `<<-`: the callback is handed to Python
  # and called from there, and a closure reaching back into its parent's binding across
  # that boundary is a thing that works until it does not. An environment says which frame
  # is being written to.
  kept <- new.env(parent = emptyenv())
  visit <- function(case, mask) {
    value <- if (is.null(each)) mask else each(case, mask)
    # NULL means the caller wants the side effect and none of the masks, which is the point
    # of `each` for a split that does not fit. Assigning NULL to a list entry deletes it
    # anyway, so it is skipped rather than stored.
    if (!is.null(value)) assign(case, value, envir = kept)
    invisible(NULL)
  }

  result <- shim()$predictions_each(
    object$engine, model, visit, split = split,
    as_class = identical(type, "class"), space = space,
    cases = if (is.null(cases)) NULL else as.list(cases)
  )
  if (!isTRUE(result$ok)) abort_engine(result)

  # In the order asked for, not the order the stream served them: a caller naming two cases
  # is comparing them, and reordering silently is how the labels on a figure stop describing
  # the panels above them.
  order_of <- if (is.null(cases)) as.character(unlist(result$cases)) else cases
  out <- lapply(order_of, function(case) {
    if (exists(case, envir = kept)) get(case, envir = kept)
  })
  names(out) <- order_of
  out[!vapply(out, is.null, logical(1))]
}

#' One data frame of boxes per image, named by the sample key
#'
#' A data frame rather than a matrix, because a box carries a score and a class name as
#' well as four numbers, and because that is the shape `plot_boxes()` and `write.csv()`
#' both want. An image with nothing found gets a frame with no rows rather than being
#' dropped: a split of fifty images returns fifty entries, so nothing downstream has to
#' line names up against a shorter list.
#'
#' @noRd
as_box_frames <- function(found) {
  frames <- lapply(found, function(entry) {
    boxes <- entry$boxes
    if (is.null(boxes) || !length(boxes)) {
      return(data.frame(xmin = numeric(0), ymin = numeric(0), xmax = numeric(0),
                        ymax = numeric(0), score = numeric(0), label = integer(0),
                        name = character(0), stringsAsFactors = FALSE))
    }
    boxes <- matrix(as.numeric(boxes), ncol = 4)
    data.frame(
      xmin = boxes[, 1], ymin = boxes[, 2], xmax = boxes[, 3], ymax = boxes[, 4],
      score = as.numeric(entry$scores),
      label = as.integer(entry$labels),
      name = as.character(entry$names),
      stringsAsFactors = FALSE
    )
  })
  names(frames) <- vapply(found, function(entry) as.character(entry$key), character(1))
  frames
}

#' Average precision per class
#'
#' **Detection only.** On a segmentation fit this refuses by name and points at
#' [evaluate_cases()]. The name carries no `detection_` prefix on purpose: this is an S3
#' generic, so a future task gains a method under the same name rather than a second
#' spelling of one idea.
#'
#' The row that matters on unbalanced data, which is most detection data: BCCD has 4,155
#' red cells against 372 white and 361 platelets, so a single number is a number about red
#' cells. [evaluate()] deliberately carries no overall precision or recall for the same
#' reason - averaging them over classes needs a weighting, and every choice of weighting is
#' a different claim.
#'
#' @param object A fit from [platypus_fit()] on a detection specification.
#' @param model Which model, when the specification trained several.
#' @param split Which split to score.
#' @param ... Unused.
#' @return A data frame, one row per class: average precision at IoU 0.5, the mean overlap
#'   of the boxes that matched, the number of true boxes, and precision and recall at the
#'   model's `operating_point`.
#' @export
#' @examples
#' \dontrun{
#' evaluate_classes(fit, "bccd")
#'
#' # The row that matters on unbalanced data, which is most data: BCCD has 4155 red
#' # cells against 372 white and 361 platelets, so a single number is a number about
#' # red cells.
#' }
evaluate_classes <- function(object, ...) UseMethod("evaluate_classes")

#' @rdname evaluate_classes
#' @export
evaluate_classes.platypus_fit <- function(object, model = NULL,
                                          split = "validation", ...) {
  if (!identical(object$task, "object_detection")) {
    stop("`evaluate_classes()` reports average precision per class, which is a detection ",
         "measure. For segmentation, `evaluate_cases()` reports per case and ",
         "`summary()` on the result summarises it; for classification the per-class ",
         "figures are `evaluate()`'s own columns.", call. = FALSE)
  }
  model <- model %||% object$models[[1]]
  result <- shim()$detection_classes(object$engine, model, split = split)
  if (!isTRUE(result$ok)) abort_engine(result)
  rows_to_frame(result$rows)
}

#' Score every image separately
#'
#' **Detection only.** On a segmentation fit this refuses by name and points at
#' [evaluate_cases()]. The name carries no `detection_` prefix on purpose: this is an S3
#' generic, so a future task gains a method under the same name rather than a second
#' spelling of one idea.
#'
#' `evaluate()` gives one row per model and `evaluate_classes()` one row per class. This
#' gives one row per image, which is the question asked next: not how well on average, but
#' **which** pictures it fails on. A mean over a split says 0.86; it does not say the misses
#' are four frames where the stain is dark, and that difference is usually something about
#' the data rather than the model.
#'
#' Sort by `missed` for the frames it cannot see, and by `mean_matched_iou` for the ones
#' where it finds everything and places it badly. Those are different problems - the first
#' is usually the data, the second usually the anchors.
#'
#' **There is no average precision here, deliberately.** Average precision is the area under
#' a precision-recall curve, so it is a property of a ranking over a whole dataset; computed
#' on one image with three boxes it moves on a single box's rank and means nothing. What is
#' meaningful for one picture is counting and overlap, which is what the columns carry.
#'
#' `mean_matched_iou` is `NA` rather than 0 when nothing matched. An image where the model
#' found nothing and one where it found badly-placed boxes are different failures, and a
#' zero would merge them.
#'
#' @param object A [platypus_fit()] on a detection specification.
#' @param model Which model, by the name in the specification. Defaults to the first.
#' @param split Which data to score on.
#' @param score_threshold The confidence at which the counts are read. Unset, the
#'   specification's `operating_point` is used, which is what it is for: "how many were
#'   missed" is undefined over the whole ranking, where every box the model dimly considered
#'   counts as a prediction.
#' @param ... Unused.
#' @return A data frame of class `platypus_images`, one row per image: `key`, `n_truth`,
#'   `n_predicted`, `matched`, `missed`, `spurious` and `mean_matched_iou`.
#' @seealso [evaluate_classes()] for one row per class, [evaluate_cases()] for the
#'   segmentation counterpart.
#' @examples
#' \dontrun{
#' images <- evaluate_images(fit)
#' head(images[order(-images$missed), ])          # the frames it cannot see
#' head(images[order(images$mean_matched_iou), ]) # the ones it places badly
#' }
#' @export
evaluate_images <- function(object, ...) UseMethod("evaluate_images")

#' @rdname evaluate_images
#' @export
evaluate_images.platypus_fit <- function(object, model = NULL, split = "validation",
                                         score_threshold = NULL, ...) {
  if (!identical(object$task, "object_detection")) {
    stop("`evaluate_images()` counts boxes per image, which is a detection measure. ",
         "For segmentation, `evaluate_cases()` scores every case separately; for ",
         "classification, `predict()` returns one row per image.", call. = FALSE)
  }
  model <- model %||% object$models[[1]]
  if (!model %in% object$models) {
    stop("no model called '", model, "'; this fit has: ",
         paste(object$models, collapse = ", "), call. = FALSE)
  }
  result <- shim()$detection_images(object$engine, model, split = split,
                                    score_threshold = score_threshold)
  if (!isTRUE(result$ok)) abort_engine(result)

  frame <- rows_to_frame(result$rows)
  structure(frame, class = c("platypus_images", class(frame)))
}

#' @export
print.platypus_images <- function(x, ...) {
  clean <- sum(x$missed == 0 & x$spurious == 0)
  cat("platypus boxes by image (", nrow(x), " rows); ", clean,
      " exactly right\n", sep = "")
  worst <- x[order(-x$missed, x$mean_matched_iou), , drop = FALSE]
  print(as.data.frame(utils::head(worst, 10)), row.names = FALSE)
  if (nrow(x) > 10) {
    cat("  ... ", nrow(x) - 10,
        " more, worst first. Order by mean_matched_iou for poor placement.\n", sep = "")
  }
  invisible(x)
}

#' The anchors a detector used, and whether they were fitted
#'
#' A detector cannot be reloaded without its anchors, and when they were fitted rather than
#' named in the specification this is the only record. [export_weights()] writes them into the
#' sidecar for the same reason.
#'
#' @param object A fit from [platypus_fit()] on a detection specification.
#' @param model Which model, when the specification trained several.
#' @return A list: `anchors` as three groups of pairs, `fitted` saying whether they were
#'   fitted to your data, and when they were, the mean overlap they achieve and a data
#'   frame with one row per anchor.
#' @export
#' @examples
#' \dontrun{
#' anchors <- detection_anchors(fit)
#' anchors$mean_iou        # ~0.88 fitted on BCCD, against 0.65 for COCO's nine
#' anchors$per_anchor      # one row per anchor
#'
#' # `fitted` says whether these were fitted to the data or taken from the
#' # specification. A detector cannot be reloaded without them, so they travel
#' # with the weights.
#' }
detection_anchors <- function(object, model = NULL) {
  if (!inherits(object, "platypus_fit") || !identical(object$task, "object_detection")) {
    stop("`detection_anchors()` needs a fit from a detection specification.",
         call. = FALSE)
  }
  model <- model %||% object$models[[1]]
  result <- shim()$run_anchors(object$engine, model)
  if (!isTRUE(result$ok)) abort_engine(result)
  list(
    anchors = result$anchors,
    fitted = isTRUE(result$fitted),
    mean_iou = result$mean_iou,
    boxes_used = result$boxes_used,
    per_anchor = rows_to_frame(result$rows)
  )
}

#' Cut every detection out of the image it was found in
#'
#' A detector that knows three classes, followed by a classifier that knows eighty: find the
#' objects, cut them out, hand the pieces to something else. [predict()] returns boxes in each
#' image's own pixels precisely so they can be used on the photograph they came from, and this
#' is what uses them.
#'
#' @details
#' Cut from the image at its **native size**, not from the square the network sees. Cropping
#' the letterboxed frame would cut a shrunken object and then scale it back up: on a 1024-wide
#' photograph fed to a 416 model, every crop would be two fifths of the size the data allows.
#'
#' Four more decisions, each of which taken the other way changes what a downstream model sees
#' without changing anything you would notice:
#'
#' * **Rounded outward**, so the crop contains the whole box. Rounding to nearest loses up to a
#'   pixel per side, which on a 26-pixel platelet is a twelfth of the object.
#' * **`context` grows with the box**, not by a number of pixels, so one value suits a platelet
#'   and a white cell. Zero by default: a detector's box is tight by construction, and a
#'   classifier trained on whole objects does worse on something cut exactly at the edge - but
#'   expanding silently would put things nobody asked for into every crop.
#' * **`size` letterboxes rather than stretches.** Resizing a tall box to a square changes the
#'   aspect of every non-square object, and a classifier then sees a shape that does not occur
#'   in nature. `fit = "stretch"` is there for models trained that way, and has to be asked for.
#' * **Read at `operating_point`, not at the specification's `score_threshold`.** That one sits
#'   near zero so that average precision integrates the whole ranking - hundreds of boxes an
#'   image, almost all of them the tail it exists to measure over. Cropping those would hand a
#'   classifier mostly noise.
#'
#' `dropped` is the number of boxes that clipped to nothing. A model may place a box off the
#' frame and [predict()] reports what it said, so at a low threshold some arrive with no
#' extent at all; those are dropped and counted rather than the arrays quietly coming back
#' shorter than the detections.
#'
#' @param object A [platypus_fit()] from a detection specification.
#' @param model Which model, if the fit holds several.
#' @param split Which split's images to read.
#' @param score_threshold Crop at this confidence instead of the specification's
#'   `operating_point`.
#' @param context Expand every box by this fraction of its own width and height, per side.
#' @param size `c(height, width)` every crop is brought to, or `NULL` to keep each as cut.
#'   Crops of one image differ in size otherwise, which is why this returns a list either way.
#' @param fit `"letterbox"` to preserve the aspect by padding, `"stretch"` to fill the frame.
#' @param ... Unused.
#' @return A list with one entry per image, each a list of `key`, `crops` (a list of
#'   `height x width x channels` arrays), `boxes`, `scores`, `labels`, `names` and `dropped`.
#' @export
#' @examples
#' \dontrun{
#' found <- detection_crops(fit, size = c(224, 224))
#' length(found[[1]]$crops)
#' plot_masks(found[[1]]$crops[[1]])        # look at one
#'
#' # Everything above the operating point, as one flat list ready for another model.
#' pieces <- unlist(lapply(found, `[[`, "crops"), recursive = FALSE)
#' }
detection_crops <- function(object, model = NULL, split = "test", score_threshold = NULL,
                            context = 0, size = NULL, fit = "letterbox", ...) {
  if (!inherits(object, "platypus_fit")) {
    stop("`object` must come from `platypus_fit()`.", call. = FALSE)
  }
  if (!identical(object$task, "object_detection")) {
    stop("`detection_crops()` cuts out boxes, which only a detector produces. For ",
         "segmentation, `predict()` gives masks and `save_masks()` writes them.",
         call. = FALSE)
  }
  model <- model %||% object$models[[1]]
  if (!model %in% object$models) {
    stop("no model called '", model, "'; this fit has: ",
         paste(object$models, collapse = ", "), call. = FALSE)
  }
  if (!identical(fit, "letterbox") && !identical(fit, "stretch")) {
    stop("`fit` is \"letterbox\" or \"stretch\"; got ", paste(deparse(fit), collapse = " "),
         ". A stretch changes the aspect of every non-square object, so it is the one you ",
         "ask for rather than the one you get.", call. = FALSE)
  }
  if (!is.null(size) && length(size) != 2L) {
    stop("`size` is c(height, width); got ", length(size), " value(s).", call. = FALSE)
  }

  result <- shim()$detection_crops(object$engine, model, split = split,
                                   score_threshold = score_threshold,
                                   context = as.numeric(context),
                                   size = if (is.null(size)) NULL else as.integer(size),
                                   fit = fit)
  if (!isTRUE(result$ok)) abort_engine(result)
  result$records
}

#' The epoch-by-epoch record
#'
#' One row per model per epoch, with the loss, whatever metrics were asked for, how long
#' the epoch took and the learning rate it ran at. Two columns arrive whether or not
#' anybody asked:
#'
#' * **`foreground`** - the share of the prediction that is not background. Not a measure
#'   of quality, because nothing is compared against the truth: it answers whether the
#'   model is still producing a segmentation at all. A model collapsing to background
#'   reports a plausible loss and, with `include_background = TRUE`, a Dice around 0.5.
#' * **`val_<metric>_worst`** - the lowest any single case scored. The distribution is the
#'   finding and the mean is where a failure hides, so the number worth reading is in the
#'   table rather than only in [summary()] after the run.
#'
#' @param object A [platypus_fit()].
#' @return A data frame with one row per model per epoch.
#' @export
#' @examples
#' \dontrun{
#' history <- training_history(fit)
#' head(history)
#'
#' # For a detector the loss is broken into four terms on purpose: a run whose
#' # coordinate loss falls while its objectness loss does not is finding the right
#' # places and refusing to commit, and the reverse is confident nonsense.
#' }
training_history <- function(object) {
  if (!inherits(object, "platypus_fit")) {
    stop("`object` must come from `platypus_fit()`.", call. = FALSE)
  }
  object$history
}

#' How many processes should read the data
#'
#' Zero was the obvious default and the wrong one. Decoding a few hundred PNGs in the main
#' process leaves the GPU idle most of the epoch: measured on the Data Science Bowl at
#' 128x128, zero workers took 35 seconds an epoch and eight took under ten. A package that
#' promises a quick first result should not ship the slow arrangement by default.
#'
#' Four is a deliberate ceiling rather than a count of the cores. The work is reading and
#' decoding files, so it saturates well before the processor does, and each worker holds
#' its own copy of the sample cache.
#' @keywords internal
#' @noRd
resolve_workers <- function(x) {
  if (is.numeric(x)) return(as.integer(x))
  if (!identical(x, "auto")) {
    stop("`num_workers` must be a number or \"auto\".", call. = FALSE)
  }
  cores <- tryCatch(parallel::detectCores(logical = FALSE), error = function(e) NA_integer_)
  if (is.na(cores) || cores < 2L) return(0L)
  min(4L, cores - 1L)
}

#' Turn a list of equally-shaped records into a data frame
#'
#' The engine reports tables as lists of rows, which is what survives the crossing
#' intact. Missing entries become NA rather than shifting a column.
#' @keywords internal
#' @noRd
rows_to_frame <- function(rows) {
  if (!length(rows)) return(data.frame())
  columns <- unique(unlist(lapply(rows, names)))
  frame <- lapply(columns, function(column) {
    values <- lapply(rows, function(row) {
      value <- row[[column]]
      if (is.null(value) || !length(value)) NA else value[[1]]
    })
    unlist(values)
  })
  names(frame) <- columns
  as.data.frame(frame, stringsAsFactors = FALSE)
}

#' Score every case separately
#'
#' `evaluate()` gives one row per model: one number for a whole set. This gives one row per
#' case - each image, or each patient when `group_by` is set - because one number hides the
#' distribution, and the distribution is usually the finding. A model averaging Dice 0.86
#' that scores 0.1 on three patients has a failure mode, and the mean is where it hides.
#'
#' `summary()` on the result gives the distribution: mean, standard deviation, median,
#' range, and which case scored worst.
#'
#' Tiled models are scored on the whole image, not on tiles. Overlaps are accumulated
#' across a case's tiles and the metric applied once, which is that image's score exactly;
#' averaging the tiles' scores would be a different number, and unkind to any case whose
#' object happens to straddle a boundary.
#'
#' @param object A [platypus_fit()].
#' @param model Which model, by the name in the specification. Defaults to the first.
#' @param split Which data to score on.
#' @param group_by A pattern picking a group out of each case's name, as in
#'   [split_dataset()]. With it, the rows are patients rather than slices: a patient's
#'   slices are pooled into one score, the way a volume would be.
#' @param at Which grid to score on, as in [evaluate()]. Unset is the model's own
#'   `load_shape`; `"source"` reads each truth as stored and scores the prediction there,
#'   which is the only form in which rows from two models - or from two runs with different
#'   `target_spacing` - mean the same thing.
#' @param ... Unused.
#' @return A data frame with one row per case, of class `platypus_cases`.
#' @seealso [split_dataset()] for keeping a patient out of two sets in the first place.
#' @examples
#' \dontrun{
#' cases <- evaluate_cases(fit)
#' summary(cases)
#' head(cases[order(cases$dice), ])          # the ones worth looking at
#'
#' evaluate_cases(fit, group_by = "^(patient\\\\d+)_")
#'
#' # On the grid the files are on, which is what makes two models comparable.
#' evaluate_cases(fit, at = "source")
#' }
#' @export
evaluate_cases <- function(object, ...) UseMethod("evaluate_cases")

#' @rdname evaluate_cases
#' @export
evaluate_cases.platypus_fit <- function(object, model = NULL, split = "validation",
                                        group_by = NULL, at = NULL, ...) {
  # Refused rather than returned, because the number it would report carries no
  # information. A case on the segmentation side is an image with hundreds of thousands of
  # voxels and a score of its own, which is what makes the minimum worth publishing; one
  # image's accuracy is 0 or 1, so a split's worst case is 0 for any model that gets a
  # single image wrong. The engine says the same thing by having no `_worst` column here.
  if (identical(object$task, "classification")) {
    stop("`evaluate_cases()` scores every case separately, and a case here is one image ",
         "whose score is 0 or 1 - so the worst case of a split is 0 for any model that ",
         "gets one image wrong, and the spread carries nothing. `predict()` returns a row ",
         "per image with the answer and every class's probability, and `evaluate()` ",
         "reports the per-class figures - `balanced_accuracy` and `f1` - which is the ",
         "question this one is asking.", call. = FALSE)
  }
  model <- model %||% object$models[[1]]
  if (!model %in% object$models) {
    stop("no model called '", model, "'; this fit has: ",
         paste(object$models, collapse = ", "), call. = FALSE)
  }
  result <- shim()$case_table(
    object$engine, model, split = split, group_by = group_by, at = at
  )
  if (!isTRUE(result$ok)) abort_engine(result)

  frame <- rows_to_frame(result$table)
  structure(frame, class = c("platypus_cases", class(frame)), label = result$label)
}

#' @param object A `platypus_cases` from [evaluate_cases()].
#' @rdname evaluate_cases
#' @export
summary.platypus_cases <- function(object, ...) {
  rows <- lapply(seq_len(nrow(object)), function(i) as.list(object[i, , drop = FALSE]))
  result <- shim()$case_summary(rows)
  if (!isTRUE(result$ok)) abort_engine(result)
  rows_to_frame(result$table)
}

#' @export
print.platypus_cases <- function(x, ...) {
  label <- attr(x, "label") %||% "case"
  cat("platypus scores by ", label, " (", nrow(x), " rows)\n", sep = "")
  print(as.data.frame(utils::head(x, 10)), row.names = FALSE)
  if (nrow(x) > 10) {
    cat("  ... ", nrow(x) - 10, " more. summary() gives the distribution.\n", sep = "")
  }
  invisible(x)
}

#' The published weights, and what they are
#'
#' Weights are named rather than downloaded by hand, and a name is pinned to one commit of the
#' repository holding it - so `"dsbowl-unet"` means one set of numbers today and the same set next
#' year. This lists what is published, with the commit each name resolves to.
#'
#' Read the descriptions rather than only the names. A model's limitations decide whether it
#' answers your question: the nuclei weights are semantic, so touching nuclei come back as one
#' region and a count taken from them would be wrong.
#'
#' @return A data frame with `name`, `repo`, `filename`, `revision` and `description`.
#' @seealso [u_net()] and the other architectures, whose `weights` argument takes a name from
#'   here, a `hf://owner/repo/file.safetensors@commit` reference, or a path to a local file.
#' @examples
#' \dontrun{
#' available_weights()
#'
#' spec <- platypus_spec(
#'   data = segmentation_data("images/", "images/", colormap = binary_colormap),
#'   models = list(u_net("nuclei", input_shape = c(256, 256), blocks = 4, filters = 16,
#'                       weights = "dsbowl-unet", fit = FALSE))
#' )
#' masks <- predict(platypus_fit(spec), split = "validation")
#' }
#' @export
available_weights <- function() {
  result <- shim()$weights_listing()
  if (!isTRUE(result$ok)) abort_engine(result)

  rows <- lapply(result$weights, function(row) {
    data.frame(name = row$name, repo = row$repo, filename = row$filename,
               revision = row$revision, description = row$description,
               stringsAsFactors = FALSE)
  })
  if (!length(rows)) {
    return(data.frame(name = character(), repo = character(), filename = character(),
                      revision = character(), description = character(),
                      stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

#' Save a trained model's weights
#'
#' Writes safetensors plus a `.json` sidecar recording what the weights are for: architecture,
#' input shape, channels, classes, and whatever else you pass. Loading refuses a model they do not
#' belong to, which is what the sidecar is for - weights trained on a different colormap with the
#' same number of classes load cleanly and predict nonsense.
#'
#' Anything in `...` joins the sidecar. The data they were trained on and its licence belong there:
#' weights whose provenance lives in somebody's memory cannot be used by anybody else, including
#' you in a year.
#'
#' @param object A [platypus_fit()].
#' @param path Where to write, with or without the `.safetensors` extension.
#' @param model Which model, by the name in the specification. Defaults to the first.
#' @param ... Extra fields for the sidecar, for instance `data = "BBBC038v1"`,
#'   `licence = "CC0 1.0"`.
#' @return The path written, invisibly, with the sidecar's contents attached as the `recorded`
#'   attribute - so you can see what was put beside the weights without opening the file.
#' @examples
#' \dontrun{
#' export_weights(fit, "weights/my-run",
#'              data = "our 2026 cohort", licence = "internal use only")
#' }
#' @export
export_weights <- function(object, path, model = NULL, ...) {
  if (!inherits(object, "platypus_fit")) {
    stop("`object` must come from `platypus_fit()`.", call. = FALSE)
  }
  model <- model %||% object$models[[1]]
  if (!model %in% object$models) {
    stop("no model called '", model, "'; this fit has: ",
         paste(object$models, collapse = ", "), call. = FALSE)
  }

  extra <- list(...)
  result <- shim()$export_weights(object$engine, model, path.expand(path),
                                  extra = if (length(extra)) extra else NULL)
  if (!isTRUE(result$ok)) abort_engine(result)
  invisible(structure(result$path, recorded = result$recorded, sidecar = result$sidecar))
}


#' Class indices as the specification named them, where it named them
#'
#' The engine reports classes by position, and with `regions` a position is the one thing a
#' reader cannot resolve: `missing_classes: 1` means the second region, and counting regions
#' in a configuration file to find out which is the step nobody takes. With `colormap` or
#' `labels` the number *is* the class, so it stays a number.
#'
#' The mapping is positional and zero-based, measured rather than assumed: on a spec whose
#' second region matches nothing, the engine returned `missing = 1`. The out-of-range fallback
#' to the bare number mirrors `EngineBase._describe_classes`, which does the same - so a
#' report never loses an index it cannot name.
#'
#' Derived here rather than returned by the engine because the specification is R's own and
#' asking for it would mean a release and a pin move for a label. What holds the two together
#' is a test: the engine's refusal names the same region, so R's naming is compared against
#' that sentence rather than against an opinion.
#'
#' @keywords internal
#' @noRd
named_classes <- function(spec, indices) {
  indices <- unique(as.integer(indices))
  out <- stats::setNames(as.character(indices), as.character(indices))
  regions <- as.list(spec)$data$regions
  if (!length(regions) || !length(indices)) return(out)
  names_given <- vapply(regions, function(region) as.character(region$name), character(1))
  inside <- indices >= 0L & indices < length(names_given)
  out[inside] <- names_given[indices[inside] + 1L]
  out
}

#' What the colormap or labels match in your masks
#'
#' Reads a sample of one split's masks and reports what the specification's colours, or
#' list of labels, actually matched. Trains nothing and loads no model.
#'
#' [platypus_fit()] does a small version of this before every run and refuses when a
#' declared class appears in none of the masks it read. This is the same question asked
#' deliberately, over as much of the data as you want - which is what to reach for when
#' that refusal looks wrong.
#'
#' @section What the numbers mean:
#'
#' `missing_classes` is the one to act on. A class that appears in no mask cannot be
#' learned: its channel of the target is zero everywhere, so there is no gradient towards
#' it and the model is never shown the thing it is being asked to find. Either the colours
#' do not describe these masks, or they name a class the data does not contain.
#'
#' **With `regions` the classes are named rather than numbered**, because a position is the
#' one thing a reader cannot resolve: `missing_classes: 1` means the second region, and
#' counting entries in a configuration file to find out which is the step nobody takes. The
#' positions are still there, as the `missing` and `present` attributes.
#'
#' That naming matters most for the one failure `regions` invites: `of = 3` against a label
#' map holding `4` is a channel of zeros, so the model trains to predict nothing and scores a
#' Dice of 0 for that region while every other number in the run looks ordinary. The engine
#' refuses it before training and names the region; this is how to ask the same question over
#' more of the data than the refusal reads.
#'
#' `unmatched` is the fraction of mask pixels matching no entry, which fall back to the
#' background class. **Read it knowing that it scales with the size of the thing being
#' segmented**, so it is loud for a large structure and almost silent for a small lesion.
#' Measured on masks that are white, with a colormap asking for a colour that is not
#' there: a foreground covering 20% of the image gives 19.8%, and one covering 0.6% gives
#' 0.61% - which is less than the 0.72% that JPEG compression leaves around the edge of a
#' perfectly correct mask. That is why the refusal is built on class presence instead.
#'
#' @param spec A [platypus_spec()].
#' @param split `"train"`, `"validation"` or `"test"`.
#' @param limit How many masks to read. They are spread across the split rather than
#'   taken from its start, because datasets arrive sorted and a prefix would answer about
#'   the beginning.
#' @return A one-row data frame: `unmatched`, `samples_checked`, `total_samples`, and
#'   `present_classes` and `missing_classes` as comma-separated strings so the frame
#'   stays printable - **region names where the specification gave `regions`**, and class
#'   numbers otherwise, which is what the engine's own refusal does. The positions are
#'   attached as integer vectors in the attributes `present` and `missing` either way, so
#'   anything reading them keeps working.
#' @export
#' @examples
#' \dontrun{
#' inspect_masks(spec)
#' inspect_masks(spec, split = "validation", limit = 2000)
#' }
inspect_masks <- function(spec, split = c("train", "validation", "test"), limit = 500) {
  if (!inherits(spec, "platypus_spec")) {
    stop("`spec` must come from `platypus_spec()`; see `?platypus_spec`.", call. = FALSE)
  }
  split <- match.arg(split)
  result <- shim()$inspect_masks(spec$py, split = split, limit = as.integer(limit))
  if (!isTRUE(result$ok)) abort_engine(result)

  present <- as.integer(unlist(result$present_classes))
  missing <- as.integer(unlist(result$missing_classes))
  named <- named_classes(spec, c(present, missing))
  out <- data.frame(
    split = split,
    unmatched = as.numeric(result$unmatched),
    samples_checked = as.integer(result$samples_checked),
    total_samples = as.integer(result$total_samples),
    present_classes = paste(named[as.character(present)], collapse = ", "),
    # An empty string rather than NA: nothing missing is a result, not an absence of one.
    missing_classes = paste(named[as.character(missing)], collapse = ", "),
    stringsAsFactors = FALSE
  )
  attr(out, "present") <- present
  attr(out, "missing") <- missing
  out
}
