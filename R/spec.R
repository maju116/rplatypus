# The specification: the one thing R and Python agree on.
#
# Built from arguments or read from a YAML file, and nothing downstream can tell which.
# That is the whole contract - a colleague can hand you their configuration file, you can
# hand them your R script, and both describe the same experiment.

#' Where the images and masks are
#'
#' Two layouts. `nested_dirs` expects one directory per sample containing an `images` and
#' a `masks` subdirectory - the Data Science Bowl arrangement, where a sample may hold
#' dozens of separate mask files that are combined into one. `config_file` expects a CSV
#' with `images` and `masks` columns, several paths per cell if needed, resolved relative
#' to the file itself so a configuration travels with its data.
#'
#' Classes are named one of two ways, and exactly one of them. `colormap` is for masks
#' stored as pictures: a list of RGB triples where position is the class index. `labels` is
#' for masks stored as label maps - a vector of the voxel values, in class order - which is
#' how every volume format stores them, and how a single-channel PNG can be read as well.
#'
#' A sample that is missing its masks is an error, not a warning - a warning in a loop over
#' five hundred directories is a warning nobody reads.
#'
#' @param train,validation Paths to the training and validation data. A
#'   [split_dataset()] may be given as `train` on its own: it carries all three
#'   paths and selects `config_file` mode, so a split needs no unpacking.
#'
#'   **`validation = FALSE` says this run has no validation set**, which is the third and
#'   last answer to the question `validation` and `split` both answer - a final fit on
#'   every case you have, once the hyperparameters are settled. It goes in this argument
#'   rather than a new one because it is the same question, and a second argument could
#'   contradict the first.
#'
#'   Leaving `validation` and `split` *both* unset is still an error, and that is
#'   deliberate: "I have no validation set" and "I forgot" look identical, and only one of
#'   them is a decision.
#' @param test Optional test data. Only images are read from it.
#' @param split Divide `train` instead of naming a `validation` set: a list with
#'   `fractions` (two numbers, or three to cut a test set as well) and `group_by`. Exactly
#'   one of `split`, `validation`, and `validation = FALSE`.
#'
#'   **`group_by` has to be given, even as `NULL`.** It is a regular expression read
#'   against each sample's name, and everything sharing a group lands in a single split -
#'   usually a patient, sometimes a study or a scanner. `NULL` divides by file instead, and
#'   is a perfectly good answer when the images are independent.
#'
#'   It is required rather than optional because the mistake it prevents leaves no trace:
#'   slices of one patient in training and validation at once make validation measure
#'   memory rather than generalisation, and the score comes out several points too high
#'   with nothing in the output to say so.
#'
#'   Nothing is written. [split_dataset()] is still the way when the three CSV files are
#'   the point - to keep, to hand to a colleague, to cite - and its result can be passed
#'   straight to `train`.
#' @param colormap A list of RGB triples, one per class, background first. For masks stored
#'   as pictures. Give this or `labels`, not both.
#' @param labels The voxel value of each class, in class order, for masks stored as label
#'   maps - `c(0, 1)` for a binary segmentation, `c(0, 1, 2)` where 1 is liver and 2 is
#'   tumour. This is how NIfTI and every other volume format label anything. Give this or
#'   `colormap`, not both.
#'
#'   **Include 0 unless the masks really do fill every voxel.** A value matching no entry
#'   falls back to the first class, so a list without 0 trains the background as whatever
#'   that first class is. The engine refuses that combination rather than let it look
#'   plausible, which means the error arrives before the run and not in the scores.
#' @param mode `"nested_dirs"` or `"config_file"`.
#' @param window How values in real units reach the model. A named window - `"lung"`,
#'   `"soft_tissue"`, `"bone"`, `"brain"`, `"abdomen"`, `"liver"`, `"mediastinum"`,
#'   `"subdural"`, `"stroke"` - or an explicit `c(centre, width)` in Hounsfield units, or
#'   `"auto"` for the window the file recorded, which only DICOM has, or `"full"` for the
#'   whole range present. Applies to DICOM and to NIfTI; ignored for ordinary pictures,
#'   which are already 0-255.
#'
#'   Worth choosing rather than leaving: a fixed window is what makes two scans comparable.
#'   Scaling each scan by its own darkest and brightest voxel lets a single metal implant or
#'   marker rescale everything else in it.
#'
#'   `NULL`, the default, sends nothing and lets the engine decide - which also keeps
#'   ordinary image work running against an engine too old to know the setting exists.
#' @param dicom_window The former name of `window`, still accepted. It was accurate while
#'   DICOM was the only format that needed it.
#' @param channels_from For datasets that keep one channel per file: one pattern per channel,
#'   in channel order. BraTS ships four MRI sequences per patient - T1, T1 after contrast, T2
#'   and FLAIR - because different tumour structures are visible in different sequences;
#'   satellite sets keep their bands apart the same way.
#'
#'   The order is stated rather than inferred, and that is the point. Sorted, the BraTS names
#'   come out flair, t1, t1ce, t2 - reproducible and anatomically meaningless. A model trained
#'   with FLAIR in channel one and used on data whose channel one is T1 returns a plausible
#'   answer with the right shape and the right range, and nothing further down can notice.
#'
#'   Patterns are Python regular expressions, like `group_by` in [split_dataset()], and R's
#'   own quoting applies: `c("_t1\\.nii", "_t1ce\\.nii", "_t2\\.nii", "_flair\\.nii")`.
#'   Each must match exactly one of a sample's files - `"_t1"` would match both `_t1.nii.gz`
#'   and `_t1ce.nii.gz`, which is an error rather than a race - and every file must be claimed
#'   by some pattern, because one left out is data the model never sees.
#' @param target_spacing For volumes: resample every scan to this many millimetres per voxel,
#'   then centre-crop or pad to the model's `input_shape`. Without it a volume is simply
#'   resized into that shape, which is only harmless when every scan covers the same amount of
#'   the patient - and clinical scans do not. Forty slices of 1 mm is 40 mm of patient and
#'   forty of 2.5 mm is 100 mm, so resizing alone leaves the same organ a different size in
#'   each, and nothing in the data says so.
#'
#'   `c(1, 1, 1)` is the usual starting point. Ignored for 2D.
#' @param subdirs For `nested_dirs`, the names of the image and mask subdirectories.
#' @param column_sep For `config_file`, what separates several paths in one cell.
#' @param shuffle Shuffle the training data between epochs.
#' @return A data specification, to be passed to [platypus_spec()].
#' @export
#' @examples
#' segmentation_data("train/", "valid/", colormap = binary_colormap)
segmentation_data <- function(train, validation = NULL, colormap = NULL, labels = NULL,
                              test = NULL, split = NULL,
                              mode = c("nested_dirs", "config_file"),
                              window = NULL, dicom_window = NULL, target_spacing = NULL,
                              channels_from = NULL,
                              subdirs = c("images", "masks"), column_sep = ";",
                              shuffle = TRUE) {
  # Which of these the caller actually named. Everything below sends a field only when
  # somebody chose it or when this function chose it for them, because a default sent from
  # here is indistinguishable from a value the user set - and §3D's rule exists for a
  # reason: an R-side default silences a schema, or a weights file, that knows better.
  # Measured 2026-10-11: all four matched the engine's own defaults, so dropping them
  # changes nothing today. The point is the day one of them stops matching.
  explicit_mode <- !missing(mode)
  gave <- list(
    subdirs = !missing(subdirs),
    column_sep = !missing(column_sep),
    shuffle = !missing(shuffle)
  )
  mode <- match.arg(mode)

  # A split goes straight in. Making the caller unpack three paths and remember to switch
  # to config_file mode would be three chances to get it wrong, in the one place where a
  # mistake means training and validating on the same patient.
  if (inherits(train, "platypus_split")) {
    if (!is.null(validation)) {
      stop("`train` is already a platypus_split, which carries the validation set; ",
           "leave `validation` unset.", call. = FALSE)
    }
    if (!is.null(split)) {
      stop("`train` is already a platypus_split, so it carries the division; `split` ",
           "would divide it a second time. Give one or the other.", call. = FALSE)
    }
    # Named `done` rather than `split`, which is now an argument of this function: a
    # platypus_split is a division already performed, and `split` is a request to perform
    # one. Reusing the name made a correct call look like both at once.
    done <- train
    train <- done$train_path
    validation <- done$validation_path
    if (is.null(test)) test <- done$test_path
    if (!explicit_mode) mode <- "config_file"
  }

  check_split(validation, split, test)

  # Caught here rather than in the engine, because the message is the same and this way it
  # costs nothing: no interpreter starts to tell someone they gave both or neither.
  if (is.null(colormap) == is.null(labels)) {
    stop("give exactly one of `colormap` (masks stored as pictures) and `labels` ",
         "(masks stored as label maps, which is how volumes do it).", call. = FALSE)
  }
  if (!is.null(window) && !is.null(dicom_window)) {
    stop("`dicom_window` is the former name of `window`; give one of them, not both.",
         call. = FALSE)
  }
  if (!is.null(dicom_window)) window <- dicom_window
  if (!is.null(channels_from) && length(channels_from) < 2L) {
    stop("`channels_from` needs one pattern per channel, so at least two. With a single ",
         "channel there is nothing to order.", call. = FALSE)
  }
  if (!is.null(channels_from) && anyDuplicated(channels_from)) {
    stop("`channels_from` patterns must be distinct - two channels matching the same file ",
         "would make one measurement into two.", call. = FALSE)
  }
  if (!is.null(target_spacing) &&
        (length(target_spacing) != 3L || anyNA(target_spacing) || any(target_spacing <= 0))) {
    stop("`target_spacing` must be three positive numbers, in millimetres.", call. = FALSE)
  }

  list(
    train_path = train,
    # FALSE is not a path. It travels as the engine's own `validation` flag, and
    # `validation_path` stays absent - sending both would be the contradiction the engine
    # refuses, from the one place that knows they are the same question.
    validation_path = if (isFALSE(validation)) NULL else validation,
    validation = if (isFALSE(validation)) FALSE else NULL,
    test_path = test,
    # Not `compact()` here, deliberately. `group_by = NULL` is the whole point of the
    # field - "divide by file, and I know it" - and compacting would drop it, leaving the
    # engine to refuse a key the caller did write. The one case where an absent value and
    # a NULL value are different things, so the list is assembled by hand.
    split = split_block(split),
    # Sent when the caller named it, or when the `platypus_split` branch above chose
    # `config_file` on their behalf - R deciding is as good a reason as the user deciding,
    # and the engine cannot tell them apart anyway.
    mode = if (explicit_mode || !identical(mode, "nested_dirs")) mode else NULL,
    colormap = if (is.null(colormap)) NULL else lapply(colormap, as.integer),
    labels = if (is.null(labels)) NULL else as.integer(labels),
    # Left out entirely when unset. An older engine rejects fields it does not know, so
    # sending a default nobody asked for would break every run that has nothing to do
    # with DICOM - and the version pin exists precisely to make such mismatches loud
    # rather than mysterious.
    # Aligned under the `if` it continues: the chain reads as one decision.
    window = if (is.null(window)) NULL
             else if (is.character(window)) window  # nolint: indentation_linter.
             else as.numeric(window),
    target_spacing = if (is.null(target_spacing)) NULL else as.numeric(target_spacing),
    channels_from = if (is.null(channels_from)) NULL else as.character(channels_from),
    subdirs = if (gave$subdirs) subdirs else NULL,
    column_sep = if (gave$column_sep) column_sep else NULL,
    shuffle = if (gave$shuffle) shuffle else NULL
  )
}

