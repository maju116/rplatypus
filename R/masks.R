# Turning masks into things you can look at.
#
# This is the half of the package that has nothing to do with training. It exists because
# the useful question is rarely "what is the Dice" - it is "where is the model wrong, and
# does that matter for what I am measuring". A number cannot answer that and a picture can.
#
# Everything here works on ordinary R arrays and needs no Python, so it is equally useful
# on masks that came from somewhere else entirely.

#' Paint a mask with its colormap
#'
#' @param mask Class indices, counted from 1: a `height x width` matrix, or an
#'   `image x height x width` array for several at once.
#' @param colormap A list of RGB triples, one per class; see [binary_colormap].
#' @return The same shape with a trailing RGB axis, values 0-255.
#' @export
#' @examples
#' mask <- matrix(c(1, 1, 2, 2), nrow = 2)
#' dim(classes_to_colours(mask, binary_colormap))
classes_to_colours <- function(mask, colormap) {
  palette <- do.call(rbind, lapply(colormap, as.integer))
  check_classes(mask, nrow(palette))
  coloured <- palette[as.vector(mask), , drop = FALSE]
  array(as.integer(coloured), dim = c(dim(mask), 3L))
}

#' Read a colour mask back to class indices
#'
#' The inverse of [classes_to_colours()]. Anything matching no colour becomes background, and
#' `coverage` in the result says how much of the mask that was - a number near 1 means the
#' colormap does not describe this dataset, which is the quietest way to train on nothing.
#'
#' @param mask An RGB array: `height x width x 3`, or with a leading image axis.
#' @param colormap A list of RGB triples, one per class.
#' @param tolerance Allow this much difference per channel. Useful after lossy resizing,
#'   though masks should be resized with `nearest = TRUE` so it is not needed.
#' @return A list with `classes` (indices counted from 1) and `coverage` (the fraction of
#'   pixels that matched a colour).
#' @export
#' @examples
#' coloured <- classes_to_colours(matrix(c(1, 2, 2, 1), nrow = 2), binary_colormap)
#' colours_to_classes(coloured, binary_colormap)$classes
colours_to_classes <- function(mask, colormap, tolerance = 0) {
  dims <- dim(mask)
  if (utils::tail(dims, 1) < 3L) {
    stop("expected an RGB mask with three channels last, got ",
         paste(dims, collapse = "x"), call. = FALSE)
  }
  spatial <- dims[-length(dims)]
  flat <- matrix(as.numeric(mask), ncol = dims[length(dims)])[, 1:3, drop = FALSE]

  classes <- integer(nrow(flat))
  matched <- logical(nrow(flat))
  # Later colours win, so an explicit class beats the background it overlaps.
  for (index in seq_along(colormap)) {
    target <- as.numeric(colormap[[index]])
    # Three parallel comparisons, aligned so that being the same shape is visible.
    hit <- abs(flat[, 1] - target[1]) <= tolerance &
           abs(flat[, 2] - target[2]) <= tolerance &  # nolint: indentation_linter.
           abs(flat[, 3] - target[3]) <= tolerance
    classes[hit] <- index
    matched <- matched | hit
  }
  classes[classes == 0L] <- 1L

  list(classes = array(classes, dim = spatial), coverage = mean(matched))
}

#' Read mask files as class indices
#'
#' Masks come two ways, and this reads both. `colormap` is for masks stored as pictures, one
#' colour per class. `labels` is for masks stored as label maps - a vector of the voxel values,
#' in class order - which is how volume formats store them.
#'
#' @inheritParams read_images
#' @param colormap A list of RGB triples, one per class. Give this or `labels`.
#' @param labels The voxel value of each class, in class order: `c(0, 1)` for a binary
#'   segmentation. For NIfTI and other label maps. Give this or `colormap`.
#' @param tolerance Passed to [colours_to_classes()]. Ignored for label maps, which are compared to
#'   within half a unit - a label map that has been resampled or merely passed through a float
#'   will not satisfy an exact comparison, and a label that fails to match becomes background.
#' @return An array of class indices, counted from 1.
#' @export
#' @examples
#' \dontrun{
#' # Masks stored as pictures: the colormap says which colour is which class.
#' truth <- read_masks(list.files("masks/", full.names = TRUE),
#'                     colormap = list(c(0, 0, 0), c(255, 255, 255)))
#'
#' # Masks stored as label maps, which is how volumes do it. Exactly one of the two.
#' truth <- read_masks("case_01/seg.nii.gz", labels = c(0, 1))
#'
#' # `tolerance` is for masks that have been through a lossy resize, where a colour
#' # that should be (255, 0, 0) arrives as (254, 1, 0) and matches nothing.
#' truth <- read_masks(paths, colormap = voc_colormap, tolerance = 2)
#' }
read_masks <- function(paths, colormap = NULL, labels = NULL, size = NULL, tolerance = 0) {
  if (is.null(colormap) == is.null(labels)) {
    stop("give exactly one of `colormap` (masks stored as pictures) and `labels` ",
         "(masks stored as label maps, which is how volumes do it).", call. = FALSE)
  }

  # Nearest, always. Interpolating a mask invents values belonging to no class, which then
  # quietly become background - and the plot would show a disagreement that is nothing but the
  # resizing.
  if (!is.null(labels)) {
    values <- read_images(paths, size = size, channels = 1, nearest = TRUE)
    return(label_classes(values, labels))
  }
  coloured <- read_images(paths, size = size, channels = 3, nearest = TRUE)
  colours_to_classes(coloured, colormap, tolerance = tolerance)$classes
}

