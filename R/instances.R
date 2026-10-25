#' Data for instance segmentation: tell the objects apart, not just find them
#'
#' Masks stored one file per object, read as a label map that keeps each object's identity
#' instead of uniting them into one foreground. The question this answers is *how many
#' nuclei, and how big is each one*, which a semantic mask cannot answer however good it is:
#' two touching nuclei are one region in it.
#'
#' **Why this exists rather than an argument on [segmentation_data()].** Every field
#' `instance_data()` takes, that one takes too - what makes it a different constructor is
#' the five it **refuses**: `colormap`, `labels`, `regions`, `channels_from` and
#' `target_spacing` do not apply to a directory of per-object masks, and the engine rejects
#' them by name. A constructor whose contract is "these five do not apply" is a contract
#' rather than a label, and it gets that refusal from its own argument list rather than from
#' a table somebody has to keep in step.
#'
#' The consequence worth knowing before you choose: `task` is still read off the
#' constructors rather than typed. Calling this one *is* how a specification says it is
#' about instances, so there is no `task = "instance_segmentation"` to write and nothing to
#' keep in agreement with it. See [platypus_spec()].
#'
#' What the model does with this is the other half, and it is one block: a model's
#' `separation` says what the network predicts - `rim` or `flows` - and `decode` says how
#' those channels become objects. Neither belongs here, because they describe the run and
#' not the data.
#'
#' @param train Training data: a directory, a configuration file, or a `platypus_split`
#'   from [split_dataset()], which carries its own validation set and division.
#' @param validation A validation set, or `FALSE` for none. Exactly one of `validation` and
#'   `split`, and neither when `train` is already a `platypus_split`.
#' @param test A test set to predict on. Scored only if it carries masks.
#' @param split Divide `train` instead of naming a `validation` set: a list with
#'   `fractions` (two numbers, or three to cut a test set too) and `group_by`, which is
#'   required and may be `NULL`. Exactly one of `split` and `validation`.
#' @param mode `"nested_dirs"` or `"config_file"`.
#' @param window How values in real units reach the model, for DICOM and NIfTI. See
#'   [segmentation_data()].
#' @param subdirs For `nested_dirs`, the names of the image and mask subdirectories. The
#'   second one holds **one file per object** rather than one mask per image, which is the
#'   layout this task is named for.
#' @param column_sep For `config_file`, what separates several paths in one cell.
#' @param shuffle Shuffle the training data between epochs.
#' @return A data specification, to be passed to [platypus_spec()].
#' @seealso [segmentation_data()] for one mask per image, [platypus_spec()]
#' @export
#' @examples
#' instance_data("stage1_train/", "stage1_validation/")
instance_data <- function(train, validation = NULL, test = NULL, split = NULL,
                          mode = c("nested_dirs", "config_file"),
                          window = NULL,
                          subdirs = c("images", "masks"), column_sep = ";",
                          shuffle = TRUE) {
  # Which of these the caller actually named: a field is sent only when somebody chose it,
  # because a default sent from here is indistinguishable from a value the user set and an
  # R-side default silences a schema that knows better. §3D's rule, and the same `gave`
  # list `segmentation_data()` keeps for the same reason.
  explicit_mode <- !missing(mode)
  gave <- list(
    subdirs = !missing(subdirs),
    column_sep = !missing(column_sep),
    shuffle = !missing(shuffle)
  )
  mode <- match.arg(mode)

  # A split goes straight in, exactly as it does for semantic data: making the caller
  # unpack three paths and remember to switch to config_file mode would be three chances to
  # get it wrong, in the one place where a mistake means training and validating on the
  # same patient.
  if (inherits(train, "platypus_split")) {
    if (!is.null(validation)) {
      stop("`train` is already a platypus_split, which carries the validation set; ",
           "leave `validation` unset.", call. = FALSE)
    }
    if (!is.null(split)) {
      stop("`train` is already a platypus_split, so it carries the division; `split` ",
           "would divide it a second time. Give one or the other.", call. = FALSE)
    }
    done <- train
    train <- done$train_path
    validation <- done$validation_path
    if (is.null(test)) test <- done$test_path
    if (!explicit_mode) mode <- "config_file"
  }

  check_split(validation, split, test)

  structure(
    list(
      train_path = train,
      # FALSE is not a path. It travels as the engine's own `validation` flag and
      # `validation_path` stays absent, because sending both is the contradiction the
      # engine refuses.
      validation_path = if (isFALSE(validation)) NULL else validation,
      validation = if (isFALSE(validation)) FALSE else NULL,
      test_path = test,
      # Not compacted: `group_by = NULL` is the whole point of that field - "divide by
      # file, and I know it" - so an absent value and a NULL value are different things.
      split = split_block(split),
      mode = if (explicit_mode || !identical(mode, "nested_dirs")) mode else NULL,
      # Aligned under the `if` it continues: the chain reads as one decision.
      window = if (is.null(window)) NULL
               else if (is.character(window)) window  # nolint: indentation_linter.
               else as.numeric(window),
      subdirs = if (gave$subdirs) as.character(subdirs) else NULL,
      column_sep = if (gave$column_sep) column_sep else NULL,
      shuffle = if (gave$shuffle) shuffle else NULL
    ),
    class = c("platypus_instance_data", "list"),
    # The tag is the whole mechanism: `task_of()` reads it, `agreed_task()` checks it
    # against the models, and nothing else in a specification has to say the word.
    task = "instance_segmentation"
  )
}

