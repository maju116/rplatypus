# Boxes, from R.
#
# The tests that need no Python come first, because they are the ones that run everywhere
# and they cover the part this package is actually responsible for: saying no clearly, and
# turning what the engine returns into something an R user can use.

test_that("detection_data carries the task so nobody has to type it", {
  data <- detection_data("train/", "valid/", classes = c("RBC", "WBC"))
  expect_s3_class(data, "platypus_detection_data")
  expect_identical(attr(data, "task"), "object_detection")
  expect_identical(data$classes, c("RBC", "WBC"))
  # `subdirs` and `annotation_format` are no longer sent unless the caller names them
  # (#148): a default sent from R is a value the engine has to treat as chosen. They used
  # to be asserted here as present, which is what made this test the one that noticed.
  expect_null(data$subdirs)
  expect_null(data$annotation_format)
  expect_identical(
    detection_data("train/", "valid/", classes = "cell",
                   subdirs = c("pics", "boxes"))$subdirs,
    c("pics", "boxes")
  )
})

test_that("a segmentation data block has no task attribute and defaults to segmentation", {
  data <- segmentation_data("train/", "valid/", colormap = binary_colormap)
  expect_null(attr(data, "task"))
  expect_identical(rplatypus:::task_of(data), "semantic_segmentation")
})

test_that("classes must be named, distinct and non-empty", {
  expect_error(detection_data("a/", "b/"), "must name the classes")
  expect_error(detection_data("a/", "b/", classes = c("RBC", "RBC")), "distinct")
  expect_error(detection_data("a/", "b/", classes = c("RBC", "")), "non-empty")
})

test_that("one class is allowed, because there is no background entry", {
  expect_identical(detection_data("a/", "b/", classes = "cell")$classes, "cell")
})

test_that("coordinates only mean something for Pascal VOC", {
  expect_error(
    detection_data("a/", "b/", classes = "cell", annotation_format = "labelme",
                   coordinates = "zero_based"),
    "continuous"
  )
  expect_identical(
    detection_data("a/", "b/", classes = "cell", coordinates = "zero_based")$coordinates,
    "zero_based"
  )
})

test_that("a split carries mask paths, so it is refused for detection", {
  fake <- structure(list(), class = "platypus_split")
  expect_error(detection_data(fake, "b/", classes = "cell"), "annotation paths")
})


# --- yolo3 ------------------------------------------------------------------------------

test_that("yolo3 refuses an input the grids cannot tile", {
  expect_error(yolo3("d", input_shape = c(400, 400)), "divisible by 32")
  expect_error(yolo3("d", input_shape = c(416, 400)), "divisible by 32")
  expect_silent(yolo3("d", input_shape = c(416, 416)))
})

test_that("yolo3 is two-dimensional", {
  expect_error(yolo3("d", input_shape = c(64, 64, 32)), "detection is 2D")
})

test_that("yolo3 offers no loss and no metrics", {
  # Not an omission: YOLOv3's objective is part of its architecture and mean average
  # precision is not one option among several, so there is nothing to choose.
  arguments <- names(formals(yolo3))
  expect_false("loss" %in% arguments)
  expect_false("metrics" %in% arguments)
})

test_that("anchors and weights together are refused, because loading adopts the file's", {
  expect_error(
    yolo3("d", input_shape = c(416, 416), weights = "bccd-yolo3",
          anchors = list(list(c(0.3, 0.3)), list(c(0.2, 0.2)), list(c(0.1, 0.1)))),
    "not both"
  )
})

test_that("anchors are fractions, and pixels say so by name", {
  # The mistake someone makes once: COCO publishes its nine in pixels at a 416 input.
  coco <- list(
    list(c(116, 90), c(156, 198), c(373, 326)),
    list(c(30, 61), c(62, 45), c(59, 119)),
    list(c(10, 13), c(16, 30), c(33, 23))
  )
  expect_error(yolo3("d", input_shape = c(416, 416), anchors = coco),
               "dividing by 416")

  fractions <- lapply(coco, function(group) lapply(group, function(p) p / 416))
  model <- yolo3("d", input_shape = c(416, 416), anchors = fractions)
  expect_length(model$anchors, 3L)
  expect_equal(model$anchors[[1]][[1]], c(116, 90) / 416)
})

