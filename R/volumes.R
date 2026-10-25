# Volumes: the parts that are not just "the same thing with one more axis".
#
# Two of them. A volume mask has to be written with the geometry of the scan it came from,
# or it cannot be laid over that scan by anything. And a segmented structure is reported in
# millilitres, not in voxels - the voxel count is meaningless outside the scanner that
# produced it, and converting needs the spacing, which is why the spacing is carried.

#' What is in a volume file
#'
#' Shape and voxel spacing, read through the engine so the numbers are the ones training
#' would use - including the canonical reorientation, which changes what "the first axis"
#' means.
#'
#' @param paths One or more paths to NIfTI files.
#' @return A data frame with one row per file: `path`, `spacing_1/2/3` in millimetres,
#'   `shape_1/2/3` in voxels, and `voxel_ml`, the volume of one voxel in millilitres.
#' @seealso [mask_volume()], which turns a segmentation into millilitres.
#' @examples
#' \dontrun{
#' volume_info("scans/case_01/images/ct.nii.gz")
#' }
#' @export
volume_info <- function(paths) {
  result <- shim()$volume_info(as.list(as.character(paths)))
  if (!isTRUE(result$ok)) abort_engine(result)

  rows <- lapply(result$volumes, function(row) {
    spacing <- unlist(row$spacing)
    shape <- unlist(row$shape)
    data.frame(
      path = row$path,
      spacing_1 = spacing[[1]], spacing_2 = spacing[[2]], spacing_3 = spacing[[3]],
      shape_1 = shape[[1]], shape_2 = shape[[2]], shape_3 = shape[[3]],
      voxel_ml = row$voxel_ml,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

#' How much of a volume a class occupies, in millilitres
#'
#' A voxel count answers nothing on its own: the same tumour is 4000 voxels on one scanner
#' and 12000 on another, and neither number goes in a report. Multiplied by the volume of a
#' voxel it becomes millilitres, which is comparable between scans, between patients and
#' against whatever the radiologist measured by hand.
#'
#' @param mask A mask of class indices, as [predict()] returns - one volume, not a stack.
#' @param spacing Voxel size in millimetres, length 3. [volume_info()] reports it; so does
#'   the `spacing_1/2/3` columns of its output.
#' @param class Which class to measure, numbered from 1 as the colormap and `labels` are.
#'   Defaults to 2, which is the foreground in a binary segmentation.
#' @return The volume in millilitres.
#' @examples
#' mask <- array(1L, dim = c(10, 10, 4))
#' mask[3:6, 3:6, 2:3] <- 2L
#' # 32 voxels of 2 x 2 x 5 mm: 32 * 20 mm^3 = 640 mm^3 = 0.64 ml
#' mask_volume(mask, spacing = c(2, 2, 5))
#' @export
mask_volume <- function(mask, spacing, class = 2L) {
  if (length(spacing) != 3L || anyNA(spacing) || any(spacing <= 0)) {
    stop("`spacing` must be three positive numbers, in millimetres.", call. = FALSE)
  }
  if (length(dim(mask)) != 3L) {
    stop("`mask` must be one volume with three dimensions; got ",
         if (is.null(dim(mask))) "a vector" else paste(dim(mask), collapse = " x "),
         ". For a stack, apply this to one volume at a time.", call. = FALSE)
  }
  # **Deliberately NOT forwarded to the engine**, although `pyplatypus.measure.mask_volume`
  # exists since `0.8.0a39` and this looks like the duplication §3F is a list of.
  #
  # Forwarding was written, measured and reverted. It is faster - 0.035 s against 0.341 s on
  # a 512 x 512 x 300 label map, because `sum(mask == class)` builds a logical vector of 78
  # million elements first - and it costs something no speed makes up for: the engine's first
  # call downloads about 5 GB, so a user holding a mask and a spacing would pay a torch
  # install for a count times a product. It would also make this function's example need
  # Python, and `R CMD check` runs examples, so the page would have to go into `\dontrun{}`
  # the way `volume_info()`'s does - on arithmetic a reader can verify by eye.
  #
  # So the rule drawn, and it is the one `ellipse_measure()` is on the other side of: a
  # measurement that is **arithmetic** stays here, a measurement that needs a **library**
  # crosses. `test-measure-pair.R` holds this against the engine's answer so the two cannot
  # drift, which is what makes it a pair rather than a copy.
  voxels <- sum(mask == as.integer(class))
  voxels * prod(as.numeric(spacing)) / 1000
}

#' Refuse a volume prediction a label map cannot hold
#'
#' The same check `save_masks()` makes, at the two places a volume prediction is reduced -
#' and this is the one that matters most, because `regions` was motivated by BraTS and BraTS
#' is volumes. A label-map NIfTI holds one integer per voxel, so an overlapping prediction
#' written this way names one of the classes a voxel is in and loses the rest, with nothing
#' in the file to say so.
#' @keywords internal
#' @noRd
refuse_overlapping_volume <- function(masks) {
  overlapping <- overlapping_channels(masks)
  if (overlapping > 1L) {
    stop("a voxel is in ", overlapping, " classes at once, and a label map holds one ",
         "integer per voxel - taking the strongest would write a plausible volume of ",
         "something else. These are overlapping classes (`regions`), so write them one ",
         "file per class with `save_class_volumes()`.", call. = FALSE)
  }
  invisible(TRUE)
}


#' One volume per element, whatever form the masks arrived in
#'
#' A list from `predict(space = "source")` passes through untouched, which is the point of that
#' argument existing: its members are already on their scans' grids and need not agree with each
#' other. An array is unstacked instead, and probabilities are collapsed.
#'
#' **The result is unnamed, and that is not tidiness.** `predict(space = "source")` returns a
#' list named by case since `maju116/rplatypus#223`, and reticulate converts a NAMED R list
#' into a Python `dict` where an unnamed one becomes a `list`. So carrying the names across
#' the bridge changes the type the writer receives, and it refuses with a message about a
#' shape it never got to read. Names are useful on this side of the bridge and are a
#' different object on the other.
#' @keywords internal
#' @noRd
as_volume_list <- function(masks) {
  if (is.list(masks)) {
    # Unnamed on the way out: see the note above. Names are useful in R and become a
    # `dict` in Python.
    volumes <- unname(lapply(masks, function(one) {
      dims <- length(dim(one))
      if (dims == 4L) {
        # (d, h, w, class): probabilities for one volume.
        refuse_overlapping_volume(one)
        apply(one, seq_len(3L), which.max)
      } else if (dims == 3L) {
        one
      } else {
        stop("a mask in the list has ", dims, " dimensions; expected 3 (class indices) or ",
             "4 (probabilities for one volume).", call. = FALSE)
      }
    }))
    return(volumes)
  }

  dimensions <- length(dim(masks))
  if (dimensions == 5L) {
    # Probabilities: (n, d, h, w, class). Collapse as predict(type = "class") would.
    refuse_overlapping_volume(masks)
    masks <- apply(masks, seq_len(4L), which.max)
  } else if (dimensions == 3L) {
    masks <- array(masks, dim = c(1L, dim(masks)))
  } else if (dimensions != 4L) {
    stop("`masks` has ", dimensions, " dimensions; expected 3 (one volume), 4 (a stack) ",
         "or 5 (a stack of probabilities).", call. = FALSE)
  }
  # Four dimensions is a stack of class-index volumes and nothing else. One volume's
  # probabilities have exactly the same rank, and guessing between them by looking at the
  # sizes is how a silent misinterpretation gets into a package: it worked here for a stack
  # of two and would have written one wrong file for a stack of four.
  lapply(seq_len(dim(masks)[1]), function(i) masks[i, , , , drop = TRUE])
}

#' Save predicted volumes as NIfTI
#'
#' Writes each mask as a label-map NIfTI carrying the geometry of the scan it was predicted
#' from. That is the whole reason this is not `save_masks()` with a different extension: a
#' mask array without an affine cannot be laid over its scan by any viewer, any registration
#' tool or any volume calculation - it either lands in the wrong place or is refused.
#'
#' Carrying the affine means the mask has to be on the same grid as the scan, which is what
#' `predict(space = "source")` is for: it maps each prediction back out of the model's grid onto
#' the scan's. Without it, a resampled or resized prediction will be refused here rather than
#' written somewhere wrong.
#'
#' @param masks Masks of class indices, as [predict()] returns.
#'
#'   A **list** of volumes is what `predict(space = "source")` gives, and the form to prefer:
#'   each mask is already on the grid of the scan it was computed from, so the geometry matches
#'   by construction and the scans need not be the same size as each other.
#'
#'   An array is also accepted: one volume as `depth x height x width`, a stack as
#'   `volume x depth x height x width`, probabilities as `volume x depth x height x width x class`
#'   which are collapsed to the most likely class. A single volume's probabilities have the same
#'   rank as a stack of masks and are not guessed at - collapse them yourself, or keep the volume
#'   axis.
#' @param dir Where to write. Created if it does not exist.
#' @param reference The scan each mask was predicted from, in the same order. Its affine is
#'   what the mask is written with, so this is required rather than optional.
#' @param names File names, without extension. Taken from `reference` when unset, which works
#'   when the scans have distinct filenames. They often do not - one directory per case, the same
#'   `ct.nii.gz` inside each - and writing every mask to one name would silently keep only the
#'   last, so that case is an error asking for this argument. `split_path(split, "validation")$key`
#'   is usually the answer.
#' @param suffix Appended to each name, for telling two models' output apart.
#' @return The paths written, invisibly.
#' @seealso [save_masks()] for 2D masks as pictures.
#' @examples
#' \dontrun{
#' validation <- split_path(split, "validation")
#' masks <- predict(fit, split = "validation", space = "source")
#' save_volumes(masks, "predictions", reference = validation$images)
#' }
#' @export
save_volumes <- function(masks, dir, reference, names = NULL, suffix = "") {
  volumes <- as_volume_list(masks)

  count <- length(volumes)
  reference <- as.character(reference)
  if (length(reference) != count) {
    stop("`reference` has ", length(reference), " entries but there are ", count,
         " masks. Each mask is written with the geometry of the scan it came from, so ",
         "they have to line up.", call. = FALSE)
  }

  names <- if (is.null(names)) {
    sub("[.]nii([.]gz)?$", "", basename(reference), ignore.case = TRUE)
  } else {
    as.character(names)
  }
  if (length(names) != count) {
    stop("`names` has ", length(names), " entries but there are ", count, " masks.",
         call. = FALSE)
  }
  if (anyDuplicated(names)) {
    # Datasets that keep one directory per case usually name the file inside it the same way -
    # `case_01/images/ct.nii.gz` - so basenames collide and every mask would be written to one
    # path, each overwriting the last. Silently losing five of six masks is the worst outcome
    # available here, and the fix is one argument.
    repeated <- unique(names[duplicated(names)])
    stop("the masks would be written to the same name: ",
         paste(utils::head(repeated, 3), collapse = ", "),
         if (length(repeated) > 3) ", ..." else "",
         ". Names come from the reference files, and one directory per case usually means ",
         "the same filename in each. Pass `names` - `split_path(split, \"validation\")$key` ",
         "is what you want.", call. = FALSE)
  }

  paths <- file.path(dir, paste0(names, suffix, ".nii.gz"))

  result <- shim()$write_volumes(volumes, as.list(paths), as.list(reference))
  if (!isTRUE(result$ok)) abort_engine(result)
  invisible(unlist(result$paths))
}

#' Check folders of DICOM slices before training on them
#'
#' One row per directory, saying whether it is a usable series and what is wrong with it if it
#' is not. Problems are reported as a column rather than raised, because a hundred cases out
#' of an archive will contain a few with a missing slice, two series in one folder, or
#' duplicated files - and stopping at the first turns an afternoon's work into a week's.
#'
#' Reads no pixels. Every check runs on the DICOM headers, so this is usable on a hundred
#' gigabytes of data and is the first thing worth running on a new dataset.
#'
#' @section What it catches:
#'
#' A **missing slice**, which does not make a volume shorter - it puts everything past the gap
#' in the wrong place, and no metric would show it. **Two series in one folder**, which is the
#' normal state of an archive export: a scout, a reconstruction and a phase sitting together,
#' which stacked would interleave two anatomies. **Duplicated slices**, from a copy or from
#' several echoes mixed together. Slices of different **size**, **angle** or **spacing**.
#'
#' It also reports how the slices were ordered. `"position"` means the geometry decided, which
#' is what you want. `"instance_number"` means the files carry no positions and the order came
#' from a number that is only required to be unique - worth knowing before trusting the result.
#'
#' @param paths Directories, each holding the slices of one series.
#' @return A data frame with one row per directory: `path`, `ok`, `slices`, `sorted_by`,
#'   `spacing_1/2/3`, `series_uid` and `problem`.
#' @seealso [volume_info()] for NIfTI files, [split_dataset()] for dividing the cases up.
#' @examples
#' \dontrun{
#' cases <- list.dirs("dicom_export", recursive = FALSE)
#' report <- series_report(cases)
#'
#' report[!report$ok, c("path", "problem")]     # the ones to deal with first
#' table(report$sorted_by)
#' }
#' @export
series_report <- function(paths) {
  result <- shim()$series_report(as.list(as.character(paths)))
  if (!isTRUE(result$ok)) abort_engine(result)

  rows <- lapply(result$series, function(row) {
    spacing <- if (is.null(row$spacing)) rep(NA_real_, 3) else unlist(row$spacing)
    data.frame(
      path = row$path,
      ok = isTRUE(row$ok),
      slices = as.integer(row$slices),
      sorted_by = row$sorted_by %||% NA_character_,
      spacing_1 = spacing[[1]], spacing_2 = spacing[[2]], spacing_3 = spacing[[3]],
      series_uid = row$series_uid %||% NA_character_,
      problem = row$problem %||% NA_character_,
      stringsAsFactors = FALSE
    )
  })
  frame <- do.call(rbind, rows)
  structure(frame, class = c("platypus_series_report", class(frame)))
}

#' @export
print.platypus_series_report <- function(x, ...) {
  usable <- sum(x$ok)
  cat("platypus series report: ", usable, " of ", nrow(x), " usable\n", sep = "")
  if (usable > 0) {
    ordered <- table(x$sorted_by[x$ok])
    cat("  ordered by: ",
        paste(names(ordered), ordered, sep = " x ", collapse = ", "), "\n", sep = "")
  }
  broken <- x[!x$ok, , drop = FALSE]
  if (nrow(broken)) {
    cat("  not usable:\n")
    for (i in seq_len(min(5L, nrow(broken)))) {
      first_line <- strsplit(broken$problem[[i]], "[.] ")[[1]][[1]]
      cat("   - ", basename(broken$path[[i]]), ": ", first_line, "\n", sep = "")
    }
    if (nrow(broken) > 5L) {
      cat("   ... and ", nrow(broken) - 5L, " more; see the `problem` column.\n", sep = "")
    }
  }
  invisible(x)
}


#' Save overlapping classes as one NIfTI per class
#'
#' The volume counterpart of [save_class_masks()], and the one `regions` was motivated by:
#' BraTS names three overlapping regions and stores them as volumes. A label-map NIfTI holds
#' one integer per voxel, so [save_volumes()] refuses an overlapping prediction rather than
#' reducing it, and this is what it refuses it in favour of - one binary volume per class,
#' each carrying the geometry of the scan it was predicted from.
#'
#' Each file is `<name><suffix>_<class>.nii.gz`. The class name becomes part of a filename the
#' same way [save_class_masks()] does, and two class names that become the same filename are
#' refused rather than written.
#'
#' Why one file per class rather than one file with several values: a voxel in the tumour core
#' is also in the whole tumour, and no single integer says both. Any viewer can load three
#' binary masks over one scan; none can unpack an overlap out of one label map.
#'
#' @param masks Channel probabilities - a list of `depth x height x width x class` arrays,
#'   which is what `predict(type = "probability", space = "source")` gives, or one stacked
#'   `volume x depth x height x width x class` array.
#' @param dir Directory to write into; created if it does not exist.
#' @param reference The scan each mask was predicted from, as paths. Every class of one scan
#'   is written with that scan's geometry, which is the whole reason this is not
#'   [save_class_masks()] with a different extension.
#' @param classes One name per channel, in channel order, which is the order the regions were
#'   written in. `inspect_masks()` names them the same way.
#' @param names File name stems, one per volume. Defaults to the reference file names with
#'   their extensions removed - and names that collide are refused, because one directory per
#'   case usually means the same filename inside each.
#' @param suffix Added before the class, so predictions from different models can sit in one
#'   directory.
#' @param threshold A class is written where its channel reaches this. 0.5 is what every
#'   metric in the engine thresholds a channel at.
#' @return The paths written, invisibly, volume by volume and within a volume class by class.
#' @seealso [save_class_masks()] for 2D, [save_volumes()] for exclusive classes.
#' @export
#' @examples
#' \dontrun{
#' channels <- predict(fit, "brats", split = "test", type = "probability", space = "source")
#' save_class_volumes(channels, "predictions",
#'                    reference = split_path(split, "test")$image,
#'                    classes = c("whole tumour", "tumour core", "enhancing"))
#' }
save_class_volumes <- function(masks, dir, reference, classes, names = NULL, suffix = "",
                               threshold = 0.5) {
  channels <- as_channel_volume_list(masks)

  count <- length(channels)
  reference <- as.character(reference)
  if (length(reference) != count) {
    stop("`reference` has ", length(reference), " entries but there are ", count,
         " predictions. Each class is written with the geometry of the scan it came from, ",
         "so they have to line up.", call. = FALSE)
  }

  names <- if (is.null(names)) {
    sub("[.]nii([.]gz)?$", "", basename(reference), ignore.case = TRUE)
  } else {
    as.character(names)
  }
  if (length(names) != count) {
    stop("`names` has ", length(names), " entries but there are ", count, " predictions.",
         call. = FALSE)
  }
  if (anyDuplicated(names)) {
    repeated <- unique(names[duplicated(names)])
    stop("the predictions would be written to the same names: ",
         paste(utils::head(repeated, 3), collapse = ", "),
         if (length(repeated) > 3) ", ..." else "",
         ". Names come from the reference files, and one directory per case usually means ",
         "the same filename in each. Pass `names`.", call. = FALSE)
  }

  # One call, and everything after this point is the engine's: the per-class filenames, the
  # threshold, the channel count against the names, the affine and the integer labels.
  #
  # It used to be a loop over classes with `write_volumes()` called once each, and the
  # filenames were computed here by `class_file_names()` - a second copy of a rule the
  # engine already had for pictures, kept honest by a test comparing the two over names
  # that are awkward on a filesystem. `pyplatypus 0.8.0a29` put the writer in the engine,
  # so the copy is gone and so is the test: the drift it guarded cannot happen now.
  result <- shim()$write_class_volumes(
    channels, dir, as.list(reference), as.list(as.character(classes)),
    cases = as.list(names), threshold = threshold, suffix = suffix
  )
  if (!isTRUE(result$ok)) abort_engine(result)
  # Volume by volume rather than class by class, matching `save_class_masks()`. The engine
  # returns them in that order already, which is why nothing reshapes them here.
  invisible(unlist(result$paths))
}

#' Channel probabilities per volume, whatever form they arrived in
#'
#' Deliberately stricter than `as_volume_list()`: there is no rank here that could be either
#' thing, because a prediction with a class axis always has one more dimension than the
#' volume. So the ambiguity that function documents does not exist in this one, and a rank
#' that is not 4 or 5 is a mistake rather than a guess.
#' @keywords internal
#' @noRd
as_channel_volume_list <- function(masks) {
  if (is.list(masks)) {
    # Unnamed, for the reason `as_volume_list` records: a named R list crosses into Python
    # as a `dict` and the writer is handed something it cannot read.
    unname(lapply(masks, function(one) {
      if (length(dim(one)) != 4L) {
        stop("a prediction in the list has ", length(dim(one)), " dimensions; expected 4 - ",
             "`depth x height x width x class`.", call. = FALSE)
      }
      one
    }))
  } else if (length(dim(masks)) == 5L) {
    lapply(seq_len(dim(masks)[1]), function(i) masks[i, , , , , drop = TRUE])
  } else if (length(dim(masks)) == 4L) {
    list(masks)
  } else {
    stop("`masks` has ", length(dim(masks)), " dimensions; expected 4 (one volume's ",
         "channels), 5 (a stack of them) or a list of 4-dimensional arrays. ",
         "`predict(type = \"probability\")` returns those.", call. = FALSE)
  }
}