#' What the network predicts, so objects can be told apart
#'
#' One per model, and it decides the head's width and which losses are admissible - both
#' derived by the engine rather than stated here, so there is no channel count to get wrong.
#' Pass the result as a model's `separation`; see [u_net()].
#'
#' `separation_rim()` trains three classes - background, object interior, object rim - and
#' the rim is what separates two touching objects. `separation_flows()` trains a vector
#' field pointing at each object's own sink, so every foreground pixel carries a value and
#' none of them is spent on being a boundary.
#'
#' **What this is worth was measured and it is not flattering.** On the Data Science Bowl's
#' held-out cases the flow route is worth +0.0680 of instance average precision over
#' `decode_connected_components()`, which ignores the signal entirely, and the rim route
#' +0.0640 - while substituting a *perfect mask* is worth +0.2398. So the mask is the limit
#' by a factor of 3.6, and a run that beats the published weights' 0.4888 without reaching
#' 0.7655 has improved its mask and said nothing about separation.
#'
#' There is no `hv`. Its markers lose to a one-pixel erosion on perfect inputs, 0.9382
#' against 0.9807, so naming it would promise a mechanism that was measured as absent.
#'
#' @param width For `rim`, how many pixels wide the rim is, **in the model's input
#'   resolution**. Unset uses the engine's default, which is 2 and stands on an argument
#'   rather than on a measurement: the published sweep peaked at 3 pixels of *source*
#'   resolution, which on a 520-pixel case read at 256 is about 1.5 pixels of model input,
#'   and a sweep in model pixels has not been run.
#' @param mode For `flows`, `"diffusion"` or `"centroid"`. Unset uses the engine's default
#'   of `"diffusion"`, which stands on a measurement: decoded against the truth it reaches
#'   0.9924 where `"centroid"` reaches 0.9478, because a straight line to a centroid leaves
#'   a crescent-shaped object.
#' @param loss For `flows`, the objective for the vector channels, which has to be one
#'   defined over numbers rather than over classes. Unset uses the engine's default.
#' @param weight For `flows`, how much of the total objective the vector half provides.
#' @return A separation block, to be passed as a model's `separation`.
#' @seealso [decodings], [instance_data()]
#' @name separations
#' @examples
#' separation_rim(width = 2)
#' separation_flows(mode = "diffusion")
NULL

#' @rdname separations
#' @export
separation_rim <- function(width = NULL) {
  compact(list(name = "rim", width = int1(width)))
}

#' @rdname separations
#' @export
separation_flows <- function(mode = NULL, loss = NULL, weight = NULL) {
  compact(list(name = "flows", mode = mode, loss = loss, weight = weight))
}