test_that("anchors accept an array as well as nested lists", {
  values <- array(0, dim = c(3, 2, 2))
  values[, , 1] <- c(0.4, 0.2, 0.1)
  values[, , 2] <- c(0.4, 0.2, 0.1)
  model <- yolo3("d", input_shape = c(416, 416), anchors = values, anchors_per_grid = 2)
  expect_length(model$anchors, 3L)
  expect_length(model$anchors[[1]], 2L)
})

test_that("uneven anchor groups are refused, because the head is one tensor", {
  uneven <- list(list(c(0.5, 0.5), c(0.4, 0.4)), list(c(0.2, 0.2)), list(c(0.1, 0.1)))
  expect_error(yolo3("d", input_shape = c(416, 416), anchors = uneven),
               "same number of anchors")
})

test_that("the wrong number of groups is refused", {
  expect_error(
    yolo3("d", input_shape = c(416, 416), anchors = list(list(c(0.1, 0.1)))),
    "three groups"
  )
})


# --- the task is inferred, and mixing is refused ------------------------------------------

test_that("mixing a detection data block with a segmentation model is refused by name", {
  expect_error(
    rplatypus:::agreed_task(
      detection_data("a/", "b/", classes = "cell"),
      list(u_net("u", input_shape = c(64, 64)))
    ),
    "mixes them"
  )
})

test_that("the refusal names the model that disagrees", {
  caught <- tryCatch(
    rplatypus:::agreed_task(
      detection_data("a/", "b/", classes = "cell"),
      list(yolo3("good", input_shape = c(416, 416)),
           u_net("bad", input_shape = c(64, 64)))
    ),
    error = function(e) conditionMessage(e)
  )
  expect_match(caught, "good is object_detection")
  expect_match(caught, "bad is semantic_segmentation")
})

test_that("an agreeing specification reports its one task", {
  expect_identical(
    rplatypus:::agreed_task(detection_data("a/", "b/", classes = "cell"),
                            list(yolo3("d", input_shape = c(416, 416)))),
    "object_detection"
  )
  expect_identical(
    rplatypus:::agreed_task(segmentation_data("a/", "b/", colormap = binary_colormap),
                            list(u_net("u", input_shape = c(64, 64)))),
    "semantic_segmentation"
  )
})


# --- plot_boxes, which needs no engine ----------------------------------------------------

test_that("plot_boxes draws boxes on an image stack", {
  skip_if_not_installed("ggplot2")
  images <- array(60, dim = c(2, 64, 96, 3))
  found <- list(
    one = data.frame(xmin = 10, ymin = 12, xmax = 40, ymax = 44, score = 0.9,
                     name = "cell"),
    two = data.frame(xmin = 50, ymin = 20, xmax = 80, ymax = 50, score = 0.8,
                     name = "cell")
  )
  plot <- plot_boxes(images, found)
  expect_s3_class(plot, "ggplot")
})

test_that("plot_boxes flips y, so a box near the top of the image is drawn near the top", {
  skip_if_not_installed("ggplot2")
  # The assertion that would catch a mirrored draw. An image row near y=0 is at the *top*
  # of the picture and near the *maximum* y in ggplot's coordinates, and getting that
  # backwards looks plausible on a symmetric figure.
  images <- array(60, dim = c(1, 100, 100, 3))
  near_top <- data.frame(xmin = 10, ymin = 5, xmax = 30, ymax = 25, score = 1,
                         name = "a")
  rows <- rplatypus:::box_rows(near_top, "prediction", offset = 0, tile_h = 100,
                               min_score = 0.5)
  expect_equal(rows$ymin, 100 - 25)
  expect_equal(rows$ymax, 100 - 5)
  expect_gt(rows$ymax, 50)
})

