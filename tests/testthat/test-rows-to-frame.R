# `rows_to_frame` is the one function every table from the engine passes through, and
# until `rplatypus#307` it kept the first element of a cell that held several and said
# nothing. The defect was latent - every row the engine builds today is scalars, and the
# catalogue listings are flattened on the engine's side of the bridge - which is exactly
# why it needed a test: a latent truncation is found by the table it eventually breaks.

test_that("a cell holding several values is refused by column and by row", {
  rows <- list(
    list(a = 1, b = 2),
    list(a = 2, b = c(3, 4))
  )

  # By column AND by row, because a table with twenty columns and two hundred rows is not
  # searchable from "a cell had two values". Both are read out of the data rather than
  # written into the message, which is what §4 asks of a number inside a refusal.
  expect_error(rplatypus:::rows_to_frame(rows), "`b`")
  expect_error(rplatypus:::rows_to_frame(rows), "2 values in row 2")

  # And the first value is NOT what comes back. This is the assertion that fails on the
  # old body: it returned a frame whose `b` column read 2 and 3, with the 4 gone.
  expect_error(rplatypus:::rows_to_frame(rows))
})

test_that("the ordinary scalar row is unchanged, which is the control", {
  # Every one of the ten callers passes rows of this shape, so a refusal that fired here
  # would be a refusal nobody could work around.
  rows <- list(
    list(case = "p01", dice = 0.91, n = 3L),
    list(case = "p02", dice = 0.88, n = 4L)
  )
  frame <- rplatypus:::rows_to_frame(rows)
  expect_identical(frame$case, c("p01", "p02"))
  expect_identical(frame$dice, c(0.91, 0.88))
  expect_identical(frame$n, c(3L, 4L))
})

test_that("a missing cell is NA rather than a shifted column, in both its shapes", {
  # NULL is what the engine sends for "no answer" - `mean_matched_iou` on an image where
  # nothing matched - and the old body handled a bare NULL correctly.
  bare <- rplatypus:::rows_to_frame(list(
    list(key = "a", iou = 0.83),
    list(key = "b", iou = NULL)
  ))
  expect_true(is.na(bare$iou[2]))
  expect_identical(nrow(bare), 2L)

  # A NULL INSIDE a list is the shape the old body got wrong, and it is the second half of
  # #307 rather than the finding. Its length is one, so the length test passed; the first
  # element was NULL; and assembling the column dropped it, leaving that column one short.
  # Measured on the old body, with iou 0.83 for case a and a wrapped NULL for case b: no
  # error and no NA, but 0.83 TWICE - the frame recycles, so case b reports case a's
  # number. That is a figure attributed to the wrong case, which is quieter than a
  # truncated cell. Flattening before the length is taken makes the two shapes one case.
  wrapped <- rplatypus:::rows_to_frame(list(
    list(key = "a", iou = 0.83),
    list(key = "b", iou = list(NULL))
  ))
  expect_identical(nrow(wrapped), 2L)
  expect_true(is.na(wrapped$iou[2]))
  expect_identical(wrapped$key, c("a", "b"))
})

test_that("a cell holding a list of one vector is refused too, not widened", {
  # The length taken before flattening cannot see this one: `length(list(c(3, 4)))` is 1.
  # Unflattened it would have put two values in one cell and widened the column.
  rows <- list(
    list(a = 1, b = 2),
    list(a = 2, b = list(c(3, 4)))
  )
  expect_error(rplatypus:::rows_to_frame(rows), "`b`")
})

test_that("a list of one value is still one value, which is how every engine row arrives", {
  # reticulate hands a Python scalar across as a length-1 list often enough that this is
  # the ordinary case rather than an edge: a refusal here would refuse everything.
  frame <- rplatypus:::rows_to_frame(list(
    list(a = list(1), b = list("x")),
    list(a = list(2), b = list("y"))
  ))
  expect_identical(frame$a, c(1, 2))
  expect_identical(frame$b, c("x", "y"))
})

test_that("the catalogue listings still arrive flattened, which is where that rule lives", {
  # The positive control for the refusal NOT firing in production: all six listings carry
  # a multi-element field on the engine's side - `arguments`, and `chooses` on the tasks -
  # and the shim joins each with ", " before R sees it. If that flattening were ever
  # removed, these calls would now refuse by name instead of silently keeping one argument.
  skip_if_no_engine()

  for (listing in list(available_tasks, available_models, available_losses,
                       available_metrics, available_optimizers, available_callbacks)) {
    frame <- listing()
    expect_s3_class(frame, "data.frame")
    expect_gt(nrow(frame), 0)
  }

  # And the flattening is visible rather than assumed: at least one listing really does
  # carry a field with several arguments joined by ", ", so these calls are exercising the
  # route this refusal would otherwise have caught.
  arguments <- available_losses()$arguments
  expect_true(any(grepl(", ", arguments, fixed = TRUE)))
})

test_that("the invariant is one value per cell at ANY nesting, not one unwrap", {
  # This is the test a surviving mutation asked for. Unwrapping a length-1 list BY HAND and
  # then taking the length is indistinguishable from flattening at every depth the engine
  # produces - all seven assertions above pass either way - because one unwrap is enough
  # for `list(c(3, 4))` and for `list(NULL)`.
  #
  # It separates at the depth where one unwrap is not enough. `list(list(list(3, 4)))`
  # unwraps once to `list(list(3, 4))`, whose length is 1, so a guard reading the length
  # there sees one value - and the `unlist()` that assembles the column then puts two in
  # one cell. Measured: 2 against 1. THE FIRST DRAFT OF THIS TEST WAS ONE LEVEL SHALLOWER
  # and the mutation survived it, which is the only reason the depth is written down.
  #
  # So what is pinned here is the promise rather than the spelling: a cell contributes
  # exactly one value to the frame, at any nesting, or the frame is refused.
  rows <- list(
    list(a = 1, b = 2),
    list(a = 2, b = list(list(list(3, 4))))
  )
  expect_error(rplatypus:::rows_to_frame(rows), "`b`")
})