#' How predicted channels become objects
#'
#' A model's `decode` is a **list** of these, not one: several decodings share one forward
#' pass, so a second one costs seconds where a second training run costs an hour.
#' [evaluate()] then returns a row per model and decoding.
#'
#' Each declares which separation it can read, and asking for one that cannot read the
#' model's signal is refused when the specification is built rather than at the end of a
#' run. `decode_connected_components()` reads none of them - it ignores the separation
#' signal entirely - which is exactly why it belongs in every model's list: it is the row
#' the signal's own row has to be read against. Left unset, a model decodes with its own
#' signal's decoding plus that yardstick.
#'
#' @param minimum_area Drop an object smaller than this many pixels. Unset keeps
#'   everything, and that is the engine's default on purpose: the right floor is a property
#'   of the data rather than of the method. A nucleus at 256x256 in the Data Science Bowl
#'   runs from 4 pixels up, so a floor picked here would silently delete the smallest real
#'   objects in one dataset while letting speckle through in another. It is applied after
#'   the objects are formed, so it removes answers rather than changing how they were
#'   reached.
#' @param steps For `decode_follow_flows()`, how many Euler steps each pixel takes.
#'   **Measured as not mattering**: one step scores 0.9914 against 0.9923 converged, a span
#'   below the 0.0013 two runs differ by, because the field is continuous within an object
#'   and diverges at a seam - so the gap between two objects opens on the first step rather
#'   than after many. Adjustable because that argument is about this data's object sizes.
#' @param step_size For `decode_follow_flows()`, how far one step moves, in pixels, on a
#'   unit-length field. **A cliff rather than a speed knob**: 0.9923 at 1, 0.4715 at 2,
#'   0.0303 at 10. A step longer than a pixel jumps over the sink it was converging on and
#'   lands in a neighbour's basin.
#' @return A decoding block, to be passed inside a model's `decode` list.
#' @seealso [separations], [instance_data()]
#' @name decodings
#' @examples
#' list(decode_nearest_seed(), decode_connected_components())
#' decode_follow_flows(step_size = 0.5)
NULL

#' @rdname decodings
#' @export
decode_connected_components <- function(minimum_area = NULL) {
  compact(list(name = "connected_components", minimum_area = int1(minimum_area)))
}

#' @rdname decodings
#' @export
decode_nearest_seed <- function(minimum_area = NULL) {
  compact(list(name = "nearest_seed", minimum_area = int1(minimum_area)))
}

#' @rdname decodings
#' @export
decode_watershed <- function(minimum_area = NULL) {
  compact(list(name = "watershed", minimum_area = int1(minimum_area)))
}

#' @rdname decodings
#' @export
decode_follow_flows <- function(steps = NULL, step_size = NULL, minimum_area = NULL) {
  compact(list(
    name = "follow_flows",
    steps = int1(steps),
    # Not an integer: this is a distance in pixels and the measurement that matters is
    # below 1. `int1()` here would turn `0.5` into `0`, which is a decoding that never
    # moves rather than an error anybody could see.
    step_size = step_size,
    minimum_area = int1(minimum_area)
  ))
}


# --------------------------------------------------------------------------- drawing
#
# A classes figure and an instances figure are different problems, and the difference is
# what makes these possible without a ninth colour. `class_colours` stops at eight because
# a figure with more than eight **classes** cannot be read by colour however it is painted.
# But nobody reads object 214 by its colour either: what a person needs from an instance
# map is *where one object ends and the next begins*, which is **adjacency, not identity**.
# So a colour may repeat freely as long as it never repeats between neighbours, and eight
# is then a surplus rather than a ceiling.
#
# Measured in the engine over all 670 Data Science Bowl cases, 524 of which hold touching
# objects and 5436 adjacent pairs between them: an exact colouring needs **at most 3**
# colours - 146 cases need one, 412 need two, 112 need three - against a maximum of 6
# neighbours for any object and a mean of 0.37. The cheap alternative, colouring by object
# value modulo eight, paints **550 of 5436 adjacent pairs in one colour, 10.12%**: one
# touching pair in ten drawn as one object, in a figure whose whole subject is whether two
# objects are two.
#
# These are pure R, like every other drawing here, for the reason `R/style.R` states: a
# default that called the engine would make a five-gigabyte torch download the price of
# drawing a mask somebody already has. What stops the two packages colouring the same
# picture differently is therefore not shared code and not a shared constant - the palette
# already agrees and would agree while the rule diverged - but
# `tests/testthat/test-instance-drawing.R`, which draws the same pictures both ways and
# compares them pixel for pixel. `maju116/rplatypus#154` is about that gap and not about
# the code.