test_that("plot_boxes drops boxes below min_score and keeps the rest", {
  skip_if_not_installed("ggplot2")
  frame <- data.frame(xmin = c(1, 2), ymin = c(1, 2), xmax = c(10, 20),
                      ymax = c(10, 20), score = c(0.2, 0.9), name = c("a", "b"))
  kept <- rplatypus:::box_rows(frame, "prediction", 0, 100, min_score = 0.5)
  expect_equal(nrow(kept), 1L)
  expect_match(kept$label, "^b 0.90$")
})

test_that("plot_boxes refuses a count that cannot line up", {
  skip_if_not_installed("ggplot2")
  images <- array(60, dim = c(3, 64, 64, 3))
  expect_error(plot_boxes(images, list(data.frame(xmin = 1, ymin = 1, xmax = 2,
                                                  ymax = 2))),
               "line up one to one")
})

test_that("plot_boxes needs the four coordinate columns", {
  skip_if_not_installed("ggplot2")
  images <- array(60, dim = c(1, 64, 64, 3))
  expect_error(plot_boxes(images, data.frame(x = 1, y = 2)), "need the columns")
})

test_that("an image with nothing found is still an entry", {
  skip_if_not_installed("ggplot2")
  images <- array(60, dim = c(2, 64, 64, 3))
  empty <- data.frame(xmin = numeric(0), ymin = numeric(0), xmax = numeric(0),
                      ymax = numeric(0), score = numeric(0), name = character(0))
  found <- list(empty, data.frame(xmin = 5, ymin = 5, xmax = 20, ymax = 20,
                                  score = 0.9, name = "a"))
  expect_s3_class(plot_boxes(images, found), "ggplot")
})


# --- with the engine ----------------------------------------------------------------------

test_that("a detector trains, scores and returns boxes in each image's own pixels", {
  skip_if_no_detection()
  skip_if_not_installed("png")

  root <- withr::local_tempdir()
  write_detection_split(file.path(root, "train"), "train", 8, seed = 1)
  write_detection_split(file.path(root, "valid"), "valid", 4, seed = 2)

  spec <- platypus_spec(
    data = detection_data(file.path(root, "train"), file.path(root, "valid"),
                          classes = c("square", "bar")),
    models = list(yolo3("d", input_shape = c(128, 128), anchors_per_grid = 2,
                        epochs = 2, batch_size = 2)),
    seed = 1
  )
  fit <- platypus_fit(spec, device = "cpu")
  expect_identical(fit$task, "object_detection")

  # The four parts of the loss, for train and validation. A YOLOv3 total means nothing
  # alone - it has a floor above zero that depends on the data.
  expect_true(all(c("train_loss", "train_coordinates", "val_loss") %in%
                    names(fit$history)))

  table <- evaluate(fit, split = "validation")
  expect_true(all(c("map_50", "map_50_95", "mean_matched_iou") %in% names(table)))
  # Not here, and deliberately: averaging precision over classes needs a weighting and
  # every weighting is a different claim.
  expect_false("precision" %in% names(table))

  per_class <- evaluate_classes(fit, split = "validation")
  expect_equal(nrow(per_class), 2L)
  expect_true(all(c("precision", "recall") %in% names(per_class)))

  found <- predict(fit, split = "validation")
  expect_length(found, 4L)
  expect_named(found)
  expect_s3_class(found[[1]], "data.frame")
  expect_true(all(c("xmin", "ymin", "xmax", "ymax", "score", "label", "name") %in%
                    names(found[[1]])))
  # Source pixels, not the network's 128x128 frame: the images are 160 wide.
  if (nrow(found[[1]])) {
    expect_lte(max(found[[1]]$xmax), 160 + 1)
    expect_true(all(found[[1]]$name %in% c("square", "bar")))
    # 1-based, like the class indices `predict` returns for masks.
    expect_true(all(found[[1]]$label >= 1L))
  }
})

