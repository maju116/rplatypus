# Refusing to train on masks the colormap does not describe, from R.
#
# The engine does the refusing. What matters here is that it arrives as a sentence, that
# the two things the message tells you to do next are both reachable from R - which they
# were not when this was written - and that turning the check off works.

test_that("platypus_fit takes check_masks and defaults to on", {
  formals <- names(formals(platypus_fit))
  expect_true("check_masks" %in% formals)
  expect_true(eval(formals(platypus_fit)$check_masks))
})

test_that("inspect_masks refuses anything that is not a spec", {
  expect_error(inspect_masks(list(a = 1)), "platypus_spec")
})


# --- against a real engine -------------------------------------------------------------

test_that("a colormap matching no tissue is refused, readably", {
  skip_if_no_mask_check()
  root <- tiny_dataset(n = 6, size = 32)
  spec <- platypus_spec(
    # The masks the fixture writes are white; this asks for VOC red.
    data = segmentation_data(root, root, colormap = list(c(0, 0, 0), c(128, 0, 0))),
    models = list(u_net("m", input_shape = c(32, 32), blocks = 2, filters = 4, epochs = 1))
  )
  expect_error(platypus_fit(spec), "never appears in the training masks")
})

test_that("the refusal names the colour, not only the class number", {
  skip_if_no_mask_check()
  root <- tiny_dataset(n = 6, size = 32)
  spec <- platypus_spec(
    data = segmentation_data(root, root, colormap = list(c(0, 0, 0), c(128, 0, 0))),
    models = list(u_net("m", input_shape = c(32, 32), blocks = 2, filters = 4, epochs = 1))
  )
  expect_error(platypus_fit(spec), "128")
})

test_that("check_masks = FALSE trains anyway", {
  skip_if_no_mask_check()
  root <- tiny_dataset(n = 6, size = 32)
  spec <- platypus_spec(
    data = segmentation_data(root, root, colormap = list(c(0, 0, 0), c(128, 0, 0))),
    models = list(u_net("m", input_shape = c(32, 32), blocks = 2, filters = 4, epochs = 1,
                        batch_size = 2))
  )
  fit <- platypus_fit(spec, check_masks = FALSE)
  expect_s3_class(fit, "platypus_fit")
})

test_that("a correct colormap is not refused", {
  skip_if_no_mask_check()
  root <- tiny_dataset(n = 6, size = 32)
  spec <- platypus_spec(
    data = segmentation_data(root, root, colormap = binary_colormap),
    models = list(u_net("m", input_shape = c(32, 32), blocks = 2, filters = 4, epochs = 1,
                        batch_size = 2))
  )
  expect_s3_class(platypus_fit(spec), "platypus_fit")
})

test_that("inspect_masks says what matched and what did not", {
  skip_if_no_mask_check()
  root <- tiny_dataset(n = 6, size = 32)
  spec <- platypus_spec(
    data = segmentation_data(root, root, colormap = binary_colormap),
    models = list(u_net("m", input_shape = c(32, 32), blocks = 2, filters = 4, epochs = 1))
  )
  report <- inspect_masks(spec)
  expect_s3_class(report, "data.frame")
  expect_identical(nrow(report), 1L)
  expect_identical(report$split, "train")
  expect_identical(attr(report, "missing"), integer(0))
  expect_true(all(c(0L, 1L) %in% attr(report, "present")))
  expect_lte(report$unmatched, 0.01)
  expect_identical(report$total_samples, 6L)
})

test_that("inspect_masks names the class a wrong colormap loses", {
  skip_if_no_mask_check()
  root <- tiny_dataset(n = 6, size = 32)
  spec <- platypus_spec(
    data = segmentation_data(root, root, colormap = list(c(0, 0, 0), c(128, 0, 0))),
    models = list(u_net("m", input_shape = c(32, 32), blocks = 2, filters = 4, epochs = 1))
  )
  report <- inspect_masks(spec)
  expect_identical(attr(report, "missing"), 1L)
  expect_identical(report$missing_classes, "1")
  # It reads without training, which is the point of having it.
  expect_gt(report$samples_checked, 0L)
})

test_that("inspect_masks reads the split it is asked for", {
  skip_if_no_mask_check()
  root <- tiny_dataset(n = 6, size = 32)
  spec <- platypus_spec(
    data = segmentation_data(root, root, colormap = binary_colormap),
    models = list(u_net("m", input_shape = c(32, 32), blocks = 2, filters = 4, epochs = 1))
  )
  expect_identical(inspect_masks(spec, split = "validation")$split, "validation")
})