#' Which objects touch, as pairs of label values
#'
#' Eight-connected on purpose, and the opposite of the choice a label-maker makes: labelling
#' under 4-connectivity keeps a diagonal join from merging two objects, which errs towards
#' finding more objects - the kind direction for a yardstick. Here the risk runs the other
#' way. Two objects meeting only at a corner are *visually* adjacent, and giving them one
#' colour would draw them as one.
#'
#' The four shifts are the engine's four, in its order, because this has to be the same rule
#' rather than the same intention.
#' @keywords internal
#' @noRd
instance_adjacent_pairs <- function(labels) {
  height <- dim(labels)[1]
  width <- dim(labels)[2]
  pairs <- list()
  shifts <- list(c(0L, 1L), c(1L, 0L), c(1L, 1L), c(1L, -1L))
  for (shift in shifts) {
    rows <- shift[[1]]
    columns <- shift[[2]]
    first_rows <- seq(1L + max(rows, 0L), height - max(-rows, 0L))
    first_columns <- seq(1L + max(columns, 0L), width - max(-columns, 0L))
    second_rows <- seq(1L + max(-rows, 0L), height - max(rows, 0L))
    second_columns <- seq(1L + max(-columns, 0L), width - max(columns, 0L))
    if (!length(first_rows) || !length(first_columns)) next
    first <- labels[first_rows, first_columns, drop = FALSE]
    second <- labels[second_rows, second_columns, drop = FALSE]
    touching <- first > 0L & second > 0L & first != second
    if (!any(touching)) next
    one <- as.integer(first[touching])
    other <- as.integer(second[touching])
    pairs[[length(pairs) + 1L]] <- cbind(pmin(one, other), pmax(one, other))
  }
  if (!length(pairs)) return(matrix(integer(), ncol = 2L))
  found <- do.call(rbind, pairs)
  unique(found)
}

#' One palette slot per object such that no two touching objects share one
#'
#' Welsh-Powell: greedy in order of descending degree, which is not optimal in general and
#' is exact here for the reason the measurement above gives - the graph is planar, so four
#' colours always suffice, and these graphs are sparse enough that three were enough for
#' every one of 670 real pictures.
#'
#' Ties in degree are broken by ascending label value, because Python's `sorted` is stable
#' and the engine sorts values already in ascending order. `order()` on the negated degree
#' is stable the same way, so the two assign the same slot to the same object - which a
#' pixel-for-pixel test would otherwise fail on a picture where two objects tie.
#' @keywords internal
#' @noRd
instance_colour_index <- function(labels, palette_size) {
  values <- sort(unique(as.integer(labels[labels > 0L])))
  if (!length(values)) return(structure(integer(), wrapped = integer()))
  neighbours <- stats::setNames(vector("list", length(values)), as.character(values))
  pairs <- instance_adjacent_pairs(labels)
  for (row in seq_len(nrow(pairs))) {
    one <- as.character(pairs[row, 1])
    other <- as.character(pairs[row, 2])
    neighbours[[one]] <- c(neighbours[[one]], pairs[row, 2])
    neighbours[[other]] <- c(neighbours[[other]], pairs[row, 1])
  }
  degree <- vapply(neighbours, length, integer(1))

  chosen <- stats::setNames(rep(NA_integer_, length(values)), as.character(values))
  wrapped <- integer()
  for (value in values[order(-degree)]) {
    key <- as.character(value)
    taken <- chosen[as.character(neighbours[[key]])]
    taken <- taken[!is.na(taken)]
    slot <- 0L
    while (slot %in% taken) slot <- slot + 1L
    # Past the palette the colouring stops being a guarantee and the slot wraps, so two
    # neighbours get one colour - provably, since a slot is only past the end once every
    # colour before it was taken by a neighbour. Which objects that happened to is carried
    # out rather than dropped, and `overlay_instances()` is what reports it, because it is
    # the function a person called and the only one that knows the palette. The engine warns
    # from the same place as of `0.8.0a24` and in the same words, which a test compares -
    # `maju116/pyplatypus#231`. Both packages were silent here until then, and that silence
    # was a gap rather than a decision: the engine's docstring claimed the report existed.
    # `palette_size = NULL` asks for the colouring with no palette at all, which is how many
    # colours the picture needs and cannot be read off a folded run.
    if (!is.null(palette_size) && slot >= palette_size) {
      wrapped <- c(wrapped, value)
      slot <- slot %% palette_size
    }
    chosen[[key]] <- slot
  }
  structure(chosen, wrapped = sort(wrapped))
}

#' The pixels of a region that have a non-region pixel among their four neighbours
#' @keywords internal
#' @noRd
instance_outline <- function(where) {
  inside <- array(TRUE, dim = dim(where))
  rows <- dim(where)[1]
  columns <- dim(where)[2]
  inside[-rows, ] <- inside[-rows, ] & where[-1L, , drop = FALSE]
  inside[-1L, ] <- inside[-1L, ] & where[-rows, , drop = FALSE]
  inside[, -columns] <- inside[, -columns] & where[, -1L, drop = FALSE]
  inside[, -1L] <- inside[, -1L] & where[, -columns, drop = FALSE]
  where & !inside
}