test_that("the anchors a run used come back, and say they were fitted", {
  skip_if_no_detection()
  skip_if_not_installed("png")

  root <- withr::local_tempdir()
  write_detection_split(file.path(root, "train"), "train", 8, seed = 3)
  write_detection_split(file.path(root, "valid"), "valid", 4, seed = 4)

  spec <- platypus_spec(
    data = detection_data(file.path(root, "train"), file.path(root, "valid"),
                          classes = c("square", "bar")),
    models = list(yolo3("d", input_shape = c(128, 128), anchors_per_grid = 2,
                        epochs = 1, batch_size = 2)),
    seed = 1
  )
  fit <- platypus_fit(spec, device = "cpu")

  anchors <- detection_anchors(fit)
  expect_true(anchors$fitted)
  expect_length(anchors$anchors, 3L)
  expect_length(anchors$anchors[[1]], 2L)
  expect_gt(anchors$mean_iou, 0.3)
  expect_equal(nrow(anchors$per_anchor), 6L)
})

test_that("predict refuses mask arguments on a detector, and only then", {
  # Both halves. `missing()` on a formal argument stops being true once the argument has
  # been assigned to, and `match.arg` assigns - so the first version of this refusal fired
  # for every caller, including the plain `predict(fit)` above. The test below is what
  # caught it, by making the ordinary call first.
  skip_if_no_detection()
  skip_if_not_installed("png")

  root <- withr::local_tempdir()
  write_detection_split(file.path(root, "train"), "train", 8, seed = 5)
  write_detection_split(file.path(root, "valid"), "valid", 4, seed = 6)

  spec <- platypus_spec(
    data = detection_data(file.path(root, "train"), file.path(root, "valid"),
                          classes = c("square", "bar")),
    models = list(yolo3("d", input_shape = c(128, 128), anchors_per_grid = 2,
                        epochs = 1, batch_size = 2)),
    seed = 1
  )
  fit <- platypus_fit(spec, device = "cpu")
  expect_error(predict(fit, split = "validation", space = "source"), "about masks")
  expect_error(predict(fit, split = "validation", type = "probability"), "about masks")
})

test_that("evaluate_classes refuses a segmentation fit, and says what to use", {
  skip_if_no_engine()
  fake <- structure(list(task = "semantic_segmentation", models = "u"), class = "platypus_fit")
  expect_error(evaluate_classes(fake), "evaluate_cases")
})

test_that("the engine refuses a detection specification it cannot read", {
  # Against a released engine this is the pin working: an older one rejects `task` and
  # every field under it. Against a current one the spec builds, which is what the skip
  # above already established.
  skip_if_no_detection()
  spec <- platypus_spec(
    data = detection_data(".", ".", classes = c("a", "b")),
    models = list(yolo3("d", input_shape = c(416, 416))),
    check_paths = FALSE
  )
  expect_s3_class(spec, "platypus_spec")
})


# --- the gap a vignette found ------------------------------------------------------------

test_that("every callback the engine offers has an R constructor", {
  # Written because `cosine_annealing` reached the engine's spec and not this package's, so
  # the recipe that produced the published BCCD weights could not be expressed from R at
  # all. Nothing in either test suite could notice: the engine's tests do not know R exists
  # and the R tests only exercise the constructors that exist. Writing the vignette as a
  # user would run it is what found it - the third time in this project (see the `hub`
  # extra), which is why it is now a test.
  skip_if_no_engine()

  # Asked the way the engine itself resolves a callback: the builders' keys. The
  # discriminated union is awkward to introspect and the builder map is the thing that
  # decides, so it is also the right thing to compare against.
  names_in_engine <- reticulate::py_eval(paste0(
    "sorted(s.model_fields['name'].default for s in ",
    "__import__('pyplatypus.training.callbacks', fromlist=['x'])._BUILDERS)"
  ))
  in_r <- sort(sub("^callback_", "", grep("^callback_", getNamespaceExports("rplatypus"),
                                          value = TRUE)))

  expect_setequal(names_in_engine, in_r)
})


# --- the picture of the anchor fit --------------------------------------------------------

