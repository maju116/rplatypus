# The ecosystem layer works on ordinary arrays, so almost all of this runs without Python.

square <- function(size = 8) {
  mask <- matrix(1L, size, size)
  inner <- seq(max(1L, size %/% 4L), min(size, size - size %/% 4L))
  mask[inner, inner] <- 2L
  mask
}

test_that("a mask is painted with its colormap", {
  coloured <- classes_to_colours(square(), binary_colormap)
  expect_identical(dim(coloured), c(8L, 8L, 3L))
  expect_identical(coloured[1, 1, ], c(0L, 0L, 0L))
  expect_identical(coloured[4, 4, ], c(255L, 255L, 255L))
})

test_that("a class the colormap does not define is refused, and says so", {
  # Counting from 1 is the convention here, and getting it wrong should not produce a
  # picture that looks plausible.
  expect_error(classes_to_colours(matrix(c(1L, 5L), 1), binary_colormap),
               "colormap defines 2 classes")
  expect_error(classes_to_colours(matrix(c(0L, 1L), 1), binary_colormap),
               "counted from 1")
})

test_that("colours and classes are exact inverses", {
  mask <- square()
  back <- colours_to_classes(classes_to_colours(mask, binary_colormap), binary_colormap)
  expect_identical(back$classes, mask)
  expect_identical(back$coverage, 1)
})

test_that("a colormap that does not describe the data shows up as coverage", {
  # The quietest way to train on nothing: every pixel falls through to background and the
  # run looks normal all the way to a model that learned the empty mask.
  coloured <- classes_to_colours(square(), binary_colormap)
  wrong <- colours_to_classes(coloured, list(c(1L, 2L, 3L), c(4L, 5L, 6L)))
  expect_identical(wrong$coverage, 0)
  expect_true(all(wrong$classes == 1L))
})

test_that("an overlay tints the classes and leaves the background alone", {
  image <- array(100, dim = c(8, 8, 3))
  blended <- overlay_mask(image, square(), binary_colormap, alpha = 0.5)
  expect_identical(dim(blended), c(8L, 8L, 3L))
  expect_identical(blended[1, 1, 1], 100L)       # background, untouched
  expect_gt(blended[4, 4, 1], 100L)              # foreground, lightened
})

test_that("a mask of the wrong size is caught rather than recycled", {
  expect_error(overlay_mask(array(0, c(8, 8, 3)), square(4), binary_colormap),
               "8x8 but mask is 4x4")
})

test_that("agreement separates found, missed and invented", {
  # A single overlap score cannot say which of the three you have, and for most clinical
  # questions they cost different things.
  truth <- square()
  prediction <- matrix(1L, 8, 8)
  prediction[3:6, 5:8] <- 2L                      # shifted right: some of each
  image <- array(0, dim = c(8, 8, 3))
  blended <- overlay_agreement(image, prediction, truth)

  expect_identical(dim(blended), c(8L, 8L, 3L))
  expect_gt(blended[4, 5, 2], 0L)                 # hit, green
  expect_gt(blended[4, 3, 1], 0L)                 # missed, red
  expect_gt(blended[4, 8, 1], 0L)                 # invented, yellow
  expect_identical(blended[1, 1, ], c(0L, 0L, 0L))
})

test_that("greyscale and RGBA images are both accepted", {
  mask <- square()
  expect_identical(dim(overlay_mask(matrix(0.5, 8, 8), mask, binary_colormap)),
                   c(8L, 8L, 3L))
  expect_identical(dim(overlay_mask(array(0.5, c(8, 8, 4)), mask, binary_colormap)),
                   c(8L, 8L, 3L))
})

test_that("images in 0-1 and in 0-255 both work", {
  mask <- square()
  expect_lte(max(overlay_mask(array(1, c(8, 8, 3)), mask, binary_colormap)), 255L)
  expect_lte(max(overlay_mask(array(255, c(8, 8, 3)), mask, binary_colormap)), 255L)
})