#' Mix one colour into a picture where a mask says so
#' @keywords internal
#' @noRd
blend_into <- function(picture, rgb, where, alpha) {
  flat <- as.vector(where)
  if (!any(flat)) return(picture)
  for (channel in 1:3) {
    layer <- picture[, , channel]
    layer[flat] <- (1 - alpha) * layer[flat] + alpha * rgb[[channel]]
    picture[, , channel] <- layer
  }
  picture
}

#' Draw an instance map over its image
#'
#' One colour per object, chosen so that **no two touching objects share one**. The rule is
#' adjacency rather than identity: a colour repeats across the picture and never between
#' neighbours, because nobody reads object 214 by its colour and everybody needs to see
#' where one object ends.
#'
#' That is an exact graph colouring, and it is affordable rather than clever. Measured over
#' all 670 Data Science Bowl cases: the hardest needs three colours and `class_colours` has
#' eight, while the cheap alternative - colour by object number, modulo the palette - draws
#' one touching pair in ten as a single object.
#'
#' Eight-connected, so two objects meeting at a corner get different colours. A label-maker
#' goes the other way and joins only along edges, because there the risk is merging two
#' objects into one; here the risk is *drawing* two as one, which is the opposite direction.
#'
#' @param image One image: `height x width x 3`, `height x width x 1` or a matrix. Values
#'   may be 0-1 or 0-255.
#' @param labels An instance label map - one integer per object, 0 for background. Not a
#'   one-hot array: an object identity cannot be carried by a channel.
#' @param alpha How much of the tint shows. Ignored when `outline` is true, where the stroke
#'   is drawn at full strength, because a translucent outline is a smudge.
#' @param outline Draw one stroke per object instead of filling it, which leaves the tissue
#'   entirely visible and is what a pathologist is used to.
#' @param colours The palette to take slots from. Eight by default, mirrored from the
#'   engine's own. A picture needing more colours than this has **warns**, naming how many
#'   it needs and how many objects lost the guarantee: the slot wraps onto a colour a
#'   neighbour already holds - provably, since it is only past the end once every colour
#'   before it was taken by a neighbour - so two touching objects are drawn as one and this
#'   figure answers its own question wrongly. The engine warns in the same words, which is
#'   checked rather than claimed. Unreachable on anything measured: the hardest of 670 Data
#'   Science Bowl cases needs three of the eight.
#' @return A `height x width x 3` array of integers, 0-255.
#' @seealso [overlay_instance_agreement()] for whether the objects are the right ones,
#'   [overlay_mask()] for classes rather than objects.
#' @export
#' @examples
#' image <- array(0.5, dim = c(5, 9, 3))
#' labels <- matrix(0L, nrow = 5, ncol = 9)
#' labels[2:4, 2:4] <- 1L
#' labels[2:4, 5:7] <- 2L   # touching object 1 along a seam
#' shown <- overlay_instances(image, labels)
#' # Two touching objects, two colours.
#' !identical(shown[3, 2, ], shown[3, 6, ])
overlay_instances <- function(image, labels,
                              alpha = drawing_style()$overlay_alpha,
                              outline = FALSE,
                              colours = drawing_style()$class_colours) {
  if (!length(colours)) {
    stop("`colours` is empty; there is nothing to draw the objects in.", call. = FALSE)
  }
  picture <- as_rgb(image)
  labels <- as_instance_map(labels, "labels")
  if (!identical(dim(labels), dim(picture)[1:2])) {
    stop("the labels are ", paste(dim(labels), collapse = "x"), " and the image is ",
         paste(dim(picture)[1:2], collapse = "x"), "; they must match.", call. = FALSE)
  }

  slots <- instance_colour_index(labels, length(colours))
  wrapped <- attr(slots, "wrapped")
  if (length(wrapped)) {
    needed <- max(instance_colour_index(labels, NULL)) + 1L
    warning(
      "this picture needs ", needed, " colours to keep every pair of touching objects ",
      "apart and the palette has ", length(colours), ", so ", length(wrapped), " of ",
      length(slots), " objects are drawn in a colour one of their own neighbours holds. ",
      "A slot past the end of the palette wraps onto one a neighbour has already taken - ",
      "that is what being past the end means - so for those objects the figure no longer ",
      "answers where one ends and the next begins. Pass a longer `colours`.",
      call. = FALSE
    )
  }
  for (key in names(slots)) {
    where <- labels == as.integer(key)
    picture <- blend_into(
      picture,
      grDevices::col2rgb(colours[[slots[[key]] + 1L]])[, 1],
      if (isTRUE(outline)) instance_outline(where) else where,
      if (isTRUE(outline)) 1 else alpha
    )
  }
  array(as.integer(round(picture)), dim = dim(picture))
}