test_that("plot_anchors draws the boxes and the anchors in one frame", {
  skip_if_no_anchor_plot()
  skip_if_not_installed("png")
  skip_if_not_installed("ggplot2")

  root <- withr::local_tempdir()
  write_detection_split(file.path(root, "train"), "train", 8, seed = 11)
  write_detection_split(file.path(root, "valid"), "valid", 4, seed = 12)

  spec <- platypus_spec(
    data = detection_data(file.path(root, "train"), file.path(root, "valid"),
                          classes = c("square", "bar")),
    models = list(yolo3("d", input_shape = c(128, 128), anchors_per_grid = 2,
                        epochs = 1, batch_size = 2)),
    seed = 1
  )
  fit <- platypus_fit(spec, device = "cpu")

  plot <- plot_anchors(fit)
  expect_s3_class(plot, "ggplot")

  # Two layers: the cloud and the anchors. A picture with only one of them is the failure
  # worth catching, and `ggplot` is happy to produce it.
  expect_length(plot$layers, 2L)

  cloud <- plot$layers[[1]]$data
  expect_equal(nrow(cloud), 16L)              # eight images, two boxes each
  expect_setequal(unique(cloud$name), c("square", "bar"))

  anchors <- plot$layers[[2]]$data
  expect_equal(nrow(anchors), 6L)             # three grids, two each
})

test_that("the cloud and the anchors are in the same coordinates", {
  skip_if_no_anchor_plot()
  skip_if_not_installed("png")
  skip_if_not_installed("ggplot2")

  root <- withr::local_tempdir()
  write_detection_split(file.path(root, "train"), "train", 8, seed = 13)
  write_detection_split(file.path(root, "valid"), "valid", 4, seed = 14)

  spec <- platypus_spec(
    data = detection_data(file.path(root, "train"), file.path(root, "valid"),
                          classes = c("square", "bar")),
    models = list(yolo3("d", input_shape = c(128, 128), anchors_per_grid = 2,
                        epochs = 1, batch_size = 2)),
    seed = 1
  )
  fit <- platypus_fit(spec, device = "cpu")
  plot <- plot_anchors(fit)

  cloud <- plot$layers[[1]]$data
  anchors <- plot$layers[[2]]$data

  # The property the picture rests on. k-means puts its centres among their points, so an
  # anchor far outside the cloud means the two were computed in different coordinates -
  # which would look like a bad fit rather than like a bug.
  expect_gte(min(anchors$width), min(cloud$width) * 0.5)
  expect_lte(max(anchors$width), max(cloud$width) * 2)
  expect_gte(min(anchors$height), min(cloud$height) * 0.5)
  expect_lte(max(anchors$height), max(cloud$height) * 2)

  # And both are fractions of the input, not pixels.
  expect_true(all(cloud$width > 0 & cloud$width <= 1))
  expect_true(all(anchors$width > 0 & anchors$width <= 1))
})

test_that("plot_anchors refuses a segmentation fit", {
  skip_if_not_installed("ggplot2")
  fake <- structure(list(task = "semantic_segmentation", models = "u"), class = "platypus_fit")
  expect_error(plot_anchors(fake), "a U-Net has none")
})


# --- the run record, which is where fitted anchors survive --------------------------------

test_that("nothing is written when output_dir was not given", {
  skip_if_no_detection()
  skip_if_not_installed("png")

  root <- withr::local_tempdir()
  write_detection_split(file.path(root, "train"), "train", 8, seed = 15)
  write_detection_split(file.path(root, "valid"), "valid", 4, seed = 16)

  # R used to send its own default, which would have put a record in every user's working
  # directory the moment the engine learned to write them. `output_dir` is NULL here and
  # `compact()` drops it, so the engine never hears about it.
  spec <- platypus_spec(
    data = detection_data(file.path(root, "train"), file.path(root, "valid"),
                          classes = c("square", "bar")),
    models = list(yolo3("d", input_shape = c(128, 128), anchors_per_grid = 2,
                        epochs = 1, batch_size = 2))
  )
  withr::with_dir(root, platypus_fit(spec, device = "cpu"))
  expect_false(dir.exists(file.path(root, "platypus_output")))
})

