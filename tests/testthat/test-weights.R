# Weights by name, and saving your own. Nothing here downloads anything: fetching from the Hub is
# the engine's job and is tested there, offline. What belongs here is the surface - the listing
# arriving as a data frame, and a trained model's weights making the round trip through R.

test_that("the published weights are listed with the commit each name is pinned to", {
  skip_if_no_weights_registry()
  listing <- available_weights()

  expect_s3_class(listing, "data.frame")
  expect_true(all(c("name", "repo", "filename", "revision", "description") %in% names(listing)))
  expect_true(nrow(listing) >= 1)
  # A full commit hash, not a branch: a branch can be moved to different numbers later.
  expect_true(all(grepl("^[0-9a-f]{40}$", listing$revision)))
  expect_true(all(grepl("[.]safetensors$", listing$filename)))
})

test_that("the nuclei entry says what it cannot do", {
  # Someone chooses weights by reading this. The limitation decides whether they answer the right
  # question, so it has to be in the description and not only in a paper somewhere.
  skip_if_no_weights_registry()
  listing <- available_weights()
  nuclei <- listing[listing$name == "dsbowl-unet", ]

  expect_equal(nrow(nuclei), 1)
  expect_match(nuclei$description, "BBBC038")
  expect_match(nuclei$description, "[Ss]emantic")
})

test_that("the retinal entry carries the two things a reader would get wrong", {
  # The third published set, and the first where the description has to correct an assumption
  # rather than only state a limitation. Its per-disease table reads picture quality as
  # pathology - glaucoma is the weakest group over all 200 test images and the strongest over
  # the ones FIVES grades clean - and these weights are CC BY 4.0 while the other two are MIT.
  # Both are things somebody reading only the headline Dice would get wrong.
  skip_if_no_weights_registry()
  listing <- available_weights()
  vessels <- listing[listing$name == "fives-unet", ]

  expect_equal(nrow(vessels), 1)
  expect_match(vessels$description, "FIVES")
  expect_match(vessels$description, "glaucoma")
  # Not "CC BY 4.0", which appears twice - once for the data, once for the weights. The
  # engine-side version of this test passed with the licence sentence deleted for exactly
  # that reason.
  expect_match(vessels$description, "not MIT")
})

test_that("the instance entry cannot offer a score without the decoding it came from", {
  # The fourth published set and the first whose score is not one number: one trained file,
  # three decodings, and 0.0623 between the best and the worst against a run-to-run spread of
  # 0.009. An R user meets all of that through this data frame and nowhere else, so the thing
  # that has to be in the description is a decoding beside every score.
  #
  # Checked against the arithmetic rather than against the four decimals, which is all a test
  # on this side can do: the measurements live in the Hub repository, so what is verifiable
  # here is that the gap the description claims for the separation signal is the gap between
  # the rows it quotes, and that the perfect-mask figure beside it is the larger of the two -
  # the entry's actual claim, that the mask is the limit on this data and not the signal.
  skip_if_no_weights_registry()
  listing <- available_weights()
  objects <- listing[listing$name == "dsbowl-instances", ]

  expect_equal(nrow(objects), 1)
  expect_match(objects$description, "BBBC038")
  expect_match(objects$description, "decoding")

  scored <- regmatches(
    objects$description,
    gregexpr("[0-9][.][0-9]{4} by [a-z_]+", objects$description)
  )[[1]]
  expect_setequal(
    sub("^.* by ", "", scored),
    c("nearest_seed", "watershed", "connected_components")
  )

  numbers <- as.numeric(sub(" by .*$", "", scored))
  expect_match(objects$description, sprintf("[+]%.4f", max(numbers) - min(numbers)), fixed = FALSE)
  perfect <- as.numeric(sub(
    "^.*perfect mask is worth [+]([0-9][.][0-9]{4}).*$", "\\1", objects$description
  ))
  expect_gt(perfect, max(numbers) - min(numbers))
})

