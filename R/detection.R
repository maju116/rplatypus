# Boxes rather than masks.
#
# The task is never typed. `detection_data()` and `yolo3()` carry it, `platypus_spec()`
# reads it off them, and mixing a detection data block with a segmentation model is caught
# here rather than by the engine - the user has already said which they meant, twice, by
# choosing these functions.

#' Where the images and their annotation files are
#'
#' The detection counterpart of [segmentation_data()]. Two layouts, the same two as
#' segmentation: `nested_dirs` expects one directory per sample holding an `images` and an
#' `annotations` subdirectory, and `config_file` expects a CSV with `images` and
#' `annotations` columns. A detection dataset in Pascal VOC's own layout - one flat
#' `JPEGImages` beside one flat `Annotations` - is neither, and the way in is to write
#' three CSV files listing the pairs; `examples/detect_blood_cells.py` in the engine does
#' exactly that for BCCD in a dozen lines.
#'
#' @param train,validation Paths to the training and validation data.
#' @param classes Class names, **in class order**. Position is the class index the model
#'   learns, and that is why it is written down rather than read from the files: sorted,
#'   BCCD's three come out `Platelets, RBC, WBC`, which is reproducible and anatomically
#'   meaningless. A model trained with `RBC` first and used where the first class is
#'   `WBC` reports plausible boxes with plausible scores and nothing downstream can tell.
#'
#'   There is no background entry, unlike a segmentation colormap. A pixel always belongs
#'   to some class, so segmentation needs a name for "none of them"; a region of an image
#'   holding no object is simply not a box. One class is therefore a legitimate thing to
#'   ask for.
#' @param test Optional test data. Annotations are read if they are there, and the split is
#'   then scoreable; without them it can be predicted and [evaluate()] refuses it by name,
#'   because scoring against empty truth would report zero and a zero in a table reads as a
#'   result.
#' @param split Divide `train` instead of naming a `validation` set: a list with
#'   `fractions` (two numbers, or three to cut a test set too) and `group_by`, which is
#'   required and may be `NULL`. Exactly one of `split` and `validation`.
#'
#'   This is the only way to divide one folder for detection. [split_dataset()] writes a
#'   `masks` column and so cannot be used here; `split` divides the samples themselves, so
#'   column names never come into it. A test set cut this way carries its annotations, so
#'   unlike a separate `test` folder it can be scored and not only predicted on.
#' @param mode `"nested_dirs"` or `"config_file"`.
#' @param annotation_format `"pascal_voc"` for the XML most detection datasets ship, or
#'   `"labelme"` for its JSON.
#' @param coordinates How to read a Pascal VOC box. The format's own convention is 1-based
#'   and inclusive of both ends, so a ten-pixel-wide box runs `xmin=1 xmax=10` and the width
#'   is `xmax - xmin + 1`. Plenty of tools write the same files 0-based and exclusive, where
#'   that box is `xmin=0 xmax=10`. Reading one as the other shifts every box by a pixel and
#'   shrinks it by one, which is invisible at a glance and costs real overlap on a small
#'   object - at 24 pixels a side, one pixel is 4%.
#'
#'   `NULL`, the default, means the VOC convention. Only meaningful for `pascal_voc`:
#'   LabelMe stores continuous pixel coordinates and has no convention to pick, so giving
#'   both is an error rather than a setting that does nothing.
#' @param strict_labels Refuse an object whose class is not in `classes`. `FALSE` skips it
#'   instead, which is how you train on two of a dataset's three classes. `TRUE` by default,
#'   because an unexpected label is more often a typo in `classes` than an intention.
#' @param window How values in real units reach the model, for DICOM and NIfTI. See
#'   [segmentation_data()]; ignored for ordinary pictures, which is what most detection data
#'   is.
#' @param subdirs For `nested_dirs`, the names of the image and annotation subdirectories.
#' @param column_sep For `config_file`, what separates several paths in one cell.
#' @param shuffle Shuffle the training data between epochs.
#' @return A data specification, to be passed to [platypus_spec()].
#' @seealso [yolo3()], [plot_boxes()]
#' @export
#' @examples
#' detection_data("train/", "valid/", classes = c("RBC", "WBC", "Platelets"))
detection_data <- function(train, validation = NULL, classes, test = NULL,
                           split = NULL,
                           mode = c("nested_dirs", "config_file"),
                           annotation_format = c("pascal_voc", "labelme"),
                           coordinates = NULL, strict_labels = TRUE, window = NULL,
                           subdirs = c("images", "annotations"), column_sep = ";",
                           shuffle = TRUE) {
  # As in `segmentation_data()`, and for the same reason: a default sent from here is a
  # value the engine must treat as chosen. This constructor has two more than that one -
  # `annotation_format` and `strict_labels`.
  explicit_mode <- !missing(mode)
  gave <- list(
    annotation_format = !missing(annotation_format),
    strict_labels = !missing(strict_labels),
    subdirs = !missing(subdirs),
    column_sep = !missing(column_sep),
    shuffle = !missing(shuffle)
  )
  mode <- match.arg(mode)
  annotation_format <- match.arg(annotation_format)

  if (inherits(train, "platypus_split")) {
    stop("a `split_dataset()` carries mask paths, not annotation paths, so it cannot be ",
         "used for detection. Use `split` instead - it divides the samples themselves ",
         "rather than three CSV files, so the column names never come into it.",
         call. = FALSE)
  }
  check_split(validation, split, test)
  if (missing(classes) || !length(classes)) {
    stop("`classes` must name the classes, in class order - position is the class index ",
         "the model learns. See `?detection_data`.", call. = FALSE)
  }
  classes <- as.character(classes)
  if (anyNA(classes) || any(!nzchar(classes))) {
    stop("every entry in `classes` must be a non-empty name.", call. = FALSE)
  }
  if (anyDuplicated(classes)) {
    stop("`classes` must be distinct - two classes sharing a name cannot be told apart, ",
         "and one of them would never be matched.", call. = FALSE)
  }
  if (!is.null(coordinates)) {
    coordinates <- match.arg(coordinates, c("voc", "zero_based"))
    if (annotation_format != "pascal_voc") {
      stop("`coordinates` describes how to read a Pascal VOC box, and ",
           "annotation_format is '", annotation_format, "', which stores continuous ",
           "pixel coordinates and needs no convention.", call. = FALSE)
    }
  }
  if (length(subdirs) != 2L) {
    stop("`subdirs` names two directories: the images, and the annotations.",
         call. = FALSE)
  }

  structure(
    list(
      train_path = train,
      # FALSE is not a path: it travels as the engine's `validation` flag with
      # `validation_path` absent, since both would be the contradiction the engine refuses.
      validation_path = if (isFALSE(validation)) NULL else validation,
      validation = if (isFALSE(validation)) FALSE else NULL,
      test_path = test,
      split = split_block(split),
      mode = if (explicit_mode || !identical(mode, "nested_dirs")) mode else NULL,
      classes = classes,
      annotation_format = if (gave$annotation_format) annotation_format else NULL,
      # NULL unless asked for, and `compact()` drops it before the request is built -
      # the rule every option here follows, so an engine that has never heard of a
      # field keeps working for everyone not asking for it.
      coordinates = coordinates,
      strict_labels = if (gave$strict_labels) strict_labels else NULL,
      # Aligned under the `if` it continues: the chain reads as one decision.
      window = if (is.null(window)) NULL
               else if (is.character(window)) window  # nolint: indentation_linter.
               else as.numeric(window),
      subdirs = if (gave$subdirs) as.character(subdirs) else NULL,
      column_sep = if (gave$column_sep) column_sep else NULL,
      shuffle = if (gave$shuffle) shuffle else NULL
    ),
    class = c("platypus_detection_data", "list"),
    task = "object_detection"
  )
}

