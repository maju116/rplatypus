# Pictures.
#
# The package's reason for existing, as much as the training is. Getting from a folder of
# images to a figure that can go in a paper is the job; a model is the middle of it.

#' Read images as the model sees them
#'
#' Reads through the engine's own pipeline rather than a separate decoder, so what you
#' plot is what the model was given. A picture drawn from a differently resized copy is a
#' picture of something the model never saw, and the disagreements it appears to show may
#' be nothing but the resizing.
#'
#' @param paths Image files.
#' @param size `c(height, width)` to read at, or `NULL` to keep each image's own size -
#'   which only works if they all agree.
#' @param channels 3 for colour, 1 for greyscale.
#' @param nearest Use nearest-neighbour resizing. Required for masks: interpolating one
#'   invents colours belonging to no class, which then quietly become background.
#' @param label_map The file holds class identities rather than brightness, so read it at
#'   full integer width. A 16-bit PNG or a 32-bit TIFF label map is otherwise read through
#'   8-bit greyscale, where every value above 255 arrives as 255 - two classes then merge
#'   into one with nothing unmatched to say so. One channel only, because a label map has
#'   one, and never for an image: a picture is divided by 255 later.
#' @return An `image x height x width x channels` array of 0-255 values - or of the file's
#'   own integer values with `label_map = TRUE`, which is the point of that argument.
#' @export
#' @examples
#' \dontrun{
#' images <- read_images(list.files("test/", full.names = TRUE), size = c(256, 256))
#'
#' # A label map stored wide, whose values are classes rather than brightness.
#' values <- read_images("seg.png", channels = 1, nearest = TRUE, label_map = TRUE)
#' }
read_images <- function(paths, size = NULL, channels = 3, nearest = FALSE,
                        label_map = FALSE) {
  result <- shim()$read_images(as.list(as.character(paths)),
                               channels = as.integer(channels),
                               size = if (is.null(size)) NULL else as.integer(size),
                               nearest = nearest,
                               label_map = label_map)
  if (!isTRUE(result$ok)) abort_engine(result)
  result$images
}

