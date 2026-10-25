# `predict(space = "source")` returns a list, and a list is only useful if you know which
# entry is which. `maju116/rplatypus#223`.
#
# The whole difficulty of testing this is that **names can be present and wrong**. A check
# for `!is.null(names(x))` passes on names attached in the wrong order, which is the failure
# that matters: a caller joins the masks to a table of pixel sizes, the join succeeds, and
# every measurement afterwards belongs to a different picture. So the fixture gives each case
# a DIFFERENT IMAGE SIZE, and source space returns each mask on its own grid - which makes
# the shape of an entry a fingerprint of the case it came from, independent of anything the
# model learned. A permutation of the names then puts a 24-pixel mask under the 40-pixel
# name, and the assertion below fails.
#
# The control is the fixture itself: if the sizes were not distinct, the fingerprint would be
# the same for every case and this test would pass on any permutation at all. That is checked
# rather than assumed.

sized_dataset <- function(sizes) {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  for (i in seq_along(sizes)) {
    size <- sizes[[i]]
    sample <- file.path(root, sprintf("sample_%02d", i - 1L))
    dir.create(file.path(sample, "images"), recursive = TRUE, showWarnings = FALSE)
    dir.create(file.path(sample, "masks"), recursive = TRUE, showWarnings = FALSE)
    reticulate::py_run_string(sprintf("
import numpy as np, pathlib
from PIL import Image
sample = pathlib.Path(%s)
size = %d
rng = np.random.default_rng(size)
mask = np.zeros((size, size), np.uint8)
mask[4:size - 4, 4:size - 4] = 255
image = np.clip(mask.astype(np.float32) * 0.7 + rng.random((size, size)) * 70, 0, 255)
Image.fromarray(image.astype(np.uint8)).convert('RGB').save(sample / 'images' / 'a.png')
Image.fromarray(mask).convert('RGB').save(sample / 'masks' / 'a.png')
", shQuote(sample), size))
  }
  root
}

fitted_on <- function(root) {
  spec <- platypus_spec(
    data = segmentation_data(root, root, colormap = binary_colormap),
    models = list(u_net("u", input_shape = c(16, 16), blocks = 2, filters = 4,
                        epochs = 1, batch_size = 1))
  )
  platypus_fit(spec, num_workers = 0)
}

test_that("a source-space prediction is named by case, and the names are the right way round", {
  skip_if_no_source_space()
  sizes <- c(24L, 32L, 40L)
  # The control first, because every assertion below is worthless without it.
  expect_length(unique(sizes), length(sizes))

  root <- sized_dataset(sizes)
  masks <- predict(fitted_on(root), split = "validation", space = "source")

  expect_true(is.list(masks))
  expect_length(masks, length(sizes))
  expect_false(is.null(names(masks)))
  expect_setequal(names(masks), sprintf("sample_%02d", seq_along(sizes) - 1L))

  # The pairing itself: each entry is on its own case's grid.
  for (i in seq_along(sizes)) {
    key <- sprintf("sample_%02d", i - 1L)
    expect_equal(dim(masks[[key]])[1:2], c(sizes[[i]], sizes[[i]]),
                 info = paste0(key, " carries a mask of another case's shape"))
  }

  # And the negative half, so that "named" is not satisfied by a constant: the three shapes
  # differ, so a shuffled set of names could not have passed the loop above.
  expect_length(unique(vapply(masks, function(m) dim(m)[[1]], integer(1))), length(sizes))
})

test_that("a model-space prediction is one array and so has nothing to name", {
  # The asymmetry is deliberate and is between the two SPACES rather than between two tasks:
  # model space stacks every case into one array, where there is no per-case entry to label.
  # Asserted so that a later change making both branches alike has to be a decision.
  skip_if_no_source_space()
  root <- sized_dataset(c(24L, 32L, 40L))
  stacked <- predict(fitted_on(root), split = "validation")

  expect_true(is.array(stacked))
  expect_null(names(stacked))
  expect_equal(dim(stacked)[[1]], 3L)
})
