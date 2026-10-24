fit_on_patients <- function(..., input_shape = c(32, 32), envir = parent.frame()) {
  # The dataset has to outlive this helper: evaluate_cases() reads the images again after
  # training, so tying the directory to this frame would delete it in between.
  # Defined in helper-engine.R, which testthat sources at run time and lintr cannot see.
  root <- tiny_patient_dataset(  # nolint: object_usage_linter.
    patients = 6, slices = 2, envir = envir
  )
  spec <- platypus_spec(
    data = segmentation_data(root, root, colormap = binary_colormap),
    models = list(u_net("tiny", input_shape = input_shape, blocks = 2, filters = 4,
                        metrics = list(metric_dice(include_background = FALSE)),
                        epochs = 1, batch_size = 2, ...))
  )
  platypus_fit(spec, num_workers = 0)
}

test_that("scores come back one row per case", {
  skip_if_no_splits()
  cases <- evaluate_cases(fit_on_patients())

  expect_s3_class(cases, "platypus_cases")
  expect_equal(nrow(cases), 12)
  expect_true("case" %in% names(cases))
  expect_true(all(cases$dice >= 0 & cases$dice <= 1))
})

test_that("cases are named after the sample, so a bad score can be chased", {
  # A table of scores against 'row 7' is useless: the first thing anyone does with a low
  # score is go and look at the image.
  skip_if_no_splits()
  cases <- evaluate_cases(fit_on_patients())
  expect_match(cases$case[[1]], "^patient\\d+_slice\\d+$")
})

test_that("grouping reports patients instead of slices", {
  skip_if_no_splits()
  cases <- evaluate_cases(fit_on_patients(), group_by = "^(patient\\d+)_")

  expect_equal(nrow(cases), 6)
  expect_true("group" %in% names(cases))
  expect_false("case" %in% names(cases))
})

test_that("summary() gives the distribution and names the worst case", {
  skip_if_no_splits()
  summary_table <- summary(evaluate_cases(fit_on_patients()))

  expect_true(all(c("metric", "n", "mean", "sd", "median", "min", "max") %in%
                    names(summary_table)))
  expect_equal(summary_table$n[[1]], 12)
  expect_true(summary_table$min[[1]] <= summary_table$mean[[1]])
  expect_true(summary_table$mean[[1]] <= summary_table$max[[1]])
  # The column that makes the table actionable rather than decorative.
  expect_true(any(grepl("^worst_", names(summary_table))))
})

test_that("the summary is the engine's, not a second implementation in R", {
  # Means and quantiles are easy enough to write twice, which is the problem: two tables
  # that drift apart are worse than one table. This pins that R is asking the engine.
  skip_if_no_splits()
  cases <- evaluate_cases(fit_on_patients())
  mine <- summary(cases)
  theirs <- rplatypus:::rows_to_frame(rplatypus:::shim()$case_summary(
    lapply(seq_len(nrow(cases)), function(i) as.list(cases[i, , drop = FALSE]))
  )$table)
  expect_equal(mine$mean, theirs$mean)
})

test_that("a tiled model is scored on whole images, not on tiles", {
  # Four tiles per image, but still one row per image - and the score is the image's, since
  # the engine accumulates overlaps rather than averaging tile scores.
  skip_if_no_splits()
  cases <- evaluate_cases(fit_on_patients(splits = c(2, 2)))
  expect_equal(nrow(cases), 12)
})

test_that("asking for a model that was not trained lists the ones that were", {
  skip_if_no_splits()
  expect_error(evaluate_cases(fit_on_patients(), model = "nope"), "no model called")
})

test_that("printing shows the first rows and says how to get the distribution", {
  skip_if_no_splits()
  expect_output(print(evaluate_cases(fit_on_patients())), "scores by case")
  expect_output(print(evaluate_cases(fit_on_patients())), "summary\\(\\)")
})

# --- one prediction at a time ---------------------------------------------------------------
#
# `predict()` returns the whole split, which for a tiled run is the whole split at full
# resolution. The engine grew a streaming form for that (pyplatypus#178, released in
# 0.8.0a5) and R could not reach it until now, which is the gap platypus#126 names.

test_that("cases= returns just those, named, in the order asked for", {
  skip_if_no_splits()
  fit <- fit_on_patients()
  all_cases <- evaluate_cases(fit, split = "validation")$case
  wanted <- rev(all_cases[1:2])

  some <- predict(fit, split = "validation", cases = wanted)

  expect_type(some, "list")
  # The order asked for, not the order the stream served them: a caller naming two cases is
  # comparing them, and `rev()` here is what makes that assertion mean something.
  expect_identical(names(some), wanted)
  expect_length(some, 2L)
})