#' Colormaps and their labels
#'
#' `binary_colormap` is black background, white foreground: the ordinary two-class
#' problem. `voc_colormap` is the twenty-one class palette used by Pascal VOC, kept
#' because datasets and other people's masks still arrive in it.
#'
#' The labels are the matching class names, for figure legends and [mask_coverage()].
#' Position in the list is the class index throughout, counting from 1.
#'
#' @format A list of RGB triples, or a character vector of names.
#' @returns Four exported objects rather than functions. `binary_colormap` and
#'   `voc_colormap` are lists of integer vectors of length three - one RGB triple per
#'   class, 2 entries and 21 entries respectively - where position in the list is the class
#'   index, counting from 1. `binary_labels` and `voc_labels` are character vectors of the
#'   matching class names, the same length as their colormap and in the same order, so the
#'   nth label names the class the nth triple draws.
#' @name colormaps
#' @examples
#' mask_coverage(matrix(c(1, 2, 2, 1), 2), labels = binary_labels)
NULL

#' @rdname colormaps
#' @export
binary_colormap <- list(c(0L, 0L, 0L), c(255L, 255L, 255L))

#' @rdname colormaps
#' @export
binary_labels <- c("background", "object")

#' @rdname colormaps
#' @export
voc_colormap <- list(
  c(0L, 0L, 0L),       c(128L, 0L, 0L),     c(0L, 128L, 0L),     c(128L, 128L, 0L),
  c(0L, 0L, 128L),     c(128L, 0L, 128L),   c(0L, 128L, 128L),   c(128L, 128L, 128L),
  c(64L, 0L, 0L),      c(192L, 0L, 0L),     c(64L, 128L, 0L),    c(192L, 128L, 0L),
  c(64L, 0L, 128L),    c(192L, 0L, 128L),   c(64L, 128L, 128L),  c(192L, 128L, 128L),
  c(0L, 64L, 0L),      c(128L, 64L, 0L),    c(0L, 192L, 0L),     c(128L, 192L, 0L),
  c(0L, 64L, 128L)
)