test_that("a trained model's weights make the round trip through R", {
  skip_if_no_weights_registry()
  root <- tiny_dataset()
  spec <- platypus_spec(
    data = segmentation_data(root, root, colormap = binary_colormap),
    models = list(u_net("tiny", input_shape = c(32, 32), blocks = 2, filters = 4,
                        epochs = 1, batch_size = 2,
                        metrics = list(metric_dice())))
  )
  fit <- platypus_fit(spec, num_workers = 0)

  out <- file.path(withr::local_tempdir(), "mine")
  written <- export_weights(fit, out, data = "the tiny fixture", licence = "MIT")
  expect_true(file.exists(written))
  expect_true(file.exists(sub("[.]safetensors$", ".json", written)))

  # The sidecar comes back attached, so seeing what was recorded needs no JSON reader in R.
  recorded <- attr(written, "recorded")
  expect_equal(unlist(recorded$input_shape), c(32L, 32L))
  # Whatever was passed rides along: provenance belongs with the file.
  expect_equal(recorded$data, "the tiny fixture")
  expect_equal(recorded$licence, "MIT")

  # And two things NOBODY passed, since engine 0.8.0a75. This is R's receipt for the
  # paragraph `?export_weights` gained with that pin: the page tells a reader the engine
  # writes these without being asked, and until this the claim was prose about the other
  # package's behaviour with nothing reading it. `maju116/pyplatypus#419`.
  expect_match(recorded$trained_with, "^pyplatypus ")
  expect_identical(sub("^pyplatypus ", "", recorded$trained_with),
                   platypus_status()$engine_version)

  # `measured_with` is the one the issue is about, and the assertion is on the parameter
  # nobody wrote: `metric_dice()` above sets no `smooth`, so a block recording the
  # configuration AS WRITTEN would carry nothing here. Resolved, it carries the default -
  # which is the whole reason the key exists, since clDice's peel count arrived the same way
  # and moved a published figure by about five points.
  expect_identical(recorded$measured_with$engine, platypus_status()$engine_version)
  metrics <- recorded$measured_with$metrics
  expect_length(metrics, 1L)
  expect_identical(metrics[[1]]$name, "dice")
  expect_false(is.null(metrics[[1]]$smooth))

  # And the DATA's half, since engine 0.8.0a79: how the data was READ, which decides what the
  # figures were measured ON rather than how they were computed. `maju116/pyplatypus#447`.
  # The receipt is for the same reason as the two above - `?export_weights` tells a reader
  # this block carries it, and until something reads it that is prose about the other
  # package's behaviour.
  #
  # `window` is asserted rather than merely present, and `"auto"` is the value: nothing in
  # the specification above names a window, so a block recording only what a configuration
  # STATED would carry nothing here. It is the same argument `measured_with$metrics` makes
  # one assertion up, one layer out.
  expect_identical(recorded$measured_with$window, "auto")

  # The asymmetry, held because a reader would guess the other way and the help page says so:
  # the two halves of a specification inherit DIFFERENTLY. An instance model extends the
  # segmentation model and so has `splits`; instance DATA extends the base data class, so a
  # semantic fit records `channels_from` and `target_spacing` and an instance fit records
  # neither. This specification names neither either, so their ABSENCE is the assertion -
  # "only what is set", which is what separates *this run named none* from *written by an
  # engine that could not answer*.
  expect_false("channels_from" %in% names(recorded$measured_with))
  expect_false("target_spacing" %in% names(recorded$measured_with))

  # The refusal, which is what makes the two keys the engine's answer rather than a default
  # somebody can quietly replace.
  expect_error(
    export_weights(fit, file.path(withr::local_tempdir(), "clash"), trained_with = "mine"),
    "trained_with"
  )

  # And they load back into the same specification, which is the point of saving them.
  again <- platypus_spec(
    data = segmentation_data(root, root, colormap = binary_colormap),
    models = list(u_net("tiny", input_shape = c(32, 32), blocks = 2, filters = 4,
                        epochs = 1, batch_size = 2, weights = written, fit = FALSE,
                        metrics = list(metric_dice())))
  )
  loaded <- platypus_fit(again, num_workers = 0)
  expect_equal(dim(predict(loaded, split = "validation")), c(6L, 32L, 32L))
})