#' Found, missed and invented objects
#'
#' [overlay_agreement()] answers the same three-way question about **pixels**, and on an
#' instance result that is the wrong unit: a merged pair and a split object are both nearly
#' perfect pixelwise and both wrong, which is exactly what an average precision will not
#' tell anybody. This matches whole **objects** at one IoU threshold, the way the metric
#' matches them, so the picture cannot disagree with the number it illustrates.
#'
#' @param image One image, as [overlay_instances()] takes it.
#' @param prediction An instance label map from a model.
#' @param truth An instance label map from the annotation.
#' @param threshold The IoU above which a predicted object counts as a true one, strictly
#'   greater. 0.5 is the loosest of the challenge's ten thresholds, so it is the kindest
#'   reading, and **below 0.5 is refused** for the reason the metric refuses it: there one
#'   prediction can satisfy two true objects and the match stops being one to one.
#' @param alpha How much of the tint shows.
#' @param colours Named `hit`, `missed` and `false_alarm`, as [overlay_agreement()] takes
#'   them.
#' @return A `height x width x 3` array of integers, 0-255.
#' @seealso [overlay_instances()] for the objects themselves.
#' @export
#' @examples
#' image <- array(0.5, dim = c(5, 11, 3))
#' truth <- matrix(0L, nrow = 5, ncol = 11)
#' truth[2:4, 2:4] <- 1L
#' truth[2:4, 6:8] <- 2L
#' predicted <- matrix(0L, nrow = 5, ncol = 11)
#' predicted[2:4, 2:4] <- 1L    # one found
#' predicted[2:4, 9:11] <- 2L   # one invented, and object 2 missed
#' shown <- overlay_instance_agreement(image, predicted, truth)
#' # Three different colours: hit, missed, invented.
#' nrow(unique(rbind(shown[3, 2, ], shown[3, 6, ], shown[3, 10, ])))
overlay_instance_agreement <- function(image, prediction, truth, threshold = 0.5,
                                       alpha = drawing_style()$overlay_alpha,
                                       colours = drawing_style()$agreement_colours) {
  if (threshold < 0.5) {
    stop("`threshold` is ", threshold, ", below 0.5, where one prediction can satisfy two ",
         "true objects and the match is no longer one to one. The instance average ",
         "precision refuses the same thing for the same reason, and a figure drawn under a ",
         "rule the metric rejects is a figure that disagrees with the number it ",
         "illustrates.", call. = FALSE)
  }
  missing <- setdiff(c("hit", "missed", "false_alarm"), names(colours))
  if (length(missing)) {
    stop("`colours` is missing ", paste(sort(missing), collapse = ", "),
         "; all three are needed, because the point of this picture is telling the three ",
         "apart.", call. = FALSE)
  }

  picture <- as_rgb(image)
  predicted <- as_instance_map(prediction, "prediction")
  actual <- as_instance_map(truth, "truth")
  if (!identical(dim(predicted), dim(actual))) {
    stop("the prediction is ", paste(dim(predicted), collapse = "x"), " and the truth is ",
         paste(dim(actual), collapse = "x"),
         "; agreement between two arrays of different shapes is not defined.", call. = FALSE)
  }
  if (!identical(dim(predicted), dim(picture)[1:2])) {
    stop("the maps are ", paste(dim(predicted), collapse = "x"), " and the image is ",
         paste(dim(picture)[1:2], collapse = "x"), "; they must match.", call. = FALSE)
  }

  matched <- matched_objects(actual, predicted, threshold)
  hit <- actual > 0L & matrix(as.vector(actual) %in% matched$truth, nrow = nrow(actual))
  missed <- actual > 0L & !hit
  invented <- predicted > 0L &
    !matrix(as.vector(predicted) %in% matched$prediction, nrow = nrow(predicted))

  for (part in c("hit", "missed", "false_alarm")) {
    where <- switch(part, hit = hit, missed = missed, false_alarm = invented)
    picture <- blend_into(picture, grDevices::col2rgb(colours[[part]])[, 1], where, alpha)
  }
  array(as.integer(round(picture)), dim = dim(picture))
}