#' @rdname colormaps
#' @export
voc_labels <- c(
  "background", "aeroplane", "bicycle", "bird", "boat", "bottle", "bus", "car", "cat",
  "chair", "cow", "diningtable", "dog", "horse", "motorbike", "person", "potted plant",
  "sheep", "sofa", "train", "tv/monitor"
)

#' The named CT windows
#'
#' The windows radiologists use, as `c(centre, width)` in Hounsfield units. Pass a name to
#' [segmentation_data()] rather than the numbers; this is here for looking them up.
#'
#' Held here rather than fetched from the engine so that looking up a constant does not
#' require starting Python. A test checks the two lists against each other whenever the
#' engine is available, so the copy cannot quietly drift.
#'
#' @return A named list of `c(centre, width)` pairs.
#' @export
#' @examples
#' ct_windows()$lung
#' ct_windows()[["soft_tissue"]]
ct_windows <- function() {
  list(
    brain       = c(centre = 40,   width = 80),
    subdural    = c(centre = 75,   width = 215),
    stroke      = c(centre = 32,   width = 8),
    bone        = c(centre = 400,  width = 1800),
    soft_tissue = c(centre = 40,   width = 400),
    abdomen     = c(centre = 60,   width = 400),
    liver       = c(centre = 30,   width = 150),
    lung        = c(centre = -600, width = 1500),
    mediastinum = c(centre = 50,   width = 350)
  )
}