#' Look at masks beside the images they came from
#'
#' Builds a grid: one row per image, one column per panel. Which panels appear depends on
#' what you pass - the image alone, the truth, the prediction, and where they disagree.
#'
#' The disagreement panel is usually the one worth looking at. It separates what was found
#' from what was missed and what was invented, and those are not interchangeable: for most
#' clinical questions a missed lesion and a false alarm cost different things, and a single
#' overlap score hides which one you have.
#'
#' @param images An `image x height x width x channels` array, or one
#'   `height x width x channels` image.
#' @param prediction Predicted class indices, from [predict.platypus_fit()].
#' @param truth True class indices, if you have them.
#' @param colormap A list of RGB triples, one per class.
#' @param which Which images to show.
#' @param alpha How strongly to tint the overlays.
#' @param labels Row labels; defaults to the image number.
#' @param slice For volumes, which slice to draw. A volume cannot honestly be shown as one
#'   picture, so one plane is chosen and said out loud rather than a projection being
#'   invented. Counted along the last axis, which after the canonical reorientation is the
#'   axial direction - the view a radiologist scrolls through. `"middle"` takes the middle
#'   slice, which is the sensible first look.
#' @return A `ggplot`.
#' @export
#' @examples
#' \dontrun{
#' plot_masks(images, prediction = masks, truth = truth, colormap = binary_colormap)
#' }
plot_masks <- function(images, prediction = NULL, truth = NULL,
                       colormap = binary_colormap, which = NULL,
                       alpha = drawing_style()$overlay_alpha, labels = NULL,
                       slice = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("plot_masks() needs the ggplot2 package.", call. = FALSE)
  }

  if (is_volumetric(images)) {
    if (is.null(slice)) {
      stop("these look like volumes (", paste(dim(images), collapse = " x "), "). ",
           "Choose a slice to draw - `slice = \"middle\"` to start - because a volume ",
           "shown as one picture is either a lie or a projection nobody asked for.",
           call. = FALSE)
    }
    images <- take_slice(images, slice, channels = TRUE)
    prediction <- take_slice(prediction, slice, channels = FALSE)
    truth <- take_slice(truth, slice, channels = FALSE)
  } else if (!is.null(slice)) {
    stop("`slice` only applies to volumes; these are ", length(dim(images)) - 2L,
         "D images.", call. = FALSE)
  }

  images <- as_image_stack(images)
  if (is.null(which)) which <- seq_len(min(4L, n_images(images)))
  which <- as.integer(which)

  panels <- "image"
  if (!is.null(truth)) panels <- c(panels, "truth")
  if (!is.null(prediction)) panels <- c(panels, "prediction")
  if (!is.null(truth) && !is.null(prediction)) panels <- c(panels, "agreement")

  rows <- lapply(which, function(i) {
    image <- as_rgb(images[i, , , , drop = FALSE][1, , , , drop = TRUE])
    lapply(panels, function(panel) {
      switch(panel,
        image = as_rgb(image),
        truth = classes_to_colours(slice_mask(truth, i), colormap),
        prediction = classes_to_colours(slice_mask(prediction, i), colormap),
        agreement = overlay_agreement(image, slice_mask(prediction, i),
                                      slice_mask(truth, i), alpha = alpha)
      )
    })
  })

  montage <- bind_panels(rows)
  height <- dim(montage)[1]
  width <- dim(montage)[2]
  tile_h <- height / length(which)
  tile_w <- width / length(panels)

  ggplot2::ggplot() +
    ggplot2::annotation_raster(
      grDevices::as.raster(montage / 255),
      xmin = 0, xmax = width, ymin = 0, ymax = height, interpolate = FALSE
    ) +
    ggplot2::scale_x_continuous(
      limits = c(0, width), expand = c(0, 0),
      breaks = (seq_along(panels) - 0.5) * tile_w, labels = panels, position = "top"
    ) +
    ggplot2::scale_y_continuous(
      limits = c(0, height), expand = c(0, 0),
      breaks = height - (seq_along(which) - 0.5) * tile_h,
      labels = labels %||% paste("image", which)
    ) +
    ggplot2::coord_fixed() +
    ggplot2::labs(x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      axis.ticks = ggplot2::element_blank()
    )
}

#' Plot what happened during training
#'
#' One panel per quantity, one line per model. Useful for the thing a final number cannot
#' tell you: whether it had stopped improving, or was still going when it ran out of
#' epochs.
#'
#' @param x A [platypus_fit()].
#' @param metrics Which columns to plot; defaults to the losses and metrics.
#' @param ... Unused.
#' @return A `ggplot`.
#' @importFrom rlang .data
#' @export
#' @examples
#' \dontrun{
#' plot(fit)                              # every metric that was recorded
#' plot(fit, metrics = "dice")
#' }
plot.platypus_fit <- function(x, metrics = NULL, ...) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("plotting a fit needs the ggplot2 package.", call. = FALSE)
  }
  history <- training_history(x)
  if (!nrow(history)) stop("this fit has no history to plot.", call. = FALSE)

  ignore <- c("model", "epoch", "seconds", "learning_rate")
  metrics <- metrics %||% setdiff(names(history), ignore)

  long <- do.call(rbind, lapply(metrics, function(metric) {
    data.frame(model = history$model, epoch = history$epoch,
               quantity = metric, value = history[[metric]],
               stringsAsFactors = FALSE)
  }))
  # train_loss and val_loss belong on the same panel; train_dice and val_dice likewise.
  long$panel <- sub("^(train|val)_", "", long$quantity)
  long$split <- ifelse(grepl("^train_", long$quantity), "train", "validation")

  ggplot2::ggplot(long, ggplot2::aes(x = .data$epoch, y = .data$value,
                                     colour = .data$model,
                                     linetype = .data$split)) +
    ggplot2::geom_line(linewidth = 0.7) +
    ggplot2::geom_point(size = 1.2) +
    ggplot2::facet_wrap(~ panel, scales = "free_y") +
    # Epochs are counted, so half of one is not a thing. The default breaks offer 1.5 and
    # 2.5 on a short run, which is the sort of detail that makes a figure look unconsidered.
    ggplot2::scale_x_continuous(breaks = function(limits) {
      unique(as.integer(round(pretty(limits))))
    }) +
    ggplot2::labs(x = "epoch", y = NULL, colour = NULL, linetype = NULL) +
    ggplot2::theme_minimal(base_size = 11)
}