#' Label values to class indices
#'
#' @param values An array whose last axis is a single channel, as [read_images()] returns for
#'   `channels = 1`.
#' @param labels The voxel value of each class, in class order.
#' @return An array of class indices counted from 1, with the channel axis dropped.
#' @keywords internal
#' @noRd
label_classes <- function(values, labels) {
  dims <- dim(values)
  spatial <- dims[-length(dims)]
  flat <- as.numeric(values)

  classes <- integer(length(flat))
  for (index in seq_along(labels)) {
    # Half a unit, because the values arrive as floats: exact comparison would miss a label
    # map that has been resampled, and a label that misses becomes background.
    classes[abs(flat - as.numeric(labels[[index]])) <= 0.5] <- index
  }
  classes[classes == 0L] <- 1L
  array(classes, dim = spatial)
}

#' Lay a mask over the image it belongs to
#'
#' The picture that answers "where is it looking". Background - class 1 - is left alone,
#' so only the classes that were found are tinted.
#'
#' @param image A `height x width x channels` array. Values in 0-1 or 0-255; greyscale is
#'   repeated across three channels.
#' @param mask Class indices, counted from 1, matching the image's height and width.
#' @param colormap A list of RGB triples, one per class.
#' @param alpha How strongly to tint, 0 to 1.
#' @return A `height x width x 3` array of 0-255 integers.
#' @export
#' @examples
#' image <- array(runif(8 * 8 * 3, 0.2, 0.6), dim = c(8, 8, 3))
#' mask <- matrix(1L, 8, 8); mask[2:4, 2:4] <- 2L
#' tinted <- overlay_mask(image, mask, colormap = list(c(0, 0, 0), c(255, 0, 0)))
#' dim(tinted)
overlay_mask <- function(image, mask, colormap, alpha = drawing_style()$overlay_alpha) {
  image <- as_rgb(image)
  if (!identical(dim(image)[1:2], dim(mask)[1:2])) {
    stop("image is ", paste(dim(image)[1:2], collapse = "x"), " but mask is ",
         paste(dim(mask)[1:2], collapse = "x"), "; they must match.", call. = FALSE)
  }
  tint <- classes_to_colours(mask, colormap)
  foreground <- as.vector(mask) > 1L
  blended <- image
  for (channel in 1:3) {
    layer <- blended[, , channel]
    layer[foreground] <- (1 - alpha) * layer[foreground] +
      alpha * tint[, , channel][foreground]
    blended[, , channel] <- layer
  }
  array(as.integer(round(blended)), dim = dim(blended))
}