test_that("a record appears when output_dir was given, and carries the fitted anchors", {
  skip_if_no_detection()
  skip_if_not_installed("png")

  root <- withr::local_tempdir()
  write_detection_split(file.path(root, "train"), "train", 8, seed = 17)
  write_detection_split(file.path(root, "valid"), "valid", 4, seed = 18)
  out <- file.path(root, "runs")

  spec <- platypus_spec(
    data = detection_data(file.path(root, "train"), file.path(root, "valid"),
                          classes = c("square", "bar")),
    models = list(yolo3("d", input_shape = c(128, 128), anchors_per_grid = 2,
                        epochs = 1, batch_size = 2)),
    output_dir = out
  )
  fit <- platypus_fit(spec, device = "cpu")

  path <- file.path(out, "d", "run.json")
  expect_true(file.exists(path))

  # The reason it exists: the specification does not name the anchors when they were
  # fitted, so this is the only copy outside a weights sidecar somebody has to remember
  # to export.
  # Through `read_record()` rather than `jsonlite::fromJSON()`, which is what this read
  # before the package had a reader: a feature is not shipped until something uses it the
  # way a user reaches it, and the anchors are the strongest reason the reader exists.
  skip_if_not_installed("jsonlite")
  record <- read_record(path)
  expect_s3_class(record, "platypus_record")
  expect_true(record$derived$anchors_were_fitted)
  expect_length(record$derived$anchors, 3L)
  expect_equal(
    lapply(record$derived$anchors, function(g) lapply(g, unlist)),
    lapply(detection_anchors(fit)$anchors, function(g) lapply(g, unlist))
  )
})

# --- one row per image --------------------------------------------------------------------

test_that("evaluate_images gives one row per image, and the counts add up", {
  skip_if_no_evaluate_images()
  skip_if_not_installed("png")

  root <- withr::local_tempdir()
  write_detection_split(file.path(root, "train"), "train", 8, seed = 31)
  write_detection_split(file.path(root, "valid"), "valid", 4, seed = 32)

  spec <- platypus_spec(
    data = detection_data(file.path(root, "train"), file.path(root, "valid"),
                          classes = c("square", "bar")),
    models = list(yolo3("d", input_shape = c(128, 128), anchors_per_grid = 2,
                        epochs = 1, batch_size = 2))
  )
  fit <- platypus_fit(spec, device = "cpu")
  images <- evaluate_images(fit)

  expect_s3_class(images, "platypus_images")
  expect_equal(nrow(images), 4L)
  expect_setequal(
    names(images),
    c("key", "n_truth", "n_predicted", "matched", "missed", "spurious",
      "mean_matched_iou")
  )
  # Per row, the three outcomes are a partition of the counts, not three free numbers.
  expect_equal(images$missed, images$n_truth - images$matched)
  expect_equal(images$spurious, images$n_predicted - images$matched)

  # And they decompose the per-class table, which is the assertion that stops the two
  # from drifting apart.
  per_class <- evaluate_classes(fit)
  expect_equal(sum(images$n_truth), sum(per_class$n_truth))

  # No average precision per image: on one picture it is a property of a ranking that is
  # not there to rank.
  expect_false("average_precision" %in% names(images))
})

test_that("evaluate_images refuses a segmentation fit and names the alternative", {
  skip_if_no_engine()
  skip_if_not_installed("png")

  root <- tiny_dataset(n = 4, size = 32)
  spec <- platypus_spec(
    data = segmentation_data(root, root, colormap = binary_colormap),
    models = list(u_net("u", input_shape = c(32, 32), blocks = 2, filters = 4,
                        epochs = 1, batch_size = 2))
  )
  fit <- platypus_fit(spec, device = "cpu")
  expect_error(evaluate_images(fit), "evaluate_cases")
})

test_that("an image where nothing matched arrives as NA rather than zero", {
  # The claim the help page makes, pinned at the seam where it could quietly stop being
  # true: the engine returns None, and None has to cross into R as NA. A 0 would merge
  # "found nothing" with "found badly", which are different failures.
  rows <- list(
    list(key = "a", n_truth = 2L, n_predicted = 1L, matched = 1L, missed = 1L,
         spurious = 0L, mean_matched_iou = 0.83),
    list(key = "b", n_truth = 2L, n_predicted = 3L, matched = 0L, missed = 2L,
         spurious = 3L, mean_matched_iou = NULL)
  )
  frame <- rplatypus:::rows_to_frame(rows)
  expect_true(is.numeric(frame$mean_matched_iou))
  expect_true(is.na(frame$mean_matched_iou[2]))
  expect_false(isTRUE(frame$mean_matched_iou[2] == 0))
})