#' @keywords internal
#' @noRd
n_images <- function(images) {
  if (length(dim(images)) == 4L) dim(images)[1] else 1L
}

#' @keywords internal
#' @noRd
as_image_stack <- function(images) {
  if (length(dim(images)) == 3L) array(images, dim = c(1L, dim(images))) else images
}

#' @keywords internal
#' @noRd
slice_mask <- function(mask, i) {
  if (length(dim(mask)) == 3L) mask[i, , ] else mask
}

#' Lay panels out as one image: rows of samples, columns of views
#' @keywords internal
#' @noRd
bind_panels <- function(rows) {
  row_arrays <- lapply(rows, function(panels) {
    Reduce(function(a, b) abind_axis(a, b, 2L), panels)
  })
  Reduce(function(a, b) abind_axis(a, b, 1L), row_arrays)
}

#' Join two arrays along one axis, without taking a dependency to do it
#' @keywords internal
#' @noRd
abind_axis <- function(a, b, axis) {
  stopifnot(length(dim(a)) == 3L, length(dim(b)) == 3L)
  if (axis == 1L) {
    out <- array(0L, dim = c(dim(a)[1] + dim(b)[1], dim(a)[2], 3L))
    out[seq_len(dim(a)[1]), , ] <- a
    out[dim(a)[1] + seq_len(dim(b)[1]), , ] <- b
  } else {
    out <- array(0L, dim = c(dim(a)[1], dim(a)[2] + dim(b)[2], 3L))
    out[, seq_len(dim(a)[2]), ] <- a
    out[, dim(a)[2] + seq_len(dim(b)[2]), ] <- b
  }
  out
}


#' Does this array hold volumes rather than images?
#'
#' Read off the rank: a stack of images is (n, h, w, c) and a stack of volumes is
#' (n, d, h, w, c). One volume, (d, h, w, c), has the same rank as a stack of images, and
#' that ambiguity is real - it is resolved by the caller passing `slice`, which is why an
#' unsliced volume is an error rather than a guess.
#' @keywords internal
#' @noRd
is_volumetric <- function(images) {
  length(dim(images)) == 5L
}

#' Take one plane out of a volume, along the last spatial axis
#' @keywords internal
#' @noRd
take_slice <- function(x, slice, channels) {
  if (is.null(x)) return(NULL)
  dims <- dim(x)
  rank <- length(dims)
  # Which axis is the slice: the last spatial one, which is the last axis for masks and the
  # one before the channels for images.
  axis <- if (channels) rank - 1L else rank
  depth <- dims[axis]

  index <- if (identical(slice, "middle")) {
    as.integer(ceiling(depth / 2))
  } else {
    as.integer(slice)
  }
  if (is.na(index) || index < 1L || index > depth) {
    stop("slice ", slice, " is outside 1..", depth, ".", call. = FALSE)
  }

  selector <- rep(list(quote(expr = )), rank)
  selector[[axis]] <- index
  out <- do.call(`[`, c(list(x), selector, list(drop = FALSE)))
  dim(out) <- dims[-axis]
  out
}