test_that("several masks of one image become one", {
  # One file per nucleus is how the Data Science Bowl stores its labels, and it is not
  # unusual.
  a <- matrix(1L, 4, 4)
  a[1:2, ] <- 2L
  b <- matrix(1L, 4, 4)
  b[4, ] <- 2L
  united <- unite_masks(list(a, b))
  expect_identical(united[1, 1], 2L)
  expect_identical(united[4, 1], 2L)
  expect_identical(united[3, 1], 1L)
})

test_that("masks of different sizes are refused rather than silently cropped", {
  expect_error(unite_masks(list(matrix(1L, 4, 4), matrix(1L, 8, 8))), "same size")
  expect_error(unite_masks(list()), "empty")
})

test_that("coverage answers how much of the picture each class is", {
  # Worth knowing before training rather than after: a foreground of one percent is a
  # problem the loss has to be chosen for.
  coverage <- mask_coverage(square(), labels = c("background", "nucleus"))
  expect_identical(coverage$label, c("background", "nucleus"))
  expect_identical(sum(coverage$pixels), 64L)
  expect_equal(sum(coverage$fraction), 1)
  expect_equal(coverage$fraction[[2]], sum(square() == 2L) / 64)
})

test_that("the supplied colormaps line up with their labels", {
  expect_length(binary_colormap, length(binary_labels))
  expect_length(voc_colormap, length(voc_labels))
  expect_identical(voc_labels[[1]], "background")
  expect_identical(voc_colormap[[1]], c(0L, 0L, 0L))
  # Every colour distinct, or two classes could not be told apart on disk.
  expect_length(unique(voc_colormap), length(voc_colormap))
})

test_that("masks are written as files that read back identically", {
  # A prediction is only half useful while it is an array in a session. The round trip is
  # the property that matters: what comes back out has to be what went in.
  skip_if_no_engine()
  out <- withr::local_tempdir()
  masks <- array(1L, dim = c(3, 16, 16))
  masks[, 4:12, 4:12] <- 2L

  paths <- save_masks(masks, out, binary_colormap)
  expect_length(paths, 3L)
  expect_true(all(file.exists(paths)))
  expect_identical(read_masks(paths, binary_colormap), masks)
})

test_that("a suffix keeps two models from overwriting each other", {
  skip_if_no_engine()
  out <- withr::local_tempdir()
  mask <- array(1L, dim = c(1, 8, 8))
  save_masks(mask, out, binary_colormap, suffix = "_unet")
  save_masks(mask, out, binary_colormap, suffix = "_linknet")
  expect_length(list.files(out), 2L)
})

test_that("names can come from the images the masks belong to", {
  skip_if_no_engine()
  out <- withr::local_tempdir()
  mask <- array(1L, dim = c(2, 8, 8))
  paths <- save_masks(mask, out, binary_colormap,
                      names = c("a/scan_01.png", "b/scan_02.tif"), suffix = "_m")
  expect_identical(basename(paths), c("scan_01_m.png", "scan_02_m.png"))
})

test_that("probabilities are reduced to classes rather than refused", {
  skip_if_no_engine()
  out <- withr::local_tempdir()
  probabilities <- array(0, dim = c(2, 8, 8, 2))
  probabilities[, , , 1] <- 0.3
  probabilities[, , , 2] <- 0.7
  paths <- save_masks(probabilities, out, binary_colormap)
  expect_identical(unique(as.vector(read_masks(paths, binary_colormap))), 2L)
})

test_that("a mismatched number of names is caught before anything is written", {
  skip_if_no_engine()
  out <- withr::local_tempdir()
  expect_error(
    save_masks(array(1L, dim = c(3, 8, 8)), out, binary_colormap, names = c("a", "b")),
    "2 entries but there are 3"
  )
  expect_length(list.files(out), 0L)
})

test_that("the output directory is created rather than demanded", {
  skip_if_no_engine()
  out <- file.path(withr::local_tempdir(), "does", "not", "exist")
  paths <- save_masks(array(1L, dim = c(1, 8, 8)), out, binary_colormap)
  expect_true(file.exists(paths))
})