# --- stating the task ---------------------------------------------------------------------

test_that("task is derived when unset and checked when given", {
  data <- segmentation_data("train", "valid", colormap = binary_colormap)
  models <- list(u_net("u", input_shape = c(32, 32)))

  # Derived: the constructors already decided, so nothing has to be typed.
  expect_identical(rplatypus:::agreed_task(data, models), "semantic_segmentation")

  # Agreeing is allowed - being explicit is the point of permitting it at all.
  expect_identical(
    rplatypus:::agreed_task(data, models, stated = "semantic_segmentation"),
    "semantic_segmentation"
  )

  # Disagreeing is refused. Stating the task is a way of being explicit, never a way of
  # overriding what `segmentation_data()` and `u_net()` plainly are.
  expect_error(
    rplatypus:::agreed_task(data, models, stated = "object_detection"),
    "disagrees with what this specification is built from"
  )
})

test_that("the task names that were renamed are named back", {
  data <- segmentation_data("train", "valid", colormap = binary_colormap)
  models <- list(u_net("u", input_shape = c(32, 32)))

  expect_error(rplatypus:::agreed_task(data, models, stated = "segmentation"),
               "renamed to \"semantic_segmentation\"")
  expect_error(rplatypus:::agreed_task(data, models, stated = "detection"),
               "renamed to \"object_detection\"")

  # This read `stated = "classification"` until the pin moved to `0.8.0a49`, and then it
  # was a refusal that could no longer fire: the example of an unknown task had become a
  # known one. §4's fixture that stops being able to fail, and the only safe example is a
  # value nothing could ever name - every plausible one is on a milestone somewhere.
  expect_error(rplatypus:::agreed_task(data, models, stated = "not_a_task_anybody_has"),
               "must be one of")

  # And the positive half, which is what makes the line above a change rather than a
  # deletion: `classification` is now known, so it is refused for disagreeing with the
  # constructors instead of for being a name nobody has heard of.
  expect_error(rplatypus:::agreed_task(data, models, stated = "classification"),
               "disagrees")
})

test_that("detection can divide one folder, which split_dataset cannot do for it", {
  # `split_dataset()` writes a `masks` column, so it was never usable here - detection had
  # no way to split one folder at all. This divides the samples rather than writing CSVs,
  # so the column name never arises.
  skip_if_no_split_block()

  data <- detection_data("t", classes = c("RBC", "WBC"),
                         split = list(fractions = c(0.8, 0.2), group_by = NULL))
  expect_true("group_by" %in% names(data$split))
  expect_silent(invisible(platypus_spec(
    data = data, models = list(yolo3("y")), check_paths = FALSE
  )))
})

test_that("the refusal for a platypus_split points at what does work", {
  split <- structure(list(train_path = "a", validation_path = "b", test_path = NULL),
                     class = "platypus_split")
  expect_error(detection_data(split, classes = "a"), "Use `split` instead")
})

# --- box_loss ----------------------------------------------------------------------------

test_that("box_loss is omitted when unset, so an older engine is unaffected", {
  model <- yolo3("d", input_shape = c(416, 416))
  expect_false("box_loss" %in% names(model))

  model <- yolo3("d", input_shape = c(416, 416), box_loss = "giou")
  expect_identical(model$box_loss, "giou")
})

test_that("a box_loss that is not one of the two is refused here, not across the bridge", {
  expect_error(yolo3("d", input_shape = c(416, 416), box_loss = "ciou"),
               '`box_loss` is "offsets" or "giou"')
  expect_error(yolo3("d", input_shape = c(416, 416), box_loss = c("giou", "offsets")),
               '`box_loss` is "offsets" or "giou"')
})

test_that("the refusal says what giou is for, since the name invites choosing it", {
  # A message that only lists the two spellings leaves the reader to guess which they want,
  # and the measured answer is counter-intuitive: `giou` scores lower on the overlap it is
  # supposed to improve.
  expect_error(yolo3("d", input_shape = c(416, 416), box_loss = "iou"),
               "readable")
})