#' Where a prediction and the truth disagree
#'
#' Three colours rather than one: what was found, what was missed, and what was invented.
#' A Dice of 0.85 says nothing about which of the three is costing you, and for most
#' clinical questions they are not interchangeable - a missed lesion and a false alarm
#' are different kinds of wrong.
#'
#' @param image A `height x width x channels` array.
#' @param prediction,truth Class indices, counted from 1.
#' @param alpha How strongly to tint.
#' @param colours Named colours for `hit`, `missed` and `false_alarm`.
#' @return A `height x width x 3` array of 0-255 integers.
#' @export
#' @examples
#' image <- array(runif(8 * 8 * 3, 0.2, 0.6), dim = c(8, 8, 3))
#' truth <- matrix(1L, 8, 8); truth[2:4, 2:4] <- 2L
#' predicted <- matrix(1L, 8, 8); predicted[3:5, 2:4] <- 2L
#' shown <- overlay_agreement(image, prediction = predicted, truth = truth)
#' dim(shown)
#'
#' # Three colours, not one: a missed lesion and a false alarm cost different things,
#' # and a single overlap score hides which one you have.
overlay_agreement <- function(image, prediction, truth,
                              alpha = drawing_style()$overlay_alpha,
                              colours = drawing_style()$agreement_colours) {
  image <- as_rgb(image)
  predicted <- as.vector(prediction) > 1L
  actual <- as.vector(truth) > 1L
  parts <- list(hit = predicted & actual,
                missed = !predicted & actual,
                false_alarm = predicted & !actual)

  blended <- image
  for (part in names(parts)) {
    where <- parts[[part]]
    if (!any(where)) next
    rgb <- grDevices::col2rgb(colours[[part]])[, 1]
    for (channel in 1:3) {
      layer <- blended[, , channel]
      layer[where] <- (1 - alpha) * layer[where] + alpha * rgb[[channel]]
      blended[, , channel] <- layer
    }
  }
  array(as.integer(round(blended)), dim = dim(blended))
}

#' Combine several binary masks into one
#'
#' The Data Science Bowl stores one file per nucleus; datasets like it are common. Later
#' masks win where they overlap, so an explicit class beats the background it sits on.
#'
#' @param masks A list of `height x width` matrices of class indices.
#' @return One `height x width` matrix.
#' @export
#' @examples
#' # Data Science Bowl stores one file per nucleus, so a sample's mask arrives as several
#' # matrices that have to become one. Later masks win where they overlap.
#' one <- matrix(1L, 8, 8); one[2:4, 2:4] <- 2L
#' two <- matrix(1L, 8, 8); two[6:7, 5:7] <- 2L
#' united <- unite_masks(list(one, two))
#' table(united)
unite_masks <- function(masks) {
  if (!length(masks)) stop("`masks` is empty.", call. = FALSE)
  shapes <- unique(lapply(masks, dim))
  if (length(shapes) > 1L) {
    stop("all masks must be the same size; found ",
         paste(vapply(shapes, paste, character(1), collapse = "x"), collapse = " and "),
         call. = FALSE)
  }
  Reduce(function(a, b) pmax(a, b), masks)
}

#' How much of each class a mask covers
#'
#' A quick sanity check before training: a foreground of half a percent is a problem the
#' loss has to be chosen for, and it is better to know before the run than after.
#'
#' @param mask Class indices, counted from 1.
#' @param labels Optional names for the classes.
#' @return A data frame with one row per class.
#' @export
#' @examples
#' mask <- matrix(1L, 8, 8); mask[2:4, 2:4] <- 2L
#' mask_coverage(mask, labels = c("background", "nucleus"))
#'
#' # A class with 0 pixels is the thing to look for: its target channel is zero
#' # everywhere, so there is no gradient towards it and the model is never shown
#' # what it is being asked to find.
mask_coverage <- function(mask, labels = NULL) {
  counts <- tabulate(as.vector(mask))
  classes <- seq_along(counts)
  data.frame(
    class = classes,
    label = if (is.null(labels)) paste("class", classes) else labels[classes],
    pixels = counts,
    fraction = counts / length(mask),
    stringsAsFactors = FALSE
  )
}

#' Any array to a 0-255 RGB array
#' @keywords internal
#' @noRd
as_rgb <- function(image) {
  if (length(dim(image)) == 2L) image <- array(image, dim = c(dim(image), 1L))
  if (max(image, na.rm = TRUE) <= 1 + 1e-8) image <- image * 255
  channels <- dim(image)[3]
  if (channels == 1L) {
    image <- array(rep(image, 3L), dim = c(dim(image)[1:2], 3L))
  } else if (channels > 3L) {
    image <- image[, , 1:3, drop = FALSE]
  }
  image
}

#' @keywords internal
#' @noRd
check_classes <- function(mask, n_class) {
  values <- unique(as.vector(mask))
  bad <- values[values < 1L | values > n_class]
  if (length(bad)) {
    stop("mask contains class ", bad[[1]], " but the colormap defines ", n_class,
         " classes. Classes are counted from 1.", call. = FALSE)
  }
  invisible(TRUE)
}

#' How many classes the most ambitious pixel is in
#'
#' Read off the array rather than from the specification, because that is what a caller
#' holding only a prediction can answer - and it is the same test the engine's
#' `onehot_to_colours` applies, so the two halves refuse the same arrays. A softmax output
#' never trips it: its channels sum to one, so at most one can reach half.
#'
#' `rowSums(..., dims = )` rather than `apply()`: a split of 200 retinas at 2048 px is
#' 3.4e9 elements and `apply` would build a list over all of them.
#' @keywords internal
#' @noRd
overlapping_channels <- function(masks, threshold = 0.5) {
  spatial <- length(dim(masks)) - 1L
  as.integer(max(rowSums(masks >= threshold, dims = spatial)))
}