test_that("weights that belong to another model are refused with the field that differs", {
  # The sidecar's whole purpose. A wrong channel count fails inside torch anyway; a different
  # colormap with the same class count would load cleanly and predict nonsense.
  skip_if_no_weights_registry()
  root <- tiny_dataset()
  spec <- platypus_spec(
    data = segmentation_data(root, root, colormap = binary_colormap),
    models = list(u_net("tiny", input_shape = c(32, 32), blocks = 2, filters = 4,
                        epochs = 1, batch_size = 2))
  )
  written <- export_weights(platypus_fit(spec, num_workers = 0),
                            file.path(withr::local_tempdir(), "mine"))

  wider <- platypus_spec(
    data = segmentation_data(root, root, colormap = binary_colormap),
    models = list(u_net("tiny", input_shape = c(32, 32), blocks = 2, filters = 8,
                        epochs = 1, batch_size = 2, weights = written, fit = FALSE))
  )
  expect_error(platypus_fit(wider, num_workers = 0), "filters")
})

test_that("an unknown name lists the published ones", {
  skip_if_no_weights_registry()
  root <- tiny_dataset()
  spec <- platypus_spec(
    data = segmentation_data(root, root, colormap = binary_colormap),
    models = list(u_net("tiny", input_shape = c(32, 32), blocks = 2, filters = 4,
                        epochs = 1, batch_size = 2, weights = "not-a-thing", fit = FALSE))
  )
  expect_error(platypus_fit(spec, num_workers = 0), "no published weights")
})

test_that("export_weights refuses what it cannot save", {
  expect_error(export_weights(list(), "somewhere"), "platypus_fit")
})

test_that("the fetal-head entry is the one not to choose on its Dice", {
  # The fifth published set and the first where the score a reader reaches for first is the
  # wrong one: these weights exist for a length in millimetres, and on this run the Dice
  # orders the cases differently from the millimetres. Somebody picks weights by reading this
  # description, so the warning has to be in it and not only on a model card.
  skip_if_no_weights_registry()
  listing <- available_weights()
  skull <- listing[listing$name == "hc18-unet", ]

  expect_equal(nrow(skull), 1)
  expect_match(skull$description, "HC18")
  expect_match(skull$description, "Do not choose these weights on the Dice")
  # Not "CC BY 4.0", which appears twice - once for the data and once for the weights - the
  # same trap `fives-unet`'s test above records.
  expect_match(skull$description, "not MIT")

  # Read the figures out of the description BY THEIR ROLE and compare what was read. The
  # engine-side version of this test first bound them as literals and asserted one below the
  # other, which is true whatever the description says: it stayed green with the two numbers
  # swapped in the entry. Found by mutating the entry, not by reading the test.
  figure <- function(pattern) {
    found <- regmatches(skull$description, regexpr(pattern, skull$description))
    expect_length(found, 1)
    as.numeric(regmatches(found, regexpr("[0-9.]+", found)))
  }
  median_mm <- figure("Median absolute error [0-9.]+ mm")
  mean_mm <- figure("mean [0-9.]+ mm")
  expect_lt(median_mm, mean_mm)

  # The order is the claim: millimetres first, the Dice named only inside the sentence
  # telling the reader not to choose on it.
  expect_lt(
    as.integer(regexpr("millimetres", skull$description)),
    as.integer(regexpr("Dice", skull$description))
  )

  # And the control, because every assertion here is about this entry being unlike the rest:
  # the nearest one has to report no millimetres at all.
  vessels <- listing[listing$name == "fives-unet", ]
  expect_false(grepl(" mm", vessels$description))
})

