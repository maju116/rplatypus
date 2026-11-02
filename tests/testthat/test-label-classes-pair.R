# The pair for `maju116/rplatypus#263`, found while fixing `#262` in the function it runs
# through.
#
# **Two implementations of one rule, in two languages.** `read_masks(labels = )` turns a
# label map into class indices with R's own `label_classes()`, and the engine does the same
# job in `labels_to_classes`. Both compare the file's values with a tolerance of half a
# unit, both send a value no label claims to the first class, and until this file nothing
# compared them - `label_classes()` is referenced in one place and no test in either suite
# mentioned `labels_to_classes`.
#
# The arrays below are the ones where the two could disagree rather than the ones any
# implementation agrees on: the tolerance's own boundary, a value no label claims, a value
# two labels can both claim, and values wider than a byte. The numbering differs on purpose
# - the engine counts channels from 0 and the R surface counts classes from 1 - so the
# comparison adds one rather than pretending they agree about that.

engine_masks <- function() {
  # `pyplatypus.data` rather than `pyplatypus`: `labels_to_classes` is exported from the
  # data module and the top-level package does not re-export it.
  reticulate::import("pyplatypus.data")
}

as_label_map <- function(values) {
  # The shape `label_classes()` is given: whatever `read_images(channels = 1)` returns, so
  # a trailing axis of one. Here it is one mask rather than a stack, which is the shape the
  # engine takes as well.
  array(values, dim = c(dim(values), 1L))
}

label_cases <- list(
  exact = list(values = matrix(c(0, 1, 2, 1), nrow = 2), labels = c(0, 1, 2)),
  unmatched = list(values = matrix(c(0, 1, 9, 2), nrow = 2), labels = c(0, 1, 2)),
  on_the_boundary = list(values = matrix(c(0.5, 1.5, 2, 0), nrow = 2), labels = c(0, 1, 2)),
  two_labels_claim_it = list(values = matrix(c(1, 1.5, 2, 0), nrow = 2), labels = c(1, 2)),
  wider_than_a_byte = list(values = matrix(c(0, 255, 1000, 300), nrow = 2),
                           labels = c(0, 255, 300, 1000)),
  resampled = list(values = matrix(c(0.2, 0.9, 2.1, 1.8), nrow = 2), labels = c(0, 1, 2))
)

test_that("label_classes answers what the engine's labels_to_classes answers", {
  skip_if_no_engine()
  py <- engine_masks()
  answers <- list()

  for (name in names(label_cases)) {
    case <- label_cases[[name]]
    mine <- rplatypus:::label_classes(as_label_map(case$values), case$labels)
    theirs <- py$labels_to_classes(as_label_map(case$values), as.list(case$labels))[[1]]

    # +1 because the engine counts the channel a voxel belongs to from 0 and every class
    # index on the R surface is counted from 1.
    expect_identical(as.vector(mine), as.integer(as.vector(theirs)) + 1L, info = name)
    answers[[name]] <- as.vector(mine)
  }

  # The positive control, because two implementations agreeing on one class everywhere is
  # not agreement: every case above has to name at least two classes, and the six cases
  # have to differ from one another.
  expect_true(all(vapply(answers, function(a) length(unique(a)) >= 2L, logical(1))))
  expect_identical(length(unique(lapply(answers, identity))), length(label_cases))
})

test_that("both halves send a value no label claims to the first class", {
  # The convention, asserted on its own rather than only inside the comparison: a loop that
  # left unmatched voxels at 0 would agree with an engine that did the same, and both would
  # be writing a class index nothing can read.
  skip_if_no_engine()
  py <- engine_masks()
  values <- as_label_map(matrix(c(9, 9, 9, 9), nrow = 2))

  expect_identical(unique(as.vector(rplatypus:::label_classes(values, c(0, 1)))), 1L)
  expect_identical(
    unique(as.integer(as.vector(py$labels_to_classes(values, list(0, 1))[[1]]))),
    0L
  )
})