#' Build an experiment specification
#'
#' Either from arguments, or from a YAML file by passing its path as the only argument.
#' Both produce the same object, and everything downstream treats them identically.
#'
#' The engine validates it, so a mistake is caught here rather than part-way through a
#' training run - and reported against the model that has it, by the name you gave it.
#'
#' @param data A [segmentation_data()], [detection_data()] or [instance_data()]
#'   specification, or the path to a YAML file. Which one it is decides `task`.
#' @param models A list of model specifications, see [models] and [available_models()].
#'   More than one is the ordinary case rather than the exception: they are trained in turn
#'   against the same data and the same split, which is what makes their numbers
#'   comparable, and a comparison is written by listing several entries of the same
#'   architecture with different settings.
#' @param task Which task this specification describes, one of `"semantic_segmentation"`,
#'   `"object_detection"` or `"instance_segmentation"`. Normally left unset: the data and
#'   model constructors already decide it, and `segmentation_data()` with `u_net()` can only
#'   mean one thing. Given, it is **checked against them rather than trusted**, so it can
#'   only agree or refuse.
#'
#'   The third task sharpened what this argument is for rather than making it load-bearing.
#'   An instance *data* block declares nothing a segmentation one lacks, so
#'   [instance_data()] is what says the word - but a *model* can still say it on its own,
#'   because `separation` is required on an instance model and has no counterpart on a
#'   semantic one.
#' @param seed Makes a run repeatable as far as the arithmetic is deterministic, which goes
#'   further on some hardware than others - so it is worth knowing where it stops.
#'
#'   **Repeatable:** the split ([split_dataset()] gives the same partition on any machine), a
#'   detector's fitted anchors, the order the data arrives in and its augmentation - including
#'   inside the loader's worker processes - and, on the processor, every number to twelve
#'   decimal places.
#'
#'   **Not repeatable:** a run on a CUDA device. Measured on a GTX 1070, two runs of one
#'   configuration at one seed agreed to twelve decimals on the processor and differed in the
#'   fourth after a single epoch on the card, because cuDNN chooses algorithms neither package
#'   constrains. Nor across versions of the engine: anything that changes the order data is
#'   drawn in changes what one seed draws, and `0.8.0a3` did exactly that.
#'
#'   So it is the argument for comparing two of your own runs, and not for publishing a number
#'   somebody else can land on. [platypus_device()] reports which device yours will use.
#' @param deterministic Ask the engine for deterministic algorithms as well, which is the only
#'   thing that makes a run on a card repeatable - `seed` on its own does not, as above.
#'
#'   **The cost is real and arrives later than any other refusal here.** Some convolutions
#'   become much slower, and an operation with no deterministic implementation raises *when it
#'   is reached*, so a run can stop ten minutes in rather than when the specification is
#'   built. Everything else this package refuses, it refuses before reading a single image;
#'   this cannot, because whether an operation has a deterministic algorithm is a fact about
#'   the installed engine and the device rather than about the specification.
#'
#'   Needs `seed`, and is refused without one: constraining the algorithms while the draw
#'   still varies leaves the run exactly as unrepeatable and only slower.
#' @param output_dir Where to write a record of the run: the specification, the history,
#'   and anything the run worked out that the specification does not already say - a
#'   detector's fitted anchors, which it cannot be reloaded without. `NULL`, the default,
#'   writes nothing.
#'
#'   Unset means *nothing is written*, not "written to a default place". A field with a
#'   default cannot be told apart from one somebody set to that default, so sending the
#'   default from here would have put files in every user's working directory the moment
#'   the engine learned to write them - which it just did.
#' @param check_paths Verify that the data paths exist. Turn it off to build a
#'   specification on a machine that does not hold the data.
#' @return A `platypus_spec`.
#' @export
#' @examples
#' \dontrun{
#' spec <- platypus_spec(
#'   data = segmentation_data("train/", "valid/", colormap = binary_colormap),
#'   models = list(
#'     u_net("unet", input_shape = c(256, 256)),
#'     linknet("linknet", input_shape = c(256, 256), loss = loss_focal_tversky(alpha = 0.7))
#'   )
#' )
#'
#' # The same thing, from a file
#' spec <- platypus_spec("experiment.yaml")
#' }
platypus_spec <- function(data, models = NULL, task = NULL, seed = NULL,
                          deterministic = NULL, output_dir = NULL, check_paths = TRUE) {
  from_file <- is.character(data) && length(data) == 1L && is.null(models)

  result <- if (from_file) {
    shim()$load_spec(path.expand(data), check_paths = check_paths)
  } else {
    if (is.null(models) || !length(models)) {
      stop("`models` must contain at least one model; see `?models`.", call. = FALSE)
    }
    task <- agreed_task(data, models, stated = task)
    config <- compact(list(
      # Always sent. The engine requires it, and even when it did not, a request that
      # leaves it out is one whose meaning depends on the version reading it.
      task = task,
      data = data, models = models,
      seed = int1(seed), deterministic = deterministic, output_dir = output_dir
    ))
    shim()$build_spec(config, check_paths = check_paths)
  }

  if (!isTRUE(result$ok)) abort_engine(result)
  new_spec(result$spec, source = if (from_file) data else NULL)
}