# --- overlapping classes cannot be one colour -------------------------------------------
#
# `regions` gives a channel per named class and a sigmoid per channel, so two channels can
# both be hot at one pixel - that is the point of the field. A colour map cannot hold it:
# one pixel gets one colour, so writing such a prediction as a picture means choosing one
# of the classes the pixel is in and leaving nothing in the file to say that happened.
#
# The detection is read off the array rather than off the specification, which is the same
# test the engine's `onehot_to_colours` applies - so both halves refuse the same arrays, and
# a caller holding only a prediction can answer the question. A softmax output never trips
# it: its channels sum to one, so at most one can reach half. `#152`.

overlapping_prediction <- function(images = 1L, size = 8L) {
  # Built the way the data stores it - a label map of {0, 1, 2, 4} turned into unions -
  # rather than by setting channels directly, so the overlap is a consequence rather than
  # something the test asserted into existence.
  labels <- array(0L, dim = c(images, size, size))
  labels[, 1, ] <- 2L
  labels[, 2, ] <- 1L
  labels[, 3, ] <- 4L
  channels <- lapply(list(c(1, 2, 4), c(1, 4), 4), function(of) {
    as.numeric(labels %in% of)
  })
  array(unlist(channels), dim = c(dim(labels), 3L))
}

test_that("a pixel in several classes is counted rather than guessed at", {
  expect_identical(rplatypus:::overlapping_channels(overlapping_prediction()), 3L)
  # The control, and it is the one that matters: a softmax prediction must not be read as
  # overlapping, or `save_masks()` would refuse every ordinary run.
  softmax <- array(0, dim = c(1, 8, 8, 3))
  softmax[, , , 1] <- 0.6
  softmax[, , , 2] <- 0.3
  softmax[, , , 3] <- 0.1
  expect_identical(rplatypus:::overlapping_channels(softmax), 1L)
})

test_that("save_masks() refuses an overlapping prediction and names where to go", {
  out <- withr::local_tempdir()
  expect_error(
    save_masks(overlapping_prediction(), out, binary_colormap),
    "3 classes at once"
  )
  expect_error(
    save_masks(overlapping_prediction(), out, binary_colormap),
    "save_class_masks"
  )
  # Refused before anything is written, not after some of it: a directory holding two of
  # three classes is worse than an error, because it looks like a result.
  expect_length(list.files(out), 0L)
})

test_that("save_class_masks() writes one file per class, named after the class", {
  skip_if_no_engine()
  out <- withr::local_tempdir()
  paths <- save_class_masks(
    overlapping_prediction(),
    out,
    classes = c("whole tumour", "tumour core", "enhancing")
  )
  expect_identical(
    basename(paths),
    c("mask_0001_whole_tumour.png", "mask_0001_tumour_core.png", "mask_0001_enhancing.png")
  )
  # Read back rather than trusting the returned paths, and read back the class each file is
  # supposed to hold: a writer that put the same channel in all three would pass a test
  # that only counted files.
  written <- lapply(paths, function(path) read_masks(path, binary_colormap))
  names(written) <- basename(paths)
  expect_true(all(written[["mask_0001_whole_tumour.png"]][1, 2, ] == 2L))
  expect_true(all(written[["mask_0001_enhancing.png"]][1, 2, ] == 1L))
  # Row 3 is the pixel value a colour map could not have held: in all three at once.
  expect_true(all(vapply(written, function(mask) all(mask[1, 3, ] == 2L), logical(1))))
})

test_that("save_class_masks() takes file names per image and a suffix per model", {
  skip_if_no_engine()
  out <- withr::local_tempdir()
  paths <- save_class_masks(
    overlapping_prediction(images = 2L), out,
    classes = c("a", "b", "c"),
    names = c("x/scan_01.png", "y/scan_02.tif"), suffix = "_unet"
  )
  expect_identical(basename(paths)[c(1, 4)],
                   c("scan_01_unet_a.png", "scan_02_unet_a.png"))
})