test_that("a window somebody DID name reaches the sidecar", {
  # The other direction of `maju116/pyplatypus#447`. The test above asserts `"auto"` - the
  # value nobody wrote, which is the resolved-rather-than-as-written argument - and on its own
  # that is satisfied by a block recording a constant. This names one.
  #
  # A window is ignored for ordinary pictures, and these are PNGs, which is exactly why the
  # RECORD matters: the number beside the weights was measured under whatever windowing the
  # specification asked for, and nothing else in the file says which. Recording it where it
  # had no effect is cheaper than a reader having to know.
  skip_if_no_weights_registry()
  root <- tiny_dataset()
  spec <- platypus_spec(
    data = segmentation_data(root, root, colormap = binary_colormap, window = "lung"),
    models = list(u_net("tiny", input_shape = c(32, 32), blocks = 2, filters = 4,
                        epochs = 1, batch_size = 2,
                        metrics = list(metric_dice())))
  )
  fit <- platypus_fit(spec, num_workers = 0)
  written <- export_weights(fit, file.path(withr::local_tempdir(), "windowed"))
  recorded <- attr(written, "recorded")

  expect_identical(recorded$measured_with$window, "lung")
  # `channels_from` and `target_spacing` are a SEMANTIC data field and this is one, so their
  # absence here is still *this run named none* rather than *this task has none*. The engine's
  # own suite holds the set direction for those two; what R holds is that the forward exists
  # and that the block is this package's to read.
  expect_false("target_spacing" %in% names(recorded$measured_with))
})

test_that("the split a run partitioned with reaches the sidecar, resolved", {
  # `maju116/pyplatypus#450`, and the companion to the `window` receipts above: those say what
  # the pictures looked like when they were measured, this says WHICH pictures there were.
  #
  # `CLAUDE.md` §4 has what the silence cost. `dsbowl-unet`'s card reports Dice over "134
  # held-out images"; the 134 case directories on that disk are a DIFFERENT 134, and the
  # discrepancy that gave it away was 0.01 of Dice - which is also what a rounding difference
  # looks like. `fractions`, `group_by` and `seed` with the files that were found turn *which
  # 134* from a question into a reading.
  #
  # RESOLVED is the half that matters, and the seed is the proof of it: nothing below writes
  # one, so a block recording the configuration as WRITTEN would carry a partition nobody can
  # rebuild. `group_by` is in it for the other half - that is what makes a split by patient
  # rather than by file, which is the difference `split_dataset()` exists to let you keep.
  skip_if_no_weights_registry()
  root <- tiny_dataset()
  spec <- platypus_spec(
    data = segmentation_data(
      root,
      colormap = binary_colormap,
      split = list(fractions = c(0.7, 0.3), group_by = NULL)
    ),
    models = list(u_net("tiny", input_shape = c(32, 32), blocks = 2, filters = 4,
                        epochs = 1, batch_size = 2,
                        metrics = list(metric_dice())))
  )
  fit <- platypus_fit(spec, num_workers = 0)
  written <- export_weights(fit, file.path(withr::local_tempdir(), "partitioned"))
  recorded <- attr(written, "recorded")$measured_with

  expect_identical(unlist(recorded$split$fractions), c(0.7, 0.3))
  expect_identical(recorded$split$seed, 0L)
  expect_true("group_by" %in% names(recorded$split))

  # `split` is not `splits`, and they sit in this one block one letter apart: the first is
  # which cases were held out, the second how a source image was cut into tiles. A reader
  # meeting both reads one for the other, so the receipt says they are different keys.
  expect_false("splits" %in% names(recorded$split))
  expect_true("splits" %in% names(recorded))
})

test_that("a run that names a second folder records NO split, which is the absent case", {
  # The other direction, and it is a real case rather than a theoretical one: the two ways of
  # getting a validation set are exclusive, so a run with a second folder partitioned nothing
  # and the record says so by saying nothing. Without this the test above passes on a block
  # that records a split unconditionally.
  skip_if_no_weights_registry()
  root <- tiny_dataset()
  spec <- platypus_spec(
    data = segmentation_data(root, root, colormap = binary_colormap),
    models = list(u_net("tiny", input_shape = c(32, 32), blocks = 2, filters = 4,
                        epochs = 1, batch_size = 2,
                        metrics = list(metric_dice())))
  )
  fit <- platypus_fit(spec, num_workers = 0)
  written <- export_weights(fit, file.path(withr::local_tempdir(), "two-folders"))
  recorded <- attr(written, "recorded")$measured_with

  expect_false("split" %in% names(recorded))
  # And the block is otherwise the same one, or this asserts that the key is missing because
  # nothing was recorded at all.
  expect_identical(recorded$window, "auto")
})