test_that("a streamed prediction is the same mask predict() returns for it", {
  skip_if_no_splits()
  fit <- fit_on_patients()
  everything <- predict(fit, split = "validation")
  all_cases <- evaluate_cases(fit, split = "validation")$case
  which_one <- 2L

  one <- predict(fit, split = "validation", cases = all_cases[which_one])

  # Element for element. A test that only checked the shape would pass on a stream that
  # served the wrong image, which is the failure worth catching here.
  expect_equal(one[[all_cases[which_one]]], everything[which_one, , ])
})

test_that("each= is called once per case and keeps only what it returns", {
  skip_if_no_splits()
  fit <- fit_on_patients()
  all_cases <- evaluate_cases(fit, split = "validation")$case

  seen <- character()
  sizes <- predict(fit, split = "validation", each = function(case, mask) {
    seen <<- c(seen, case)
    length(mask)
  })

  expect_setequal(seen, all_cases)
  expect_setequal(names(sizes), all_cases)
  expect_true(all(vapply(sizes, is.integer, logical(1))))

  # Returning NULL is how a caller walks a split it cannot hold: the side effect happens
  # and nothing accumulates.
  counted <- 0L
  nothing <- predict(fit, split = "validation", each = function(case, mask) {
    counted <<- counted + 1L
    NULL
  })
  expect_length(nothing, 0L)
  expect_identical(counted, length(all_cases))
})

test_that("a case that is not in the split is an error, not an empty answer", {
  skip_if_no_splits()
  fit <- fit_on_patients()
  # Silently returning nothing is the trap: the caller would draw an empty figure and
  # believe the model had failed.
  expect_error(
    predict(fit, split = "validation", cases = "patient99_slice999"),
    "patient99_slice999"
  )
})

test_that("each= has to be a function", {
  skip_if_no_splits()
  expect_error(
    predict(fit_on_patients(), split = "validation", each = "mean"),
    "has to be a function"
  )
})

test_that("a streamed prediction composes with plot_masks the way the vignette draws it", {
  # The composition, not the pieces: `cases =` gives a named list of matrices, and
  # `plot_masks()` wants image x height x width. `simplify2array` returns height x width x
  # image, so the `aperm` is load-bearing and silently wrong without this test. Checked on a
  # toy fixture because the document that uses it costs two and a half hours to rebuild, and
  # a figure that fails at the end of one is how the last attempt was lost.
  skip_if_no_splits()
  skip_if_not_installed("ggplot2")
  fit <- fit_on_patients()
  cases <- evaluate_cases(fit, split = "validation")$case[1:2]
  masks <- predict(fit, split = "validation", cases = cases)

  stacked <- aperm(simplify2array(masks), c(3, 1, 2))
  expect_identical(dim(stacked)[1], 2L)
  expect_identical(dim(stacked)[-1], dim(masks[[1]]))
  expect_identical(stacked[1, , ], masks[[1]])

  figure <- plot_masks(
    images = array(stats::runif(2 * dim(stacked)[2] * dim(stacked)[3] * 3),
                   dim = c(2, dim(stacked)[2], dim(stacked)[3], 3)),
    prediction = stacked,
    labels = cases
  )
  expect_s3_class(figure, "ggplot")
})

test_that("`at = \"source\"` scores on the grid the files are on", {
  # The point of the argument rather than its mechanics: a model reading at 16 is scored
  # against a truth reduced to 16, and that is not the truth on disk. The engine's own
  # suite proves the arithmetic; what this proves is that R can ask for it at all and gets
  # a table back rather than an unused argument.
  skip_if_no_splits()
  fit <- fit_on_patients(input_shape = c(16, 16))

  cases <- evaluate_cases(fit, at = "source")
  expect_s3_class(cases, "platypus_cases")
  expect_equal(nrow(cases), 12)
  expect_true(all(cases$dice >= 0 & cases$dice <= 1))

  on_model <- evaluate_cases(fit)
  expect_false(isTRUE(all.equal(cases$dice, on_model$dice)))
})

test_that("the comparison table says which grid produced it", {
  skip_if_no_splits()
  fit <- fit_on_patients(input_shape = c(16, 16))

  expect_equal(evaluate(fit, at = "source")$load_shape, "source")
  expect_equal(evaluate(fit)$load_shape, "16 x 16")
  # A loss on a resampled prediction would be a number with no training meaning.
  expect_false("loss" %in% names(evaluate(fit, at = "source")))
})

test_that("a grid that is not offered is refused by name", {
  skip_if_no_splits()
  expect_error(evaluate(fit_on_patients(), at = "native"), "'model' or 'source'")
})