#' Draw boxes on images
#'
#' The detection counterpart of [plot_masks()], and the function the 2020 package had under
#' this name. Boxes arrive from [predict()] in each image's own pixels, so they land on the
#' picture without anything being undone first.
#'
#' Predictions and truth can be drawn together, and when they are, the point is the
#' comparison: truth in one colour, predictions in another, both on the same image. A
#' detector that found the right number of objects in the wrong places and one that found
#' the wrong number in the right places score similarly and look nothing alike.
#'
#' @param images An image stack from [read_images()], or a single image.
#' @param boxes Boxes to draw: one data frame as [predict()] returns per image, or a list
#'   of them - one per image in `images`. Columns `xmin`, `ymin`, `xmax`, `ymax`, and
#'   optionally `name` and `score`.
#' @param truth Boxes to draw as ground truth, the same shape as `boxes`.
#' @param which Which images to draw. Defaults to the first four, like [plot_masks()].
#' @param min_score Drop predicted boxes below this confidence before drawing. The default
#'   follows a detector's own `score_threshold` of 0.01, which is kept low so average
#'   precision can be computed over the whole ranking - and which puts far more boxes on a
#'   picture than anyone wants to look at. `0.5` is the usual choice for a figure.
#' @param labels Row labels. Defaults to the names of `boxes`, which [predict()] sets to
#'   the sample keys.
#' @param colours Named vector giving the colour for `prediction` and for `truth`.
#' @param size Line width of a box.
#' @param text_size Size of the class label, or `NULL` to draw no labels.
#' @return A ggplot object.
#' @seealso [predict.platypus_fit()], [plot_masks()]
#' @export
#' @examples
#' \dontrun{
#' found <- predict(fit, split = "test")
#' plot_boxes(read_images(files, size = NULL), found, min_score = 0.5)
#' }
plot_boxes <- function(images, boxes, truth = NULL, which = NULL,
                       min_score = drawing_style()$box_min_score,
                       labels = NULL, colours = drawing_style()$box_colours,
                       size = 0.6, text_size = 3) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("plot_boxes() needs the ggplot2 package.", call. = FALSE)
  }

  images <- as_image_stack(images)
  boxes <- as_box_list(boxes, "boxes")
  truth <- if (is.null(truth)) NULL else as_box_list(truth, "truth")

  if (length(boxes) != n_images(images)) {
    stop("`boxes` has ", length(boxes), " entr", if (length(boxes) == 1L) "y" else "ies",
         " and `images` has ", n_images(images), " image",
         if (n_images(images) == 1L) "" else "s",
         ". They must line up one to one - predict() returns one entry per image, ",
         "including the images where nothing was found, so that they do.", call. = FALSE)
  }
  if (!is.null(truth) && length(truth) != length(boxes)) {
    stop("`truth` has ", length(truth), " entries and `boxes` has ", length(boxes), ".",
         call. = FALSE)
  }

  if (is.null(which)) which <- seq_len(min(4L, n_images(images)))
  which <- as.integer(which)
  row_labels <- labels %||% names(boxes)[which] %||% paste("image", which)

  # One montage, images stacked vertically, so a box's coordinates only need the row's
  # offset added. Drawn as one raster for the same reason plot_masks() does: ggplot draws
  # one annotation_raster quickly and fifty slowly.
  tiles <- lapply(which, function(i) {
    as_rgb(images[i, , , , drop = FALSE][1, , , , drop = TRUE])
  })
  montage <- bind_panels(lapply(tiles, list))
  height <- dim(montage)[1]
  width <- dim(montage)[2]
  tile_h <- height / length(which)

  drawn <- do.call(rbind, lapply(seq_along(which), function(row) {
    i <- which[row]
    # y is measured from the bottom in ggplot and from the top in an image, so a box's
    # y flips. Getting this wrong draws every box mirrored about the middle of its tile,
    # which looks plausible on a symmetric picture and wrong on everything else.
    offset <- height - row * tile_h
    pieces <- list()
    if (!is.null(truth)) {
      pieces[[length(pieces) + 1L]] <- box_rows(truth[[i]], "truth", offset, tile_h, NULL)
    }
    pieces[[length(pieces) + 1L]] <- box_rows(boxes[[i]], "prediction", offset, tile_h,
                                              min_score)
    do.call(rbind, pieces)
  }))

  plot <- ggplot2::ggplot() +
    ggplot2::annotation_raster(
      grDevices::as.raster(montage / 255),
      xmin = 0, xmax = width, ymin = 0, ymax = height, interpolate = FALSE
    )

  if (!is.null(drawn) && nrow(drawn)) {
    plot <- plot + ggplot2::geom_rect(
      data = drawn,
      ggplot2::aes(xmin = .data$xmin, xmax = .data$xmax,
                   ymin = .data$ymin, ymax = .data$ymax, colour = .data$kind),
      fill = NA, linewidth = size
    )
    if (!is.null(text_size) && "label" %in% names(drawn)) {
      shown <- drawn[nzchar(drawn$label), , drop = FALSE]
      if (nrow(shown)) {
        plot <- plot + ggplot2::geom_text(
          data = shown,
          ggplot2::aes(x = .data$xmin, y = .data$ymax, label = .data$label,
                       colour = .data$kind),
          hjust = 0, vjust = -0.3, size = text_size, show.legend = FALSE
        )
      }
    }
  }

  plot +
    ggplot2::scale_colour_manual(values = colours, name = NULL) +
    ggplot2::scale_x_continuous(limits = c(0, width), expand = c(0, 0)) +
    ggplot2::scale_y_continuous(
      limits = c(0, height), expand = c(0, 0),
      breaks = height - (seq_along(which) - 0.5) * tile_h, labels = row_labels
    ) +
    ggplot2::coord_fixed() +
    ggplot2::labs(x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      axis.ticks = ggplot2::element_blank()
    )
}