test_that("the engine accepts both names and refuses a third", {
  skip_if_no_box_loss()
  for (mode in c("offsets", "giou")) {
    spec <- platypus_spec(
      data = detection_data("a", "b", classes = c("x", "y")),
      models = list(yolo3("d", input_shape = c(416, 416), box_loss = mode)),
      check_paths = FALSE
    )
    expect_identical(as.list(spec)$models[[1]]$box_loss, mode)
  }
})

# --- detection_crops ---------------------------------------------------------------------

test_that("detection_crops refuses anything but a detection fit, and says what to use", {
  expect_error(detection_crops(list()), "must come from `platypus_fit\\(\\)`")
})

test_that("a stretch has to be asked for by name", {
  skip_if_no_crops()
  # Checked before the bridge: `fit` is one word and a typo in it should fail at the call,
  # not inside Python with a traceback about a keyword argument.
  fake <- structure(list(task = "object_detection", models = "d", engine = NULL),
                    class = "platypus_fit")
  expect_error(detection_crops(fake, fit = "squash"), '"letterbox" or "stretch"')
  expect_error(detection_crops(fake, size = c(1, 2, 3)), "c\\(height, width\\)")
})

test_that("every detection comes back as an array cut from its own image", {
  skip_if_no_crops()
  fit <- tiny_detection_fit()
  found <- detection_crops(fit, split = "validation", score_threshold = 0)

  expect_gt(length(found), 0)
  expect_true(all(vapply(found, function(r) is.character(r$key), logical(1))))
  expect_equal(length(unique(vapply(found, `[[`, character(1), "key"))), length(found))

  cut <- unlist(lapply(found, `[[`, "crops"), recursive = FALSE)
  expect_gt(length(cut), 0)
  # Asserted over the whole set rather than one `expect_` per crop: at this threshold there
  # are hundreds, and a loop would report the same single claim hundreds of times and bury
  # the counts that mean something.
  shapes <- vapply(cut, function(c) length(dim(c)) == 3L && all(dim(c)[1:2] > 0),
                   logical(1))
  expect_true(all(shapes))                # height x width x channels, as R wants it
})

test_that("the columns of one record stay aligned, and dropped is reported", {
  skip_if_no_crops()
  fit <- tiny_detection_fit()
  records <- detection_crops(fit, split = "validation", score_threshold = 0)
  aligned <- vapply(records, function(r) {
    n <- length(r$crops)
    nrow(r$boxes) == n && length(r$scores) == n &&
      length(r$labels) == n && length(r$names) == n && is.numeric(r$dropped)
  }, logical(1))
  expect_true(all(aligned))
})

test_that("labels arrive 1-based, as everywhere else on this side", {
  skip_if_no_crops()
  fit <- tiny_detection_fit()
  labels <- unlist(lapply(detection_crops(fit, split = "validation", score_threshold = 0),
                          `[[`, "labels"))
  expect_gt(length(labels), 0)
  expect_gte(min(labels), 1)
})

test_that("size brings every crop to one shape, which is what a classifier needs", {
  skip_if_no_crops()
  fit <- tiny_detection_fit()
  found <- detection_crops(fit, split = "validation", score_threshold = 0,
                           size = c(24, 24))
  cut <- unlist(lapply(found, `[[`, "crops"), recursive = FALSE)
  expect_gt(length(cut), 0)
  expect_true(all(vapply(cut, function(c) identical(dim(c)[1:2], c(24L, 24L)),
                         logical(1))))
  expect_equal(length(unique(lapply(cut, dim))), 1L)   # one shape, so one batch
})

test_that("`at` is refused for a detection fit rather than ignored", {
  # Boxes are in the source image's coordinates already, so there is no grid to choose.
  # An argument silently accepted and dropped is the shape this package keeps refusing.
  #
  # No engine: the refusal is R's own and happens before the bridge, so this runs on a
  # machine with no Python - which is also the only way to be sure it is R's refusal and
  # not the engine's.
  fit <- structure(
    list(task = "object_detection", models = "detector", engine = NULL),
    class = "platypus_fit"
  )
  expect_error(evaluate(fit, at = "source"), "`at` is for segmentation")
})