#' Which objects on each side are matched at an IoU threshold
#'
#' Every pair above the threshold, with no greedy pass, and that is **equivalent** to the
#' engine's greedy-on-descending-IoU rather than an approximation of it. The proof is the
#' same one that makes the metric refuse a threshold below 0.5: if two disjoint true objects
#' both had IoU above 0.5 with one prediction `p`, each intersection would exceed half of
#' `p` - because the union is at least `p` - and two disjoint intersections cannot together
#' exceed `p`. So above 0.5 the matching is one to one whatever order it is taken in, and
#' the engine's own comment says its one-per-object guard cannot bind there.
#'
#' Written this way rather than as a copy of the greedy because `argsort` is not stable: two
#' pairs at the same IoU come out in an order neither package controls, and a pixel-for-pixel
#' test against the engine would then fail for a reason that is not a divergence.
#' @keywords internal
#' @noRd
matched_objects <- function(actual, predicted, threshold) {
  truth_values <- sort(unique(as.integer(actual[actual > 0L])))
  predicted_values <- sort(unique(as.integer(predicted[predicted > 0L])))
  if (!length(truth_values) || !length(predicted_values)) {
    return(list(truth = integer(), prediction = integer()))
  }

  # One cross-tabulation rather than a loop over pairs: a Data Science Bowl case holds a few
  # hundred objects, and a few hundred squared comparisons over a 256x256 map each is the
  # difference between a figure and a wait.
  counts <- table(factor(as.integer(actual), levels = truth_values),
                  factor(as.integer(predicted), levels = predicted_values))
  intersections <- matrix(as.integer(counts), nrow = length(truth_values))
  truth_sizes <- vapply(truth_values, function(v) sum(actual == v), integer(1))
  predicted_sizes <- vapply(predicted_values, function(v) sum(predicted == v), integer(1))
  unions <- outer(truth_sizes, predicted_sizes, "+") - intersections
  overlaps <- intersections / unions

  above <- which(overlaps > threshold, arr.ind = TRUE)
  list(truth = truth_values[unique(above[, "row"])],
       prediction = predicted_values[unique(above[, "col"])])
}

#' An instance label map, refusing what cannot be one
#' @keywords internal
#' @noRd
as_instance_map <- function(labels, what) {
  labels <- as.array(labels)
  if (length(dim(labels)) != 2L) {
    stop("`", what, "` is ", paste(dim(labels), collapse = "x"),
         "; an instance map is one integer per pixel, and a one-hot array cannot carry an ",
         "object identity.", call. = FALSE)
  }
  array(as.integer(labels), dim = dim(labels))
}

#' How big each object is, in units somebody can use
#'
#' One row per object. `voxels` is the count, which means nothing outside one scanner, and
#' `spacing` turns it into a number a reader can compare - the same argument [mask_volume()]
#' makes for one class, applied per object. That is the question this whole feature is for:
#' *how many nuclei, and how big is each one*.
#'
#' The unit is decided by the rank, and the column is named after it rather than being called
#' `size` with a note somewhere: `area_mm2` for an image, `volume_ml` for a volume. A column
#' whose unit lives in the documentation is a column that ends up in a paper as a bare number.
#'
#' Without `spacing` there is no such column at all, rather than a count pretending to be a
#' measurement.
#'
#' @param labels An instance label map from `predict()` - one integer per object, 0 for
#'   background. Two dimensions for an image, three for a volume.
#' @param spacing The size of one voxel in millimetres: two numbers for an image, three for a
#'   volume. Unset means the result counts voxels and says nothing about size.
#' @return A data frame with `object`, `voxels` and, when `spacing` is given, `area_mm2` or
#'   `volume_ml`. One row per object present, in increasing object number; an object number
#'   absent from the map gets no row, because a model that found objects 1, 2 and 4 found
#'   three objects.
#' @seealso [overlay_instances()] to look at them, [mask_volume()] for one class of a
#'   semantic mask.
#' @export
#' @examples
#' labels <- matrix(0L, nrow = 8, ncol = 8)
#' labels[2:4, 2:4] <- 1L
#' labels[6:7, 6:8] <- 2L
#' instance_sizes(labels)
#'
#' # 0.5 mm pixels: object 1 is 9 pixels, so 9 * 0.25 = 2.25 mm^2.
#' instance_sizes(labels, spacing = c(0.5, 0.5))
instance_sizes <- function(labels, spacing = NULL) {
  labels <- as.array(labels)
  rank <- length(dim(labels))
  if (!rank %in% c(2L, 3L)) {
    stop("`labels` must be one instance map: two dimensions for an image or three for a ",
         "volume; got ",
         if (is.null(dim(labels))) "a vector" else paste(dim(labels), collapse = " x "),
         ". For a stack, apply this to one map at a time - which is also how `predict()` ",
         "returns them.", call. = FALSE)
  }
  bad_spacing <- !is.null(spacing) &&
    (length(spacing) != rank || anyNA(spacing) || any(spacing <= 0))
  if (bad_spacing) {
    stop("`spacing` must be ", rank, " positive numbers, in millimetres, because `labels` ",
         "has ", rank, " dimensions. Giving ", length(spacing), " would measure a different ",
         "shape of thing than the one passed.", call. = FALSE)
  }
  # Not forwarded, for the reason written out at length in `mask_volume()`: this is a count
  # times a product, and making it cross the bridge would buy speed with a 5 GB first call.
  # `test-measure-pair.R` holds it against `pyplatypus.measure.instance_sizes`.
  values <- sort(unique(as.integer(labels[labels > 0L])))
  counts <- vapply(values, function(value) sum(labels == value), integer(1))
  out <- data.frame(object = values, voxels = counts, stringsAsFactors = FALSE)
  if (is.null(spacing)) return(out)

  per_voxel <- prod(as.numeric(spacing))
  if (rank == 2L) {
    out$area_mm2 <- counts * per_voxel
  } else {
    # Millilitres rather than cubic millimetres, as `mask_volume()` reports: a millilitre is
    # a cubic centimetre, which is the unit a radiology report is written in.
    out$volume_ml <- counts * per_voxel / 1000
  }
  out
}