#' YOLOv3
#'
#' One detector, as an entry in [platypus_spec()]'s `models`.
#'
#' **Anchors.** Unset, they are fitted to your training boxes with k-means under an IoU
#' distance, which is what you want: COCO's nine anchors borrowed for blood cells cover
#' their boxes at a mean overlap of 0.65 against 0.88 for anchors fitted to them. Fitted
#' anchors are recorded with the run and in the sidecar when weights are exported, because
#' **a detector cannot be reloaded without them** - the same weights read with other
#' anchors decode every box scaled by a fixed factor, with plausible boxes, plausible
#' scores, wrong places, and nothing in the output to say so.
#'
#' For the same reason, naming `weights` and `anchors` together is an error: loading takes
#' the anchors recorded beside the file, which would leave the ones here describing nothing.
#'
#' @param name Unique within a spec; names the outputs.
#' @param input_shape `c(height, width)`, each a multiple of 32. The three grids are the
#'   input divided by 32, 16 and 8, so a side that does not divide gives a coarsest grid
#'   that does not tile the image. Bigger is not obviously better: on BCCD, 608 bought
#'   0.014 of mAP@0.5 for twice the training time, and the grid does not quantise a box's
#'   centre - the strides are fixed and the offset is a continuous output, so a larger
#'   input buys more cells rather than finer ones.
#' @param channels Channels the model takes.
#' @param anchors Box shapes to predict offsets from, **as fractions of the input size**:
#'   a list of three groups, coarsest grid first, each group a list of `c(width, height)`
#'   pairs. COCO publishes its nine in pixels at a 416 input, so those need dividing by
#'   416. `NULL` fits them to your data.
#' @param anchors_per_grid How many anchors to fit per grid when `anchors` is unset. It also
#'   sets the head's width, which is `anchors_per_grid * (n_class + 5)`.
#' @param ignore_threshold A cell that is not responsible for an object but whose box
#'   overlaps one this much is left unsupervised rather than trained towards "no object".
#'   Without it, a nearly-correct guess beside the responsible cell is punished, which is
#'   the one thing a detector should not learn.
#' @param score_threshold Discard a predicted box below this confidence. Low on purpose:
#'   average precision is computed over the whole ranking, so a cut here is a ceiling on
#'   recall that no threshold chosen later can lift.
#' @param nms_threshold Two boxes of the same class overlapping this much are one object and
#'   the lower-scoring one is dropped. Per class, so a platelet on a red cell survives.
#' @param operating_point The confidence at which precision and recall are reported.
#'   Separate from `score_threshold` because they answer different questions: that one
#'   decides what is computed at all, this one decides where on the curve to stand.
#' @param min_visibility How much of a box must survive an augmentation that removes part of
#'   the frame, as a fraction of its original area. A convention rather than a measurement;
#'   what is defensible is the direction. A box keeping two pixels of a cell teaches the
#'   model that a two-pixel fragment is a whole cell, which produces false positives
#'   everywhere, while dropping a heavily truncated object only fails to teach it about that
#'   object. Irrelevant unless a transform can lose part of the frame, which flips and
#'   rotations never do.
#' @param box_loss How the box coordinates are scored: `"offsets"`, YOLOv3's own, or
#'   `"giou"`. Unset uses the engine's default, which is `"offsets"` - what the published
#'   `bccd-yolo3` weights were trained with.
#'
#'   **`"giou"` is not the better objective, and that is measured.** Blood cells, three
#'   seeds each, 150 epochs, on the dataset's own test split:
#'
#'   | `box_loss` | mAP@0.5 | mAP@\[.50:.95\] | matched IoU |
#'   |---|---|---|---|
#'   | `giou` | 0.8666 ±0.0147 | 0.5078 ±0.0083 | 0.7929 ±0.0069 |
#'   | `offsets` | 0.8583 ±0.0167 | 0.5172 ±0.0195 | **0.8038 ±0.0001** |
#'
#'   Average precision separates them in neither direction - both gaps are smaller than the
#'   seed spread. The overlap of the boxes it matched does separate them, and `"giou"` is
#'   worse by 0.011, which is 2.7 standard errors of the difference. It is also sixty times
#'   less repeatable on exactly that quantity.
#'
#'   The reason is visible in `detection_anchors()`: GIoU exists because plain IoU is a flat
#'   zero for boxes that do not touch, so it has no gradient where a detector is most wrong -
#'   and anchors fitted to blood cells already cover them at a mean IoU of 0.877, so a
#'   prediction never starts disjoint and the advantage never arrives. On data whose fitted
#'   anchors cover poorly it should be a different story, which is untested and so not
#'   claimed.
#'
#'   **Choose it to read the loss, not to raise the score.** The offsets term cannot reach
#'   zero - cross-entropy against a soft target bottoms out at that target's entropy - so a
#'   converged run and a stalled one print the same number, near 5.9. Under `"giou"` the
#'   coordinate term in [training_history()] reads about 0.05 on training against 0.47 on
#'   validation: a localisation gap you can see, because zero means the boxes are right.
#' @param optimizer,callbacks,augmentation,epochs,batch_size As for [u_net()]. There is no
#'   `loss` and no `metrics`: YOLOv3's objective is part of its architecture, and mean
#'   average precision is not one option among several. A field that accepts a value and
#'   ignores it is worse than no field.
#' @param weights A registry name such as `"bccd-yolo3"`, an `hf://owner/repo/file@commit`
#'   reference, or a path to a local file. The anchors come with it.
#' @param fit Set `FALSE` to load weights and skip training, which is how you get boxes on
#'   an image without a GPU and an afternoon.
#' @return One model specification.
#' @seealso [detection_data()], [plot_boxes()], [available_weights()]
#' @export
#' @examples
#' yolo3("cells", input_shape = c(416, 416))
#' yolo3("cells", input_shape = c(416, 416), weights = "bccd-yolo3", fit = FALSE)
yolo3 <- function(name, input_shape = c(416, 416), channels = NULL, anchors = NULL,
                  anchors_per_grid = NULL, ignore_threshold = NULL,
                  score_threshold = NULL, nms_threshold = NULL, operating_point = NULL,
                  min_visibility = NULL, box_loss = NULL,
                  optimizer = NULL, callbacks = NULL,
                  augmentation = NULL, epochs = NULL, batch_size = NULL,
                  weights = NULL, fit = NULL) {
  if (length(input_shape) != 2L) {
    stop("detection is 2D: `input_shape` is c(height, width). Boxes in a volume need a ",
         "3D detector, which this is not.", call. = FALSE)
  }
  if (any(as.integer(input_shape) %% 32L != 0L)) {
    stop("every side of `input_shape` must be divisible by 32 - the three grids are the ",
         "input divided by 32, 16 and 8. Got ",
         paste(as.integer(input_shape), collapse = " x "), ".", call. = FALSE)
  }
  if (!is.null(weights) && !is.null(anchors)) {
    stop("give `weights` or `anchors`, not both. A detector's weights decode boxes ",
         "relative to the anchors they were trained with, so loading uses the ones ",
         "recorded beside the file - which would leave these describing nothing.",
         call. = FALSE)
  }

  # Everything optional stays NULL and `compact()` drops it, so the engine's own default
  # applies and each of these is written down in one place. It also keeps
  # `anchors_per_grid` adoptable: a published detector records its own, and a default sent
  # from here would look like a choice and silence the file.
  structure(
    compact(list(
      name = name,
      architecture = "yolo3",
      input_shape = as.integer(input_shape),
      channels = int1(channels),
      anchors = as_anchor_groups(anchors),
      anchors_per_grid = int1(anchors_per_grid),
      ignore_threshold = ignore_threshold,
      score_threshold = score_threshold,
      nms_threshold = nms_threshold,
      operating_point = operating_point,
      min_visibility = min_visibility,
      box_loss = check_box_loss(box_loss),
      optimizer = optimizer,
      callbacks = callbacks,
      augmentation = augmentation,
      epochs = int1(epochs),
      batch_size = int1(batch_size),
      weights = weights,
      fit = fit
    )),
    class = c("platypus_detection_model", "list"),
    task = "object_detection"
  )
}