test_that("save_class_masks() refuses a class name count that does not match", {
  skip_if_no_engine()
  out <- withr::local_tempdir()
  expect_error(
    save_class_masks(overlapping_prediction(), out, classes = c("a", "b")),
    "3 channels and 2 class names"
  )
  expect_length(list.files(out), 0L)
})

test_that("save_class_masks() refuses two class names that become one file", {
  skip_if_no_engine()
  out <- withr::local_tempdir()
  # The quiet failure this guards: one file would hold the second class, the first would be
  # silently gone, and the number of returned paths would still be three.
  expect_error(
    save_class_masks(overlapping_prediction(), out, classes = c("core 1", "core_1", "x")),
    "same filename"
  )
  expect_length(list.files(out), 0L)
})

test_that("save_class_masks() refuses class indices where a value can prove it", {
  out <- withr::local_tempdir()
  # Provable: no probability exceeds 1. `predict(type = "class")` returns 1-based indices,
  # so a two-class mask holds a 2.
  expect_error(
    save_class_masks(array(2L, dim = c(1, 8, 8, 2)), out, classes = c("a", "b")),
    "class indices rather than channel probabilities"
  )
  expect_length(list.files(out), 0L)
})

test_that("the case a rank cannot prove is stated rather than detected", {
  skip_if_no_engine()
  out <- withr::local_tempdir()
  # A stack of two all-background class masks has the same rank and the same values as one
  # image with eight channels, so this is read as the latter - exactly as `save_masks()`
  # cannot tell a stack of volumes from a stack of images. What catches it is the count.
  expect_error(
    save_class_masks(array(1L, dim = c(2, 8, 8)), out, classes = c("a", "b")),
    "8 channels and 2 class names"
  )
  expect_length(list.files(out), 0L)
})

test_that("save_class_masks() counts its file names against the images", {
  out <- withr::local_tempdir()
  expect_error(
    save_class_masks(overlapping_prediction(images = 3L), out,
                     classes = c("a", "b", "c"), names = c("one", "two")),
    "2 entries but there are 3"
  )
  expect_length(list.files(out), 0L)
})


test_that("mask_coverage reports a class with no pixels, including the last one", {
  # `maju116/rplatypus#255`. `tabulate()` sizes its table by the largest value PRESENT, so a
  # declared class above it had no row - and the help page's own example says a class with 0
  # pixels is the thing to look for. The highest-numbered class is the usual position of a
  # rare foreground, so the row that disappeared was the one worth reading.
  labels <- c("bg", "liver", "tumour")

  no_tumour <- mask_coverage(matrix(c(1, 1, 2, 2), 2), labels = labels)
  expect_identical(nrow(no_tumour), 3L)
  expect_identical(no_tumour$label[3], "tumour")
  expect_identical(no_tumour$pixels[3], 0L)
  expect_identical(no_tumour$fraction[3], 0)

  # The control: a missing MIDDLE class was always reported, so the assertion above is about
  # the last row rather than about counting having started to work at all.
  no_liver <- mask_coverage(matrix(c(1, 1, 3, 3), 2), labels = labels)
  expect_identical(nrow(no_liver), 3L)
  expect_identical(no_liver$pixels, c(2L, 0L, 2L))

  # And the fractions still sum to the share of the mask that is labelled, which is what
  # would break if the table were widened by padding rather than by counting.
  expect_equal(sum(no_tumour$fraction), 1)
})


test_that("mask_coverage takes the class count from n_class when there are no labels", {
  # Without either, the largest value present is all there is to go on - which is the old
  # behaviour and is correct whenever every class occurs.
  by_number <- mask_coverage(matrix(c(1, 1, 2, 2), 2), n_class = 4)
  expect_identical(nrow(by_number), 4L)
  expect_identical(by_number$pixels, c(2L, 2L, 0L, 0L))
  expect_identical(by_number$label, paste("class", 1:4))

  # The control: nothing declared, so the answer is what the mask holds.
  expect_identical(nrow(mask_coverage(matrix(c(1, 1, 2, 2), 2))), 2L)
})