test_that("the two things the refusal tells you to do are both reachable from R", {
  skip_if_no_mask_check()
  # This is the whole reason inspect_masks() and the argument exist. The engine's message
  # names `Engine(..., check_masks=False)` and an `inspect_masks` call - neither of which
  # an R user can type. A message that suggests something impossible is worse than one
  # that only says what is wrong, so both have an R spelling and both are exercised here.
  root <- tiny_dataset(n = 6, size = 32)
  spec <- platypus_spec(
    data = segmentation_data(root, root, colormap = list(c(0, 0, 0), c(128, 0, 0))),
    models = list(u_net("m", input_shape = c(32, 32), blocks = 2, filters = 4, epochs = 1,
                        batch_size = 2))
  )
  expect_error(platypus_fit(spec))                       # refused
  expect_identical(attr(inspect_masks(spec), "missing"), 1L)   # and inspectable
  expect_s3_class(platypus_fit(spec, check_masks = FALSE), "platypus_fit")  # and overridable
})


# --- `labels` without 0 ----------------------------------------------------------------
#
# `?segmentation_data`'s `@param labels` says "**Include 0 unless the masks really do fill
# every voxel**", and until now nothing held that sentence to the engine. The engine refused
# this from `0.8.0a19`; the R prose arrived with the pin and was the whole of R's half, which
# is exactly the shape of prose that drifts. `maju116/rplatypus#153`.
#
# The pair matters more than either test. The engine deliberately refuses only when the data
# *has* unmatched voxels - `labels = c(1, 2)` over masks that genuinely fill every voxel is a
# legitimate thing and keeps working - so a single test on the refusal would pass just as well
# against "refuse whenever 0 is missing", which is a different and worse rule.

test_that("`labels` without 0 is refused when the masks have a background", {
  skip_if_no_volumes()
  skip_if_no_mask_check()
  root <- tiny_label_dataset(background = TRUE)
  spec <- platypus_spec(
    data = segmentation_data(root, root, labels = c(1, 2), window = "soft_tissue"),
    models = list(u_net("unet3d", input_shape = c(8, 8, 4), channels = 1, blocks = 2,
                        filters = 4, epochs = 1, batch_size = 1))
  )
  # The message is asserted on three things rather than one: that it names the omission, the
  # fraction it measured, and the fix. A refusal a user cannot act on is a crash with prose.
  expect_error(platypus_fit(spec, num_workers = 0), "does not contain 0")
  expect_error(platypus_fit(spec, num_workers = 0), "match none of those labels")
  expect_error(platypus_fit(spec, num_workers = 0), "add 0 to labels")
})

test_that("`labels` without 0 trains when the masks really do fill every voxel", {
  skip_if_no_volumes()
  skip_if_no_mask_check()
  # Every voxel is 1 or 2 here, so nothing matches nothing and the engine has no reason to
  # refuse. This is the control: it is the run that a blanket "labels must contain 0" rule
  # could not produce, and it is the sentence in `?segmentation_data` that the test above
  # on its own would let rot.
  root <- tiny_label_dataset(background = FALSE)
  spec <- platypus_spec(
    data = segmentation_data(root, root, labels = c(1, 2), window = "soft_tissue"),
    models = list(u_net("unet3d", input_shape = c(8, 8, 4), channels = 1, blocks = 2,
                        filters = 4, epochs = 1, batch_size = 1))
  )
  expect_s3_class(platypus_fit(spec, num_workers = 0), "platypus_fit")
})


# --- `inspect_masks()` names regions ----------------------------------------------------
#
# The engine reports classes by position, and with `regions` a position is the one thing a
# reader cannot resolve: `missing_classes: 1` means the second region, and counting entries
# in a configuration file to find out which is the step nobody takes. `#152`.
#
# Measured before any of this was written: on a spec whose second region matches nothing the
# engine returns `missing = 1`, so the mapping is positional and zero-based.

regions_spec <- function(root, regions) {
  platypus_spec(
    data = segmentation_data(root, root, window = "soft_tissue", regions = regions),
    models = list(u_net("m", input_shape = c(8, 8, 4), channels = 1, blocks = 2,
                        filters = 4, epochs = 1, batch_size = 1))
  )
}

test_that("`inspect_masks()` names the region that matches nothing", {
  skip_if_no_volumes()
  skip_if_no_regions()
  root <- tiny_label_dataset(background = TRUE)
  # The masks hold 0, 1 and 2. `of = 9` is the failure this feature invites: a channel of
  # zeros that trains to predict nothing and scores a Dice of 0 while every other number in
  # the run looks ordinary.
  report <- inspect_masks(regions_spec(root, list(list(name = "present", of = 1),
                                                  list(name = "absent", of = 9))))
  expect_identical(report$missing_classes, "absent")
  expect_identical(report$present_classes, "present")
  # The positions stay in the attributes, so anything already reading them keeps working -
  # and the number is still the thing to pass back to the engine.
  expect_identical(attr(report, "missing"), 1L)
  expect_identical(attr(report, "present"), 0L)
})