new_spec <- function(py_spec, source = NULL) {
  structure(
    list(py = py_spec, source = source),
    class = "platypus_spec"
  )
}

#' @export
print.platypus_spec <- function(x, ...) {
  info <- shim()$spec_as_dict(x$py)
  models <- info$models
  cat("platypus specification\n")
  if (!is.null(x$source)) cat("  from        :", x$source, "\n")
  cat("  data        :", info$data$train_path, "\n")
  cat("  classes     :", length(info$data$colormap), "\n")
  cat("  models      :", length(models), "\n")
  for (m in models) {
    shape <- paste(unlist(m$input_shape), collapse = "x")
    tiles <- if (!is.null(m$splits)) {
      paste0(", tiled ", paste(unlist(m$splits), collapse = "x"))
    } else {
      ""
    }
    cat(sprintf("    %-14s %-16s %s%s, %s, %d epochs\n",
                m$name, m$architecture, shape, tiles, m$loss$name, m$epochs))
  }
  invisible(x)
}

#' Turn a specification back into plain R data
#'
#' Useful for looking at what the engine made of your arguments, and for writing it out.
#' @param x A `platypus_spec`.
#' @param ... Unused.
#' @return A nested list.
#' @export
#' @examples
#' \dontrun{
#' str(as.list(spec))
#'
#' # The same thing a YAML file would hold, which is the point: a configuration file
#' # and this code describe the same run. `yaml::write_yaml(as.list(spec), "run.yaml")`
#' # produces a file the Python engine reads directly.
#' }
as.list.platypus_spec <- function(x, ...) shim()$spec_as_dict(x$py)