#' A list of box frames, whatever shape was handed in
#'
#' One frame for one image is the common case and typing `list(found)` for it would be
#' noise, so a bare data frame is accepted and wrapped.
#'
#' @noRd
as_box_list <- function(boxes, what) {
  if (is.data.frame(boxes)) return(list(boxes))
  if (!is.list(boxes)) {
    stop("`", what, "` is a data frame of boxes, or a list of them - one per image. See ",
         "`?plot_boxes`.", call. = FALSE)
  }
  wrong <- which(!vapply(boxes, is.data.frame, logical(1)))
  if (length(wrong)) {
    stop("`", what, "`[[", wrong[[1]], "]] is not a data frame of boxes.", call. = FALSE)
  }
  boxes
}

#' One image's boxes, moved into the montage's coordinates
#'
#' @noRd
box_rows <- function(frame, kind, offset, tile_h, min_score) {
  needed <- c("xmin", "ymin", "xmax", "ymax")
  missing_columns <- setdiff(needed, names(frame))
  if (length(missing_columns)) {
    stop("boxes need the columns ", paste(needed, collapse = ", "), "; missing ",
         paste(missing_columns, collapse = ", "), ".", call. = FALSE)
  }
  if (!is.null(min_score) && "score" %in% names(frame)) {
    frame <- frame[frame$score >= min_score, , drop = FALSE]
  }
  if (!nrow(frame)) return(NULL)

  label <- if ("name" %in% names(frame)) as.character(frame$name) else rep("", nrow(frame))
  if (!is.null(min_score) && "score" %in% names(frame) && nzchar(label[[1]])) {
    label <- sprintf(drawing_style()$box_label_format, label, frame$score)
  }

  data.frame(
    xmin = frame$xmin,
    xmax = frame$xmax,
    # Flipped, and shifted into this image's row of the montage.
    ymin = offset + tile_h - frame$ymax,
    ymax = offset + tile_h - frame$ymin,
    kind = kind,
    label = label,
    stringsAsFactors = FALSE
  )
}

