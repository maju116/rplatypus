# The six listings, held to the engine rather than to a list written here.
#
# The whole value of `available_losses()` and its family is that nothing in this package
# maintains them: they are read from the engine's own schema, so a loss added there appears
# in R with nothing edited. A test comparing them against names written in this file would
# assert the opposite - that somebody remembered - which is the failure mode the functions
# exist to remove. So every comparison below asks the engine the same question twice: once
# through R, once through reticulate, and checks the answers are the same set.

listing_from_engine <- function(kind, task = NULL) {
  rows <- if (is.null(task)) {
    reticulate::py_eval(sprintf("__import__('pyplatypus').available_%s()", kind))
  } else {
    reticulate::py_eval(sprintf("__import__('pyplatypus').available_%s(%s)", kind,
                                shQuote(task, type = "cmd")))
  }
  vapply(rows, function(row) row$name, character(1))
}

test_that("every listing names exactly what the engine names", {
  skip_if_no_engine()
  cases <- list(
    list(f = available_losses, kind = "losses", task = "semantic_segmentation"),
    list(f = available_metrics, kind = "metrics", task = "semantic_segmentation"),
    list(f = available_models, kind = "models", task = "semantic_segmentation"),
    list(f = available_models, kind = "models", task = "object_detection"),
    list(f = available_optimizers, kind = "optimizers", task = NULL),
    list(f = available_callbacks, kind = "callbacks", task = NULL),
    list(f = available_tasks, kind = "tasks", task = NULL)
  )
  for (case in cases) {
    got <- if (is.null(case$task)) case$f() else case$f(case$task)
    expect_setequal(got$name, listing_from_engine(case$kind, case$task))
    expect_gt(nrow(got), 0)
    expect_identical(names(got), c("name", "arguments", "description"))
    expect_true(all(nzchar(got$description)))
  }
})

test_that("the counts are what the engine's own unions hold", {
  # A floor each, so the comparison above cannot pass by matching two empty answers - §4's
  # "two numbers that were both zero". These are counts of what the pinned engine accepts,
  # not of what it will accept forever, which is why they are asserted here and written in
  # no help page.
  skip_if_no_engine()
  # 10 again since the pin moved to 0.8.0a22, and the pair below is why that is not a
  # regression. `mse`, `l1` and `smooth_l1` arrived with the regression targets in 0.8.0a17
  # and R can still reach them - through `separation_flows(loss = )` and nowhere else - but
  # the engine answers this listing per task now: a semantic model's own `loss` refuses a
  # continuous one, so advertising thirteen at that task was advertising three it would
  # refuse (`pyplatypus#223`). The instance count is asserted beside it rather than only the
  # semantic one, because a listing that merely got shorter and a listing that got right
  # look identical from one number.
  #
  # 11 and 14 since the pin moved to 0.8.0a26, which added `generalized_dice` to both - it
  # scores classes, so it is admissible wherever `dice` is. The two counts move together
  # for a class loss and apart for a continuous one, which is the thing these two numbers
  # beside each other are for.
  expect_identical(nrow(available_losses()), 11L)
  expect_identical(nrow(available_losses("instance_segmentation")), 14L)
  expect_identical(
    sort(setdiff(
      available_losses("instance_segmentation")$name, available_losses()$name
    )),
    c("l1", "mse", "smooth_l1")
  )
  # 5 since 0.8.0a26 added `surface_dice`.
  expect_identical(nrow(available_metrics()), 5L)
  expect_identical(nrow(available_optimizers()), 8L)
  # 9 since the pin moved to 0.8.0a33, which added `linear_annealing` and `step_decay`.
  # Both are schedules, so the engine now refuses two of them at once and refuses any of
  # them beside `reduce_lr_on_plateau` - a count that grew by two here corresponds to a
  # configuration surface that got *narrower*, which is the thing one number cannot say.
  #
  # 10 since 0.8.0a34 added `stop_after`. That release also widened three callbacks that
  # were already here - a warm-up on `early_stopping` and `swa`, conditions on
  # `model_checkpoint` - and this count cannot see any of it, which is why the arguments
  # are pinned below rather than only the listing's length.
  expect_identical(nrow(available_callbacks()), 10L)
  # Split rather than searched: `arguments` is one comma-joined string, and a `grepl()`
  # for "start" would also match "start_epoch" - a check that passes for the wrong reason.
  stopping <- available_callbacks()[available_callbacks()$name == "early_stopping", ]
  expect_true(all(c("start", "start_epoch") %in% strsplit(stopping$arguments, ", ")[[1]]))
  expect_identical(nrow(available_models()), 4L)
  expect_identical(nrow(available_models("object_detection")), 1L)
  expect_identical(nrow(available_tasks()), 3L)
})