#' Anchors as the engine wants them, or a refusal that says which entry is wrong
#'
#' One of two names, checked here rather than across the bridge
#'
#' `models[0].box_loss` is a worse place to learn that a name was misspelled than the call
#' that wrote it, which is the same reason `as_anchor_groups()` checks here.
#'
#' @noRd
check_box_loss <- function(box_loss) {
  if (is.null(box_loss)) return(NULL)
  box_loss <- as.character(box_loss)
  if (length(box_loss) != 1L || !box_loss %in% c("offsets", "giou")) {
    stop("`box_loss` is \"offsets\" or \"giou\"; got ",
         paste(deparse(box_loss), collapse = " "),
         ". See `?yolo3` for which to want - on blood cells `giou` scored 0.011 lower on ",
         "the overlap of the boxes it matched, and is there to make the loss readable ",
         "rather than to raise the score.", call. = FALSE)
  }
  box_loss
}

#' R has no natural shape for "three groups of pairs", so this accepts the two forms a
#' person writes - a list of lists of pairs, or a three-by-N-by-2 array - and rejects the
#' rest by name. Checked here rather than across the bridge because a location like
#' `models[0].anchors` is a worse place to learn that the second group has one pair too few.
#'
#' @noRd
as_anchor_groups <- function(anchors) {
  if (is.null(anchors)) return(NULL)

  if (is.array(anchors) && length(dim(anchors)) == 3L && dim(anchors)[3] == 2L) {
    anchors <- lapply(seq_len(dim(anchors)[1]), function(g) {
      lapply(seq_len(dim(anchors)[2]), function(a) as.numeric(anchors[g, a, ]))
    })
  }
  if (!is.list(anchors)) {
    stop("`anchors` is a list of three groups, coarsest grid first, each group a list of ",
         "c(width, height) pairs - or an array of dimension c(3, n, 2).", call. = FALSE)
  }
  if (length(anchors) != 3L) {
    stop("`anchors` needs three groups, one per grid; got ", length(anchors), ".",
         call. = FALSE)
  }

  widths <- integer(0)
  out <- lapply(seq_along(anchors), function(g) {
    group <- anchors[[g]]
    if (is.matrix(group) && ncol(group) == 2L) {
      group <- lapply(seq_len(nrow(group)), function(r) as.numeric(group[r, ]))
    }
    if (!is.list(group) || !length(group)) {
      stop("group ", g, " of `anchors` must be a non-empty list of c(width, height) ",
           "pairs.", call. = FALSE)
    }
    widths[[g]] <<- length(group)
    lapply(seq_along(group), function(a) {
      pair <- as.numeric(group[[a]])
      if (length(pair) != 2L || anyNA(pair)) {
        stop("anchor ", a, " of group ", g, " must be c(width, height).", call. = FALSE)
      }
      if (any(pair <= 0) || any(pair > 1)) {
        stop("anchors are fractions of the input size, so each must be above 0 and at ",
             "most 1; group ", g, " anchor ", a, " is ",
             paste(signif(pair, 4), collapse = " x "),
             ". COCO publishes its anchors in pixels at a 416 input - those need ",
             "dividing by 416.", call. = FALSE)
      }
      pair
    })
  })

  if (length(unique(widths)) != 1L) {
    stop("every grid needs the same number of anchors - the head is one tensor of width ",
         "anchors_per_grid * (n_class + 5); got ", paste(widths, collapse = ", "), ".",
         call. = FALSE)
  }
  out
}

#' Which task a data block or a model belongs to, or `NULL` when it does not say
#'
#' Read off the object rather than asked for. A user choosing `detection_data()` and
#' `yolo3()` has said which they meant twice already, and a third place to say it is a
#' third place to disagree.
#'
#' **`NULL` for an untagged object, and that is `maju116/rplatypus#239`.** This used to
#' answer `"semantic_segmentation"` for anything with no tag, which made a *bare* `data`
#' list - a plain list of fields rather than one of the four constructors - indistinguishable
#' from `segmentation_data()`. The bare path could then express one task out of four, and a
#' stated `task` was refused for disagreeing with an answer nobody had given. Every
#' constructor tags itself now, including the two that used to rely on the default, so an
#' absent tag means *this object says nothing* rather than *this object says segmentation*.
#'
#' @noRd
task_of <- function(x) {
  attr(x, "task", exact = TRUE)
}