#' Draw the anchors against the boxes they were fitted to
#'
#' The picture the 2020 package drew, and the one no summary statistic replaces. Every
#' annotated box is a point - its width against its height, both as fractions of the
#' model's input - coloured by class, with the anchors on top.
#'
#' What it answers that a mean overlap does not: **whether a class has any anchor near it
#' at all**. A mean of 0.65 can be one class covered well and another not covered at all,
#' and those two situations want different fixes. On blood cells the three classes occupy
#' three distinct regions - median sides of 133, 69 and 26 pixels at a 416 input - and
#' anchors fitted to all three together cover them at 0.88, 0.85 and 0.83, so fitting to
#' the mixture does not abandon the smallest class. COCO's nine cover the same three at
#' 0.64, 0.70 and 0.70: *evenly* worse rather than blind to one, which is the useful thing
#' to know. They are not aimed elsewhere - they span 10 to 373 pixels a side because COCO
#' holds objects of every size, and most of that range describes nothing here.
#'
#' Worth drawing for a split the anchors were **not** fitted on. Anchors that sit among the
#' training boxes and away from the validation ones say the two halves hold different
#' objects, and no training curve shows that.
#'
#' @param object A fit from [platypus_fit()] on a detection specification.
#' @param model Which model, when the specification trained several.
#' @param split Which split's boxes to draw.
#' @param log Draw both axes on a log scale. Detection datasets span a wide range of sizes
#'   - a BCCD platelet is about two fifths the side of a red cell and a fifth of a white
#'   one - and on linear axes the smallest class collapses into the corner.
#' @param size Point size for the boxes.
#' @return A ggplot object.
#' @seealso [detection_anchors()] for the numbers, [yolo3()] for choosing them.
#' @export
#' @examples
#' \dontrun{
#' fit <- platypus_fit(spec)
#' plot_anchors(fit)                      # the split they were fitted to
#' plot_anchors(fit, split = "validation")  # and one they were not
#' }
plot_anchors <- function(object, model = NULL, split = "train", log = FALSE,
                         size = 1.1) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("plot_anchors() needs the ggplot2 package.", call. = FALSE)
  }
  if (!inherits(object, "platypus_fit") || !identical(object$task, "object_detection")) {
    stop("`plot_anchors()` needs a fit from a detection specification; anchors are a ",
         "detector's, and a U-Net has none.", call. = FALSE)
  }
  model <- model %||% object$models[[1]]
  result <- shim()$anchor_shapes(object$engine, model, split = split)
  if (!isTRUE(result$ok)) abort_engine(result)

  boxes <- as.data.frame(result$boxes, stringsAsFactors = FALSE)
  if (!nrow(boxes)) {
    stop("the '", split, "' split has no boxes to draw.", call. = FALSE)
  }
  anchors <- matrix(unlist(result$anchors), ncol = 2, byrow = TRUE)
  anchors <- data.frame(width = anchors[, 1], height = anchors[, 2])

  # One colour per class, from the engine's palette rather than ggplot2's default hue scale:
  # the default is not colourblind-safe, which is the same reason the box colours are what
  # they are. Cycled, because beyond eight classes no palette is readable.
  # Keyed on the specification's class order, not on which classes this split happens to
  # contain. Keyed on what is present, a class missing from validation would shift every
  # class after it to another colour, so the same cell would be green in one figure and
  # purple in the next - from one model, with nothing to say so.
  palette <- drawing_style()$class_colours
  known <- unlist(result$classes) %||% unique(boxes$name)
  values <- stats::setNames(palette[(seq_along(known) - 1L) %% length(palette) + 1L], known)

  plot <- ggplot2::ggplot() +
    ggplot2::geom_point(
      data = boxes,
      ggplot2::aes(x = .data$width, y = .data$height, colour = .data$name),
      alpha = 0.55, size = size
    ) +
    ggplot2::scale_colour_manual(values = values) +
    # Diamonds, hollow, drawn last so they sit on top of the cloud rather than under it.
    ggplot2::geom_point(
      data = anchors,
      ggplot2::aes(x = .data$width, y = .data$height),
      shape = 23, size = 2.6, stroke = 0.9, colour = "black", fill = NA
    ) +
    ggplot2::labs(
      x = "box width", y = "box height", colour = NULL,
      subtitle = sprintf(
        "%d boxes in '%s', %d anchors %s, as fractions of a %d x %d input",
        nrow(boxes), split, nrow(anchors),
        if (isTRUE(result$anchors_were_fitted)) "fitted to the training boxes"
        else "given in the specification",
        result$input_shape[[1]], result$input_shape[[2]]
      )
    ) +
    ggplot2::theme_minimal(base_size = 11)

  if (isTRUE(log)) {
    plot <- plot +
      ggplot2::scale_x_log10() +
      ggplot2::scale_y_log10()
  }
  plot
}
