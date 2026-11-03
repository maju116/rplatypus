fake_fit <- function(models = "m", epochs = 3) {
  history <- do.call(rbind, lapply(models, function(model) {
    data.frame(model = model, epoch = seq_len(epochs),
               train_loss = seq(0.5, 0.3, length.out = epochs),
               val_loss = seq(0.45, 0.28, length.out = epochs),
               train_dice = seq(0.4, 0.7, length.out = epochs),
               val_dice = seq(0.5, 0.75, length.out = epochs),
               seconds = 1, learning_rate = 0.001, stringsAsFactors = FALSE)
  }))
  structure(list(history = history, models = models), class = "platypus_fit")
}

test_that("a fit plots one panel per quantity and one line per model", {
  skip_if_not_installed("ggplot2")
  built <- ggplot2::ggplot_build(plot(fake_fit(c("a", "b"))))
  expect_setequal(unique(built$plot$data$panel), c("loss", "dice"))
  expect_setequal(unique(built$plot$data$model), c("a", "b"))
})

test_that("train and validation share a panel but not a line", {
  # The comparison worth seeing is between them, which needs them on the same axes.
  skip_if_not_installed("ggplot2")
  data <- ggplot2::ggplot_build(plot(fake_fit()))$plot$data
  expect_setequal(unique(data$split), c("train", "validation"))
  expect_identical(unique(data$panel[data$quantity %in% c("train_loss", "val_loss")]),
                   "loss")
})

test_that("the epoch axis is counted in whole numbers", {
  # The default breaks offer 1.5 and 2.5 on a short run.
  skip_if_not_installed("ggplot2")
  built <- ggplot2::ggplot_build(plot(fake_fit(epochs = 3)))
  breaks <- built$layout$panel_params[[1]]$x$breaks
  breaks <- breaks[!is.na(breaks)]
  expect_true(all(breaks == as.integer(breaks)))
})

test_that("a fit with no history says so rather than drawing nothing", {
  empty <- structure(list(history = data.frame(), models = "m"), class = "platypus_fit")
  expect_error(plot(empty), "no history")
})

test_that("panels appear only for what was supplied", {
  skip_if_not_installed("ggplot2")
  images <- array(runif(2 * 8 * 8 * 3) * 255, dim = c(2, 8, 8, 3))
  mask <- array(1L, dim = c(2, 8, 8))
  mask[, 3:6, 3:6] <- 2L

  labels <- function(plot) {
    ggplot2::ggplot_build(plot)$layout$panel_params[[1]]$x$get_labels()
  }
  expect_identical(labels(plot_masks(images, which = 1)), "image")
  expect_identical(labels(plot_masks(images, prediction = mask, which = 1)),
                   c("image", "prediction"))
  expect_identical(
    labels(plot_masks(images, prediction = mask, truth = mask, which = 1)),
    c("image", "truth", "prediction", "agreement")
  )
})

test_that("a single image is accepted as readily as a stack", {
  skip_if_not_installed("ggplot2")
  expect_s3_class(plot_masks(array(0.5, dim = c(8, 8, 3)), which = 1), "ggplot")
})

test_that("panels are laid out as rows of samples and columns of views", {
  images <- array(0, dim = c(3, 8, 8, 3))
  mask <- array(1L, dim = c(3, 8, 8))
  rows <- lapply(1:3, function(i) list(array(0, c(8, 8, 3)), array(0, c(8, 8, 3))))
  montage <- rplatypus:::bind_panels(rows)
  expect_identical(dim(montage), c(24L, 16L, 3L))
})

test_that("reading images goes through the engine's own pipeline", {
  # So that what is plotted is what the model was given. A picture drawn from a
  # differently resized copy shows disagreements that may be nothing but the resizing.
  skip_if_no_engine()
  root <- tiny_dataset(n = 3, size = 32)
  paths <- list.files(root, pattern = "a[.]png$", recursive = TRUE, full.names = TRUE)
  images <- read_images(grep("images", paths, value = TRUE), size = c(16, 16))
  expect_identical(dim(images), c(3L, 16L, 16L, 3L))
  expect_lte(max(images), 255)
})

test_that("masks are read at nearest neighbour, whatever the caller does", {
  skip_if_no_engine()
  root <- tiny_dataset(n = 2, size = 32)
  paths <- grep("masks", list.files(root, pattern = "a[.]png$", recursive = TRUE,
                                    full.names = TRUE), value = TRUE)
  classes <- read_masks(paths, binary_colormap, size = c(24, 24))
  expect_identical(dim(classes), c(2L, 24L, 24L))
  # Interpolation would invent values between the two classes; nearest cannot.
  expect_true(all(classes %in% c(1L, 2L)))
})

test_that("asking for a label map without nearest warns, because a volume is rescaled", {
  # `maju116/rplatypus#266`. The engine documents `label_map` as ignored for volume
  # formats - a NIfTI never went through an 8-bit conversion - and `nearest` is what says
  # "these numbers are classes" on that route. So the combination below is always a
  # mistake, and `@return` promised the file's own values without saying so.
  #
  # Measured through the shim on a NIfTI holding 0, 1, 2 and 7: with `nearest = FALSE` it
  # came back as 0, 0.1429, 0.2857, 1.0 - the classes divided by 7 - and with
  # `nearest = TRUE` it came back as the file's own values.
  skip_if_no_engine()

  path <- withr::local_tempfile(fileext = ".png")
  png::writePNG(matrix(c(0, 1, 0, 1) / 255, nrow = 2), path)

  expect_warning(
    read_images(path, channels = 1, label_map = TRUE),
    "nearest = TRUE"
  )

  # The control: with both flags there is nothing to warn about, and the package's own
  # route - `read_masks()` - passes both, which is why nothing in the suite warned before.
  expect_silent(read_images(path, channels = 1, nearest = TRUE, label_map = TRUE))

  # And the other control: an ordinary image asks for neither and is silent.
  expect_silent(read_images(path, channels = 1))
})