test_that("arguments are a readable column and recover their parts", {
  skip_if_no_engine()
  tversky <- available_losses()[available_losses()$name == "tversky", ]
  expect_identical(strsplit(tversky$arguments, ", ")[[1]], c("alpha", "smooth"))

  # A callback with no arguments at all is the case that makes an empty string meaningful
  # rather than a missing value: `terminate_on_nan` takes nothing, and NA would read as
  # "unknown" instead of "none".
  nan <- available_callbacks()[available_callbacks()$name == "terminate_on_nan", ]
  expect_identical(nan$arguments, "")
  expect_false(is.na(nan$arguments))
})

test_that("detection says what it has instead of a loss to choose", {
  skip_if_no_engine()
  expect_error(available_losses("object_detection"), class = "platypus_error")
  expect_error(available_losses("object_detection"), "box_loss")
  # The two values come from the engine's schema rather than from its prose, so this holds
  # the message to what the specification actually accepts.
  expect_error(available_losses("object_detection"), "offsets")
  expect_error(available_losses("object_detection"), "giou")
})

test_that("detection names the metrics it reports rather than returning none", {
  skip_if_no_engine()
  expect_error(available_metrics("object_detection"), class = "platypus_error")
  for (reported in c("map_50", "map_50_95", "mean_matched_iou")) {
    expect_error(available_metrics("object_detection"), reported, fixed = TRUE)
  }
})

test_that("an unknown task lists the ones there are", {
  # This used to use `instance_segmentation` as the unknown one, which is the shape of test
  # that stops testing what it says the day the world catches up: 0.8.0a20 made it a task and
  # the assertion became "a real task is refused". A name no engine will ever have cannot
  # rot that way.
  skip_if_no_engine()
  expect_error(available_losses("panoptic_segmentation"), class = "platypus_error")
  expect_error(available_losses("panoptic_segmentation"), "semantic_segmentation")
  expect_error(available_losses("panoptic_segmentation"), "object_detection")
  expect_error(available_losses("panoptic_segmentation"), "instance_segmentation")
})

test_that("the third task answers with losses rather than with a refusal", {
  # The pin moved for this. Before 0.8.0a20 the line above was the whole story about
  # instances; now the task exists, and what it accepts is the regression losses *and* the
  # class losses - the model's own `loss` scores the mask at either separation, and only
  # `separation_flows(loss = )` is restricted to the three continuous ones.
  skip_if_no_engine()
  instance <- available_losses("instance_segmentation")
  expect_gt(nrow(instance), 0)
  expect_true(all(c("mse", "l1", "smooth_l1") %in% instance$name))
  expect_true("dice" %in% instance$name)
})

test_that("the family is spelled one way across both packages", {
  # §3A: one concept, one name. Ten exported functions answering "what can this do", and
  # `show_available_*` for any of them would be the divergence the rule exists to prevent.
  # Checked against the namespace rather than by reading the file - which is what caught
  # `available_separations` and `available_decodings` arriving on 2026-10-15, and the eight
  # above them are the engine's ten minus those two for as long as this list said eight.
  exported <- getNamespaceExports("rplatypus")
  family <- sort(grep("^available_", exported, value = TRUE))
  expect_identical(
    family,
    c("available_callbacks", "available_decodings", "available_losses", "available_metrics",
      "available_models", "available_optimizers", "available_separations",
      "available_tasks", "available_transforms", "available_weights")
  )
  expect_identical(length(grep("^show_available", exported, value = TRUE)), 0L)
})
