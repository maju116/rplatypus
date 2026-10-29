# One configuration must get one answer, whichever route it arrives by. Four findings from
# the reviewer's second pass, and all four are the same shape: R answered a question for
# itself that the engine already answers, and the two disagreed.
#
# `maju116/rplatypus#252` the multilabel switch, `#253` the split block, `#254` the
# whole-number rule, `#256` the class count.

spec_for <- function(..., model = NULL) {
  platypus_spec(
    data = segmentation_data(tempdir(), tempdir(), ...),
    models = list(model %||% u_net("m", input_shape = c(32, 32), blocks = 2, filters = 4)),
    check_paths = FALSE
  )
}

`%||%` <- function(x, y) if (is.null(x)) y else x


test_that("the class count comes from the engine rather than from the colormap's length", {
  skip_if_no_engine()
  # `#256`: this counted `data$colormap`, which only one of the four namings fills, so the
  # other three printed `classes : 0`.
  from_labels <- capture.output(print(spec_for(labels = c(0, 1, 2))))
  expect_match(grep("classes", from_labels, value = TRUE), "3")

  # The control: the one naming that always worked. Without it a count that had become
  # zero for every naming would satisfy nothing but would look like a fix.
  from_colormap <- capture.output(print(spec_for(colormap = voc_colormap)))
  expect_match(grep("classes", from_colormap, value = TRUE), "21")
})


test_that("the engine is what says whether a voxel may belong to more than one class", {
  skip_if_no_engine()
  # `#252`: R read `regions` alone, so `classes_from` - which makes the channels
  # independent in exactly the same way - was not recognised as multilabel at all.
  by_regions <- rplatypus:::shim()$data_facts(
    spec_for(regions = list(list(name = "a", of = c(1, 3)),
                            list(name = "b", of = c(2, 3))))$py
  )
  by_patterns <- rplatypus:::shim()$data_facts(
    spec_for(classes_from = c("_a\\.png$", "_b\\.png$"))$py
  )
  expect_true(by_regions$multilabel)
  expect_true(by_patterns$multilabel)

  # The control, and the reason the two above are not vacuous: a naming that is NOT
  # multilabel has to answer no, or the switch is stuck on.
  expect_false(rplatypus:::shim()$data_facts(spec_for(colormap = binary_colormap)$py)$multilabel)
})


test_that("the split block forwards what it was given, so the engine refuses what it must", {
  skip_if_no_engine()
  built <- function(split) {
    as.list(platypus_spec(
      data = segmentation_data(tempdir(), split = split, colormap = binary_colormap),
      models = list(u_net("m", input_shape = c(32, 32), blocks = 2, filters = 4)),
      check_paths = FALSE
    ))$data$split
  }

  # The control first, because the whole point is that the ordinary case still works -
  # including `group_by = NULL`, which is a stated answer and must not be compacted away.
  # Assigning NULL to a list element removes it, which is how the first version of this
  # fix broke exactly that.
  ok <- built(list(fractions = c(0.8, 0.2), group_by = NULL, seed = 7))
  expect_identical(ok$seed, 7L)

  # `#253`: an unknown key was dropped, so R accepted a block the YAML route refuses.
  expect_error(
    built(list(fractions = c(0.8, 0.2), group_by = NULL, sed = 7)),
    "sed", fixed = TRUE
  )
  # And `$` matches a list name by PREFIX, so this one was silently read as `seed` and
  # worked - the quietest way for a misspelling to survive.
  expect_error(
    built(list(fractions = c(0.8, 0.2), group_by = NULL, seeds = 7)),
    "seeds", fixed = TRUE
  )
})


test_that("a misspelt key does not also set the field it is a prefix of", {
  # The two halves of `#253` are separate claims and the forwarding one HIDES the other:
  # with every unknown key forwarded, `seeds = 7` is refused by the engine whether or not
  # `$` also read it as `seed`. Measured by mutation - putting `$` back failed nothing -
  # so this asserts what R SENDS rather than what the engine answers.
  #
  # `:::` on purpose. §3D.7's fourth gate runs `test_dir()` without `package =`, where an
  # internal is not in scope, and a bare call would pass here and fail there.
  block <- rplatypus:::split_block(list(fractions = c(0.8, 0.2), group_by = NULL, seeds = 7))
  # `[[` here too, and the first draft of this test proved the point by using `$`: it read
  # the forwarded `seeds` through the same prefix match and reported that the field had been
  # set. In a test asking WHICH NAME is present, `[[` is the only accessor that answers.
  expect_null(block[["seed"]])
  expect_identical(block[["seeds"]], 7)

  # The control: the correctly spelled key does set it, so the assertion above is about the
  # prefix rather than about `seed` having stopped working.
  spelled <- rplatypus:::split_block(list(fractions = c(0.8, 0.2), group_by = NULL, seed = 7))
  expect_identical(spelled[["seed"]], 7L)
  # And `group_by = NULL` survives as a stated answer, which is what this helper is built
  # by hand for - assigning NULL to a list element would silently remove it.
  expect_true("group_by" %in% names(spelled))
})


test_that("a whole-number field refuses a fraction instead of truncating it", {
  skip_if_no_engine()
  # `#254`: `as.integer(1.5)` is 1, silently, so the value became a DIFFERENT valid one -
  # and for a colormap that can land one class's colour on another's.
  expect_error(spec_for(labels = c(0, 1.5)), "whole number", fixed = TRUE)
  expect_error(
    spec_for(colormap = list(c(0, 0, 0), c(255.9, 255, 255))),
    "whole number", fixed = TRUE
  )
  expect_error(
    u_net("m", input_shape = c(32, 32), blocks = 2.5, filters = 4),
    "blocks", fixed = TRUE
  )

  # The controls: the whole-number cases still pass through, or the refusal is simply on.
  expect_identical(as.list(spec_for(labels = c(0, 1, 2)))$data$labels |> unlist(), c(0L, 1L, 2L))
  expect_identical(u_net("m", input_shape = c(32, 32), blocks = 2, filters = 4)$blocks, 2L)
})


test_that("predict(type = 'class') refuses every naming that makes channels independent", {
  skip_if_no_engine()
  # `#252` at the site that costs something. The specification is all this guard reads, so
  # the fit is a stand-in rather than a trained model: a real one would need a training run
  # to assert a refusal that happens before anything is predicted.
  fit_for <- function(...) {
    structure(
      list(spec = spec_for(...), models = "m", task = "semantic_segmentation"),
      class = "platypus_fit"
    )
  }

  # Both namings are refused, and each message names the naming the caller actually wrote -
  # this said `regions` unconditionally, so a `classes_from` reader was sent looking for a
  # field they never set.
  expect_error(
    predict(fit_for(classes_from = c("_a\\.png$", "_b\\.png$")), type = "class"),
    "classes_from", fixed = TRUE
  )
  expect_error(
    predict(fit_for(regions = list(list(name = "a", of = c(1, 3)),
                                   list(name = "b", of = c(2, 3)))), type = "class"),
    "regions", fixed = TRUE
  )

  # The control: a naming with one class per pixel must NOT be refused, so the guard is
  # answering the question rather than always saying no. The stand-in fit has no engine
  # behind it, so this call does fail - further on, and with a different message. Asserted
  # as "not this refusal" rather than as "no error", because a stand-in cannot predict.
  reached_further <- tryCatch(
    predict(fit_for(colormap = binary_colormap), type = "class"),
    error = function(e) conditionMessage(e)
  )
  expect_false(grepl("overlapping classes", reached_further, fixed = TRUE))
})