#' Drop empty entries so the engine's own defaults apply
#'
#' R keeps a `NULL` in a list rather than dropping it, so an argument left unset would
#' otherwise cross over as an explicit `None` and overwrite whatever default the engine
#' has. Recursive, because specifications nest.
#' @keywords internal
#' @noRd
compact <- function(x) {
  if (!is.list(x)) return(x)
  # Sent exactly as built. Everywhere else a NULL means "not asked for" and dropping it
  # lets the engine's default apply - but `split$group_by = NULL` is a stated answer,
  # "divide by file, and I know it", and the engine requires the key precisely so that
  # nobody can leave that question unanswered. Compacting it away would turn a choice the
  # caller made into a refusal they could not explain.
  if (inherits(x, "platypus_verbatim")) return(x)
  x <- lapply(x, compact)
  x[!vapply(x, function(v) is.null(v) || (is.list(v) && !length(v)), logical(1))]
}


#' The one task a specification describes, or a refusal naming the disagreement
#'
#' Inferred from the objects rather than asked for: `detection_data()` and `yolo3()` carry
#' it, and a user who chose them has said which they meant twice already.
#'
#' Caught here rather than across the bridge because the engine's refusal would be
#' "data.classes: Extra inputs are not permitted", which describes the symptom. Mixing a
#' detection data block with a segmentation model is not a stray field, it is two
#' intentions in one specification.
#'
#' @noRd
agreed_task <- function(data, models, stated = NULL) {
  from_data <- task_of(data)
  from_models <- vapply(models, task_of, character(1))
  all_tasks <- unique(c(from_data, from_models))

  # `task` is derived rather than typed, because `segmentation_data()` with `u_net()` can
  # only mean one thing and saying it again could only ever disagree. It can still be
  # stated - and then it is checked, not trusted.
  #
  # This used to predict that instance segmentation would end that, and that the constructors
  # would stop deciding on their own. Engine 0.8.0a20 arrived with the task and the prediction
  # was half right, which is why it is corrected here rather than deleted. The *data*
  # constructor does stop deciding: an instance data block declares nothing a segmentation one
  # lacks and requires the same fields, so no data block can tell the two apart. The *model*
  # constructor does not - `separation` is required on an instance model and has no
  # counterpart on a semantic one - so a model still names its task and cannot leave it unsaid.
  #
  # So this argument keeps the job it has. Instances arrive as `instance_data()`, tagged the
  # way `detection_data()` tags itself, and what that constructor is for is the five fields it
  # refuses - `colormap`, `labels`, `regions`, `channels_from`, `target_spacing` - rather than
  # any it adds. `known` below gained "instance_segmentation" with that constructor and not
  # before, because a value nothing can produce would only ever reach the disagreement error.
  if (!is.null(stated)) {
    stated <- as.character(stated)[[1L]]
    known <- c("semantic_segmentation", "object_detection", "instance_segmentation")
    if (!stated %in% known) {
      renamed <- c(segmentation = "semantic_segmentation", detection = "object_detection")
      if (stated %in% names(renamed)) {
        stop("`task = \"", stated, "\"` was renamed to \"", renamed[[stated]],
             "\". Both tasks are spelled out now, because \"segmentation\" stops naming ",
             "one thing as soon as instance segmentation exists.", call. = FALSE)
      }
      stop("`task` must be one of ", paste(dQuote(known, FALSE), collapse = " or "),
           "; got \"", stated, "\".", call. = FALSE)
    }
    if (length(all_tasks) == 1L && !identical(stated, all_tasks)) {
      stop("`task = \"", stated, "\"` disagrees with what this specification is built ",
           "from, which is ", all_tasks, ". The data and model constructors decide the ",
           "task; stating it is a way of being explicit, not a way of changing it.",
           call. = FALSE)
    }
  }

  if (length(all_tasks) == 1L) return(all_tasks)

  named <- vapply(seq_along(models), function(i) {
    name <- models[[i]][["name"]]
    sprintf("%s is %s", if (is.null(name)) paste0("models[[", i, "]]") else name,
            from_models[[i]])
  }, character(1))
  stop("a specification describes one task, and this one mixes them: the data is ",
       from_data, " while ", paste(named, collapse = ", "), ".\n",
       "  Masks and boxes are not the same pipeline, so there is nothing to reconcile - ",
       "use `segmentation_data()` with `u_net()` and friends, or `detection_data()` with ",
       "`yolo3()`.", call. = FALSE)
}