#' Write masks to files
#'
#' Predictions are only half useful while they are an array in a session. This writes them
#' as ordinary PNGs that open in anything - ImageJ, QuPath, a viewer, a colleague's
#' machine - and returns the paths, so it can sit at the end of a pipeline.
#'
#' Files go where you say, not beside the images they came from. Writing into somebody's
#' dataset directory is a surprising thing for a function to do, and a second run against
#' a different model would quietly mix its results in with the first.
#'
#' @param masks Class indices from [predict.platypus_fit()] - an `image x height x width`
#'   array, or one `height x width` matrix. Probabilities are accepted too and reduced to
#'   the most likely class.
#'
#'   For **volumes** use [save_volumes()], which writes NIfTI carrying the geometry of the
#'   scan each mask came from. This function cannot reliably tell a stack of volumes from a
#'   stack of images with a class axis - the ranks are identical - so it does not try; it
#'   refuses only the case a shape can prove.
#'
#'   For **overlapping classes** use [save_class_masks()]. A prediction where some pixel is
#'   in two classes at once is refused here rather than reduced: one pixel gets one colour,
#'   so writing it as a colour map would mean choosing one of the classes it is in and
#'   leaving nothing in the file to say that happened.
#' @param dir Directory to write into; created if it does not exist.
#' @param colormap A list of RGB triples, one per class.
#' @param names File names, or the source image paths to take names from. Defaults to
#'   `mask_0001.png` and so on.
#' @param suffix Added before the extension, so predictions from different models can sit
#'   in one directory without overwriting each other.
#' @return The paths written, invisibly.
#' @export
#' @examples
#' \dontrun{
#' masks <- predict(fit, "unet", split = "test")
#' save_masks(masks, "predictions", binary_colormap, suffix = "_unet")
#' }
save_masks <- function(masks, dir, colormap, names = NULL, suffix = "") {
  if (length(dim(masks)) == 5L) {
    # The one case a shape can prove. A stack of volumes, (n, d, h, w), has the same rank as
    # a stack of images with a class axis, so this function cannot detect that one - which
    # is why the documentation points at save_volumes() rather than this check pretending to.
    stop("these are volumes (", paste(dim(masks), collapse = " x "), "). Use ",
         "`save_volumes()`, which writes NIfTI carrying the geometry of the scan each mask ",
         "came from - a volume mask without that cannot be laid over its scan by anything.",
         call. = FALSE)
  }
  if (length(dim(masks)) == 4L) {
    # Before the `which.max` below, not after: taking the strongest channel of an
    # overlapping prediction writes a plausible picture of something else, and once it is
    # written there is nothing in the file that says so.
    overlapping <- overlapping_channels(masks)
    if (overlapping > 1L) {
      stop("a pixel is in ", overlapping, " classes at once, and one pixel gets one ",
           "colour - taking the strongest would write a plausible picture of something ",
           "else. These are overlapping classes (`regions`), so write them one file per ",
           "class with `save_class_masks()`.", call. = FALSE)
    }
    # Probabilities rather than classes: take the most likely, as predict() would.
    masks <- apply(masks, seq_len(length(dim(masks)) - 1L), which.max)
  }
  if (length(dim(masks)) == 2L) masks <- array(masks, dim = c(1L, dim(masks)))

  count <- dim(masks)[1]
  names <- if (is.null(names)) {
    sprintf("mask_%04d", seq_len(count))
  } else {
    tools::file_path_sans_ext(basename(as.character(names)))
  }
  if (length(names) != count) {
    stop("`names` has ", length(names), " entries but there are ", count, " masks.",
         call. = FALSE)
  }

  coloured <- lapply(seq_len(count), function(i) classes_to_colours(masks[i, , ], colormap))
  paths <- file.path(dir, paste0(names, suffix, ".png"))

  result <- shim()$write_masks(coloured, as.list(paths))
  if (!isTRUE(result$ok)) abort_engine(result)
  invisible(unlist(result$paths))
}