#' A vector field as a picture: hue is the direction, value is the length
#'
#' The convention optical flow has used for twenty years, and a convention rather than a
#' palette decision - which is why it is not in [drawing_style()]. Nothing about it is a
#' choice this project gets to make differently from everyone else's figures, and a reader
#' who has seen one flow visualisation can read this one.
#'
#' What it is for: debugging a `separation_flows()` model. A field that is right everywhere
#' except reversed looks obviously reversed here and identical in any loss. `predict()` with
#' `type = "channels"` is where the field comes from.
#'
#' A zero vector is black, which is also what the background is, and that is honest - the
#' background has no direction.
#'
#' @param flow A two-channel vector field: `2 x height x width`, channel 1 the row component
#'   and channel 2 the column component, which is the layout the engine's targets use.
#' @return A `height x width x 3` array of integers, 0-255.
#' @seealso [separation_flows()] for the model that predicts one.
#' @export
#' @examples
#' field <- array(0, dim = c(2, 2, 3))
#' field[1, 1, 1] <- 1   # pointing down
#' field[2, 1, 2] <- 1   # pointing right
#' shown <- flow_to_colours(field)
#' # Two directions, two hues; and no vector, no colour.
#' !identical(shown[1, 1, ], shown[1, 2, ]) && all(shown[2, 3, ] == 0L)
flow_to_colours <- function(flow) {
  field <- as.array(flow)
  if (length(dim(field)) != 3L || dim(field)[1] != 2L) {
    stop("`flow` is ",
         if (is.null(dim(field))) "a vector" else paste(dim(field), collapse = " x "),
         "; a vector field here is `2 x height x width`, channel 1 the row component and ",
         "channel 2 the column component.", call. = FALSE)
  }
  # `drop = FALSE` and an explicit reshape, because `field[1, , ]` on a `2 x 1 x w` field
  # drops to a vector and the result then has no dimensions at all. A one-row field is what
  # a tiled model hands back at the edge of an image, so it is the ordinary case rather than
  # a contrived one - caught by testing three shapes instead of one.
  shape <- dim(field)[2:3]
  rows <- array(field[1, , , drop = FALSE], dim = shape)
  columns <- array(field[2, , , drop = FALSE], dim = shape)
  length_of <- sqrt(rows^2 + columns^2)
  longest <- max(length_of)
  # `atan2` then wrapped into [0, 1): the same expression the engine uses, because a hue is
  # an angle and the only way to get a different picture from the same field is to measure
  # the angle from somewhere else.
  hue <- (atan2(columns, rows) / (2 * pi)) %% 1
  value <- if (longest > 0) length_of / longest else array(0, dim = dim(length_of))
  rgb <- grDevices::hsv(h = as.vector(hue), s = 1, v = as.vector(value))
  channels <- grDevices::col2rgb(rgb)
  array(as.integer(t(channels)), dim = c(dim(hue), 3L))
}