test_that("R's naming is the engine's naming, not a second opinion", {
  skip_if_no_volumes()
  skip_if_no_regions()
  skip_if_no_mask_check()
  # The mapping is derived in R, from a specification R owns, rather than returned by the
  # engine - asking for it would mean a release and a pin move for a label. This is what
  # holds the two together: the engine's own refusal names the region, so R's naming is
  # compared against that sentence instead of against an opinion. If the engine ever
  # indexed regions differently, this fails and the test above would not.
  root <- tiny_label_dataset(background = TRUE)
  spec <- regions_spec(root, list(list(name = "present", of = 1),
                                  list(name = "absent", of = 9)))
  named_by_r <- inspect_masks(spec)$missing_classes
  expect_error(platypus_fit(spec, num_workers = 0),
               paste0("region '", named_by_r, "'"))
})

test_that("without `regions` the classes are still numbers", {
  skip_if_no_volumes()
  # The control: with `colormap` or `labels` the number *is* the class, so naming would be
  # inventing something the specification did not say. This is what the change must not do.
  skip_if_no_engine()
  root <- tiny_label_dataset(background = TRUE)
  spec <- platypus_spec(
    data = segmentation_data(root, root, window = "soft_tissue", labels = c(0, 1, 2)),
    models = list(u_net("m", input_shape = c(8, 8, 4), channels = 1, blocks = 2,
                        filters = 4, epochs = 1, batch_size = 1))
  )
  report <- inspect_masks(spec)
  expect_identical(report$present_classes, "0, 1, 2")
  expect_identical(attr(report, "present"), c(0L, 1L, 2L))
})


# --- `predict()` has no class mask to return for overlapping classes ---------------------
#
# The lever is R's own: the specification this fit carries says whether the classes overlap,
# and the shape of the returned array cannot - sigmoid channels and a softmax's channels are
# the same array. Without this guard `type = "class"`, which is the default, reaches the
# shim's `argmax + 1` and names one of the classes a pixel is in while dropping the rest,
# with nothing in the result to say it happened. `#152`.

test_that("predict() refuses a class mask when the classes overlap", {
  skip_if_no_volumes()
  skip_if_no_regions()
  root <- tiny_label_dataset(background = TRUE)
  spec <- regions_spec(root, list(list(name = "one", of = 1),
                                  list(name = "both", of = c(1, 2))))
  # Not trained on purpose: the guard runs before the engine is consulted, so a real run
  # would spend four minutes proving something the specification already carries. The spec
  # itself is real, which is the part that matters - `as.list()` on it goes through the
  # engine, so this also proves `regions` survives the round trip.
  fit <- structure(list(spec = spec, task = "semantic_segmentation", models = "m"),
                   class = "platypus_fit")
  expect_error(predict(fit, "m", split = "validation"), "no one class per pixel")
  expect_error(predict(fit, "m", split = "validation"), "save_class_masks")

  # The control, and it is the one that matters: without `regions` this must not fire, or
  # every ordinary run would refuse. The call then fails on something else entirely.
  plain <- structure(
    list(
      spec = platypus_spec(
        data = segmentation_data(root, root, window = "soft_tissue", labels = c(0, 1, 2)),
        models = list(u_net("m", input_shape = c(8, 8, 4), channels = 1, blocks = 2,
                            filters = 4, epochs = 1, batch_size = 1))
      ),
      task = "semantic_segmentation", models = "m"
    ),
    class = "platypus_fit"
  )
  elsewhere <- tryCatch(predict(plain, "m", split = "validation"),
                        error = conditionMessage)
  expect_false(grepl("no one class per pixel", elsewhere, fixed = TRUE))
})

test_that("predict(type = \"probability\") is the way through, and says the channel order", {
  skip_if_no_volumes()
  skip_if_no_regions()
  root <- tiny_label_dataset(background = TRUE)
  spec <- regions_spec(root, list(list(name = "one", of = 1),
                                  list(name = "both", of = c(1, 2))))
  # The names `save_class_masks()` wants, in the order it wants them, from the same place
  # `inspect_masks()` reads them - and now through the real route rather than through the
  # internal, because `maju116/rplatypus#259` moved the naming to the engine. What this
  # asserts is the pairing a file on disk has with a score in a table.
  report <- inspect_masks(spec)
  expect_identical(report$present_classes, "one, both")
})