#' Write overlapping classes, one file per class
#'
#' `regions` gives a channel per named class and a sigmoid per channel, so a pixel may be in
#' several classes at once - that is the point of it. A colour map cannot hold that: one
#' pixel gets one colour. [save_masks()] therefore refuses such a prediction, and this is
#' what it refuses it in favour of - one binary picture per class, named after the class.
#'
#' Each file is `<name><suffix>_<class>.png`, black and white, so it opens in anything and
#' thresholds back to exactly what was written. A class name becomes a filename by replacing
#' anything outside letters, digits, dot, dash and underscore with `_`, so `whole tumour` is
#' `whole_tumour` on disk; two class names that become the same filename are refused rather
#' than written, because one file would hold the second class with the first silently gone.
#'
#' A class nothing reaches is written as an empty picture rather than skipped. A missing file
#' reads as *this run did not produce that class* and an empty one as *it did and the answer
#' was nothing*, which are different findings and only one of them is true.
#'
#' @param masks Channel probabilities from `predict(fit, type = "probability")` - an
#'   `image x height x width x class` array, or one `height x width x class` array.
#'
#'   Class indices are the wrong input and are refused where a shape or a value can prove
#'   it: any value above 1 is not a probability. What cannot be proved is a stack of
#'   class-index masks whose values are all 1 - `image x height x width` has the same rank
#'   as one image's `height x width x class`, exactly as `save_masks()` cannot tell a stack
#'   of volumes from a stack of images - so that one is read as one image with eight
#'   channels and caught by `classes` not having eight names.
#' @param dir Directory to write into; created if it does not exist.
#' @param classes One name per channel, in channel order, which is the order the regions were
#'   written in and the order every per-class score is reported in. `inspect_masks()` names
#'   them the same way. Called `classes` and not `names` because `names` in this family is
#'   the files - see below.
#' @param names File name stems, one per image, or the source image paths to take them from.
#'   Defaults to `mask_0001` and so on. The engine's own function calls this `cases`; in R it
#'   is `names`, matching [save_masks()] and [save_volumes()], and `classes` carries what the
#'   engine calls `names`.
#' @param suffix Added before the class, so predictions from different models can sit in one
#'   directory without overwriting each other.
#' @param threshold A class is written where its channel reaches this. 0.5 is what every
#'   metric in the engine thresholds a channel at, so a different number here writes pictures
#'   that disagree with the scores printed beside them.
#' @return The paths written, invisibly, image by image and within an image class by class.
#' @seealso [save_masks()] for exclusive classes as one colour picture, [save_volumes()] for
#'   volumes as NIfTI.
#' @export
#' @examples
#' \dontrun{
#' spec <- platypus_spec(... )
#' channels <- predict(fit, "brats", split = "test", type = "probability")
#' save_class_masks(channels, "predictions", classes = c("whole tumour", "core", "enhancing"))
#' }
save_class_masks <- function(masks, dir, classes, names = NULL, suffix = "",
                             threshold = 0.5) {
  if (length(dim(masks)) == 3L) masks <- array(masks, dim = c(1L, dim(masks)))
  if (length(dim(masks)) != 4L) {
    stop("expected channel probabilities - `image x height x width x class`, or one ",
         "`height x width x class` - got ",
         paste(dim(masks) %||% length(masks), collapse = " x "),
         ". `predict(type = \"probability\")` returns that shape.", call. = FALSE)
  }
  # Provable rather than guessed: no probability exceeds 1, so a value above it is class
  # indices. The converse is not provable - a stack of class-index masks that are all
  # background has the same rank and the same values as a one-hot single image - and that
  # one is left to the `classes` count, which is the honest division of the two cases.
  if (max(masks, na.rm = TRUE) > 1 + 1e-8) {
    stop("these are class indices rather than channel probabilities - the largest value is ",
         format(max(masks, na.rm = TRUE)), " and no probability exceeds 1. Overlapping ",
         "classes have no class index: ask `predict()` for ",
         "`type = \"probability\"`.", call. = FALSE)
  }

  count <- dim(masks)[1]
  names <- if (is.null(names)) {
    sprintf("mask_%04d", seq_len(count))
  } else {
    tools::file_path_sans_ext(basename(as.character(names)))
  }
  if (length(names) != count) {
    stop("`names` has ", length(names), " entries but there are ", count, " predictions.",
         call. = FALSE)
  }

  # The naming, the thresholding and the refusals are the engine's, deliberately: two
  # implementations of one set of rules is two things to keep in step, and the filenames
  # are part of what a user's next script reads.
  result <- shim()$class_masks(
    masks, path.expand(dir),
    classes = as.list(as.character(classes)),
    cases = as.list(names),
    threshold = as.numeric(threshold),
    suffix = as.character(suffix)
  )
  if (!isTRUE(result$ok)) abort_engine(result)
  invisible(unlist(result$paths))
}