#' Exactly one way of getting a validation set, checked the same for both tasks
#'
#' Shared because the rule is the same and a rule in two places is a rule that drifts. The
#' messages are caught in R rather than left to the engine for the reason the colormap
#' check is: no interpreter needs to start in order to say this.
#'
#' @param validation,split,test As given to the data constructor.
#' @return `TRUE`, invisibly, or an error.
#' @keywords internal
#' @noRd
check_split <- function(validation, split, test) {
  # `validation = FALSE` is the third answer, and it fits in the same argument because the
  # question is the same one: where does the validation set come from, and the answer may be
  # "there is not one". A second argument saying it could contradict the first.
  if (isFALSE(validation)) {
    if (!is.null(split)) {
      stop("`validation = FALSE` says this run has no validation set, and `split` says ",
           "where it comes from. Give one or the other.", call. = FALSE)
    }
    return(invisible(NULL))
  }
  if (is.null(validation) == is.null(split)) {
    stop("a run needs something to validate against: give `validation`, or `split` to ",
         "divide `train` itself.\n  `split` takes `fractions` (two or three) and ",
         "`group_by`, which keeps a patient out of both halves - dividing by file does ",
         "not, and the score then comes out several points too high with nothing to say so.",
         "\n  To train on everything and measure nothing - a final fit once the ",
         "hyperparameters are settled - say `validation = FALSE`. It is a decision and has ",
         "to be written down rather than arrived at by leaving both unset.",
         call. = FALSE)
  }
  if (!is.null(split)) {
    if (!is.list(split) || is.null(split$fractions)) {
      stop("`split` is a list with `fractions` and `group_by`, for example ",
           "list(fractions = c(0.8, 0.2), group_by = NULL).", call. = FALSE)
    }
    if (!"group_by" %in% names(split)) {
      stop("`split` must say `group_by`, even as NULL. A group is usually a patient and ",
           "everything sharing one lands in a single split; NULL divides by file instead.",
           "\n  Required rather than optional because the mistake it prevents is invisible: ",
           "slices of one patient on both sides make validation measure memory rather than ",
           "generalisation.", call. = FALSE)
    }
    if (!is.null(test)) {
      stop("`test` and `split` both say where the test set comes from; give a third number ",
           "to `split$fractions` instead, or drop `test`.", call. = FALSE)
    }
  }
  invisible(TRUE)
}

#' The split block, as the engine wants it
#'
#' Built by hand rather than with `compact()`: `group_by = NULL` is a stated answer and
#' compacting would drop it, leaving the engine to refuse a key the caller did write. The
#' one place in this package where an absent value and a NULL value differ.
#' @noRd
split_block <- function(split) {
  if (is.null(split)) return(NULL)
  structure(
    c(list(fractions = as.numeric(split$fractions)),
      list(group_by = split$group_by),
      if (is.null(split$seed)) list() else list(seed = int1(split$seed))),
    class = c("platypus_verbatim", "list")
  )
}


#' Write a specification back out as YAML
#'
#' [platypus_spec()] reads a YAML file and builds a specification from arguments. This is the
#' way back, so the two are one pipeline rather than one and a half: a specification assembled
#' in R becomes a file somebody else can run, or that a script can keep beside its results.
#'
#' **It writes what you set, not what the specification holds.** A model built from two
#' arguments holds 29 fields once the engine has filled in its defaults, and writing all of
#' them is not merely verbose - it changes what the file does. A model given `weights` and no
#' `architecture` takes the architecture from the weights sidecar, and that adoption happens
#' precisely because the field was never set. Freeze the defaults into the file and the
#' adoption can never happen again: the file looks like the original and quietly stops doing
#' what the original did.
#'
#' `defaults = TRUE` is the opposite want, and a legitimate one: freeze this run exactly as it
#' resolved so it reproduces years from now. The cost is the paragraph above, by design.
#'
#' @param spec A `platypus_spec`, from [platypus_spec()].
#' @param path Where to write it. The parent directory must exist.
#' @param defaults Write every field at its resolved value, including the ones you never set.
#' @return The path, invisibly.
#' @seealso [platypus_spec()], which reads one back, and [read_record()] for what a run *did*
#'   as opposed to what it was asked to do.
#' @export
#' @examples
#' \dontrun{
#' spec <- platypus_spec(
#'   data = segmentation_data("train/", "valid/", colormap = binary_colormap),
#'   models = list(u_net("unet", input_shape = c(256, 256)))
#' )
#'
#' save_spec(spec, "experiment.yaml")
#' identical(as.list(platypus_spec("experiment.yaml")), as.list(spec))
#'
#' # Everything the engine resolved, for a run that has to reproduce in five years.
#' save_spec(spec, "frozen.yaml", defaults = TRUE)
#' }
save_spec <- function(spec, path, defaults = FALSE) {
  if (!inherits(spec, "platypus_spec")) {
    stop("`spec` must be a platypus_spec; see `?platypus_spec`.", call. = FALSE)
  }
  if (!is.character(path) || length(path) != 1L || !nzchar(path)) {
    stop("`path` must be a single file path.", call. = FALSE)
  }
  result <- shim()$save_spec(spec$py, path.expand(path), defaults = isTRUE(defaults))
  if (!isTRUE(result$ok)) abort_engine(result)
  invisible(result$path)
}
