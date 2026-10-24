test_that("a specification built from arguments reaches the engine intact", {
  skip_if_no_engine()
  spec <- platypus_spec(
    data = segmentation_data(tempdir(), tempdir(), colormap = binary_colormap),
    models = list(u_net("unet", input_shape = c(256, 256), blocks = 4, filters = 16))
  )
  expect_s3_class(spec, "platypus_spec")

  built <- as.list(spec)
  expect_length(built$models, 1L)
  expect_identical(built$models[[1]]$name, "unet")
  expect_identical(built$models[[1]]$architecture, "u_net")
  expect_equal(unlist(built$models[[1]]$input_shape), c(256L, 256L))
})

test_that("the engine's defaults apply to anything left unset", {
  # R keeps NULLs in a list, so an unset argument would otherwise cross over as an
  # explicit None and overwrite the default on the other side.
  skip_if_no_engine()
  built <- as.list(platypus_spec(
    data = segmentation_data(tempdir(), tempdir(), colormap = binary_colormap),
    models = list(u_net("unet", input_shape = c(64, 64)))
  ))
  model <- built$models[[1]]
  expect_identical(model$loss$name, "cce")
  expect_identical(model$optimizer$name, "adam")
  expect_equal(model$blocks, 4L)
  expect_null(model$splits)
})

test_that("arguments and YAML produce the same specification", {
  # The contract the whole design rests on: a colleague's configuration file and your R
  # script describe the same experiment, and nothing downstream can tell them apart.
  skip_if_no_engine()
  path <- withr::local_tempfile(fileext = ".yaml")
  writeLines(
    gsub("PLACEHOLDER", tempdir(),
         readLines(test_path("fixtures", "experiment.yaml")), fixed = TRUE),
    path
  )

  from_file <- platypus_spec(path)
  from_code <- platypus_spec(
    data = segmentation_data(tempdir(), tempdir(), colormap = binary_colormap),
    models = list(u_net(
      "unet", input_shape = c(256, 256), channels = 3,
      blocks = 4, filters = 16,
      loss = loss_cce_dice(cce_weight = 0.5),
      metrics = list(metric_dice(include_background = FALSE)),
      optimizer = optimizer_adam(learning_rate = 0.001),
      epochs = 20, batch_size = 8
    ))
  )

  expect_identical(as.list(from_file), as.list(from_code))
})

test_that("numbers arrive as the integers the engine expects", {
  # R numerics are doubles, so a plain 4 crosses as 4.0. Leaving that to coercion works
  # until it does not, and then the message comes from a library the user never invoked.
  skip_if_no_engine()
  built <- as.list(platypus_spec(
    data = segmentation_data(tempdir(), tempdir(), colormap = binary_colormap),
    models = list(u_net("unet", input_shape = c(64, 64), blocks = 3, filters = 8,
                        epochs = 5, batch_size = 4, splits = c(2, 2)))
  ))
  model <- built$models[[1]]
  expect_identical(unlist(model$input_shape), c(64L, 64L))
  expect_identical(unlist(model$splits), c(2L, 2L))
  expect_equal(model$epochs, 5L)
})

test_that("several models live in one specification", {
  skip_if_no_engine()
  spec <- platypus_spec(
    data = segmentation_data(tempdir(), tempdir(), colormap = binary_colormap),
    models = list(
      u_net("a", input_shape = c(64, 64)),
      linknet("b", input_shape = c(64, 64), loss = loss_focal_tversky(alpha = 0.7)),
      res_u_net("c", input_shape = c(64, 64)),
      u_net_plus_plus("d", input_shape = c(64, 64), deep_supervision = TRUE)
    )
  )
  built <- as.list(spec)
  expect_identical(vapply(built$models, `[[`, character(1), "architecture"),
                   c("u_net", "linknet", "res_u_net", "u_net_plus_plus"))
})

test_that("a 3D specification is accepted", {
  # Rank comes from the length of input_shape, not a switch. The data pipeline stops at
  # 2D for now, but nothing in the specification does.
  skip_if_no_engine()
  built <- as.list(platypus_spec(
    data = segmentation_data(tempdir(), tempdir(), colormap = binary_colormap),
    models = list(u_net("volume", input_shape = c(32, 32, 32), blocks = 2,
                        splits = c(2, 2, 2)))
  ))
  expect_length(built$models[[1]]$input_shape, 3L)
})

# --- dividing one folder instead of naming three ------------------------------------------

test_that("split and validation are exactly one of each", {
  expect_error(segmentation_data("t", colormap = binary_colormap),
               "something to validate against")
  expect_error(
    segmentation_data("t", "v", colormap = binary_colormap,
                      split = list(fractions = c(0.8, 0.2), group_by = NULL)),
    "something to validate against"
  )
})

test_that("split must answer group_by, even with NULL", {
  # The field the whole block exists to put in front of someone: slices of one patient on
  # both sides make validation measure memory, and nothing in the output says so.
  expect_error(
    segmentation_data("t", colormap = binary_colormap,
                      split = list(fractions = c(0.8, 0.2))),
    "must say `group_by`"
  )
})

test_that("a NULL group_by survives the crossing into the engine", {
  # The bug neither suite could have caught alone. `compact()` drops a NULL because
  # everywhere else it means "not asked for"; here it is a stated answer, and the engine
  # requires the key so that nobody leaves the question open. Both rules are right and
  # they met here.
  skip_if_no_split_block()
  data <- segmentation_data("t", colormap = binary_colormap,
                            split = list(fractions = c(0.8, 0.2), group_by = NULL))
  expect_true("group_by" %in% names(data$split))
  expect_null(data$split$group_by)
  expect_silent(invisible(platypus_spec(
    data = data, models = list(u_net("u", input_shape = c(32, 32))), check_paths = FALSE
  )))
})

test_that("test and split do not both claim the test set", {
  expect_error(
    segmentation_data("t", colormap = binary_colormap, test = "x",
                      split = list(fractions = c(0.6, 0.2, 0.2), group_by = NULL)),
    "both say where the test set comes from"
  )
})

# --- loss_boundary -----------------------------------------------------------------------

test_that("loss_boundary sends nothing it was not given", {
  # The default alpha is a measured number - 0.9, because 0.5 was measured and is unusable -
  # so it lives in the engine and R must not restate it. Restating would mean an engine that
  # learns better being silently contradicted from this side.
  loss <- loss_boundary()
  expect_identical(loss$name, "boundary")
  expect_null(loss$region)
  expect_null(loss$alpha)
})

test_that("an alpha outside the open interval is refused with the reason", {
  for (bad in list(0, 1, -0.2, 1.5)) {
    expect_error(loss_boundary(alpha = bad), "strictly between 0 and 1")
  }
  expect_error(loss_boundary(alpha = "half"), "one number")
  expect_error(loss_boundary(alpha = c(0.5, 0.6)), "one number")
})

test_that("a boundary loss cannot be its own region term", {
  expect_error(loss_boundary(region = loss_boundary()), "cannot work")
})

test_that("any region loss can be combined with it, which is what the issue asked for", {
  loss <- loss_boundary(region = loss_focal(gamma = 3))
  expect_identical(loss$region$name, "focal")
  expect_identical(loss$region$gamma, 3)
})

test_that("the engine accepts it, nested region and all", {
  skip_if_no_boundary_loss()
  spec <- platypus_spec(
    data = segmentation_data("a", "b", colormap = binary_colormap),
    models = list(u_net("u", input_shape = c(32, 32),
                        loss = loss_boundary(region = loss_focal(gamma = 3),
                                             alpha = 0.8))),
    check_paths = FALSE
  )
  built <- as.list(spec)$models[[1]]$loss
  expect_identical(built$name, "boundary")
  expect_identical(built$region$name, "focal")
  expect_equal(built$alpha, 0.8)
})

test_that("unset, the engine's measured default arrives rather than one of ours", {
  skip_if_no_boundary_loss()
  spec <- platypus_spec(
    data = segmentation_data("a", "b", colormap = binary_colormap),
    models = list(u_net("u", input_shape = c(32, 32), loss = loss_boundary())),
    check_paths = FALSE
  )
  built <- as.list(spec)$models[[1]]$loss
  expect_equal(built$alpha, 0.9)          # the measured value, from the engine
  expect_identical(built$region$name, "dice")
})

# --- callback_swa ------------------------------------------------------------------------

test_that("callback_swa sends nothing it was not given", {
  # `start = 0.75` is a measured value - the arm at 0.5 was worse on every column - so it
  # lives in the engine and R must not restate it.
  cb <- callback_swa()
  expect_identical(cb$name, "swa")
  expect_null(cb$start)
  expect_null(cb$learning_rate)
})

test_that("a start outside (0, 1] is refused, and so is a non-positive rate", {
  for (bad in list(0, -0.1, 1.5, "half", c(0.5, 0.6))) {
    expect_error(callback_swa(start = bad), "above 0 and at most 1")
  }
  for (bad in list(0, -1, "fast")) {
    expect_error(callback_swa(learning_rate = bad), "one positive number")
  }
})

test_that("the engine takes it, and refuses it beside a cosine", {
  skip_if_no_swa()
  data <- segmentation_data("a", "b", colormap = binary_colormap)
  spec <- platypus_spec(
    data = data,
    models = list(u_net("u", input_shape = c(32, 32),
                        callbacks = list(callback_swa(start = 0.6,
                                                      learning_rate = 1e-3)))),
    check_paths = FALSE
  )
  built <- as.list(spec)$models[[1]]$callbacks[[1]]
  expect_identical(built$name, "swa")
  expect_equal(built$start, 0.6)

  # Both configured, neither complaining, and the average would be the last epoch: the one
  # combination worth refusing rather than documenting.
  expect_error(
    platypus_spec(
      data = data,
      models = list(u_net("u", input_shape = c(32, 32),
                          callbacks = list(callback_swa(),
                                           callback_cosine_annealing()))),
      check_paths = FALSE
    ),
    "undo each other"
  )
})

test_that("unset, the engine's measured default arrives", {
  skip_if_no_swa()
  spec <- platypus_spec(
    data = segmentation_data("a", "b", colormap = binary_colormap),
    models = list(u_net("u", input_shape = c(32, 32),
                        callbacks = list(callback_swa()))),
    check_paths = FALSE
  )
  built <- as.list(spec)$models[[1]]$callbacks[[1]]
  expect_equal(built$start, 0.75)
  expect_null(built$learning_rate)
})


# --- `regions`: overlapping classes, the third way of naming them -----------------------
#
# `regions` shipped in the engine as `0.8.0a14`. R forwarding it is a code change rather
# than a pin bump, which `maju116/rplatypus#152` measured before this was written:
# `segmentation_data()` enumerates its parameters, so `regions` was an `unused argument`,
# while a bare `data` list through `platypus_spec()` reached the engine's own validator and
# was accepted. The constructor refusing what YAML accepted is the asymmetry these close.

brats_regions <- list(
  list(name = "whole tumour", of = c(1, 2, 4)),
  list(name = "enhancing", of = 4)
)

#: Two classes drawn separately over the same image, which is what `classes_from` is for.
two_class_files <- c("_vessel\\.png$", "_organ\\.png$")

test_that("classes are named exactly one of four ways, and the message says which", {
  # "exactly one" on its own leaves the caller to work out which of their arguments the
  # complaint is about, which is the sort of message that gets read twice.
  expect_error(segmentation_data("a", "b"), "you gave none")
  expect_error(
    segmentation_data("a", "b", labels = c(0, 1), regions = brats_regions),
    "`labels` and `regions`"
  )
  # The fourth arrived with `0.8.0a28`. Every pairing with it, because this check is a
  # second copy of the engine's sentence and the only thing that keeps the copy honest is
  # a test that would notice a field left out of the list.
  expect_error(
    segmentation_data("a", "b", labels = c(0, 1), classes_from = two_class_files),
    "`labels` and `classes_from`"
  )
  expect_error(
    segmentation_data("a", "b", colormap = binary_colormap, classes_from = two_class_files),
    "`colormap` and `classes_from`"
  )
  expect_error(
    segmentation_data("a", "b", regions = brats_regions, classes_from = two_class_files),
    "`regions` and `classes_from`"
  )
  expect_error(
    segmentation_data("a", "b", colormap = binary_colormap, regions = brats_regions),
    "`colormap` and `regions`"
  )
  expect_error(
    segmentation_data("a", "b", colormap = binary_colormap, labels = c(0, 1),
                      regions = brats_regions),
    "`colormap` and `labels` and `regions`"
  )
})

test_that("`regions` travels as name and `of`, and `of` is a list even for one value", {
  data <- segmentation_data("a", "b", regions = brats_regions)
  expect_null(data$colormap)
  expect_null(data$labels)
  expect_length(data$regions, 2L)
  expect_identical(data$regions[[1]]$name, "whole tumour")
  expect_identical(data$regions[[1]]$of, list(1L, 2L, 4L))
  # The single value is the case that would break silently rather than loudly: reticulate
  # turns a length-1 integer vector into a Python *scalar*, and the schema wants an array,
  # so `of = 4` has to arrive as `[4]`. Measured both ways before the code was written, and
  # `of: [4]` is ordinary rather than an edge case - BraTS's enhancing tumour is exactly it.
  expect_identical(data$regions[[2]]$of, list(4L))
})

test_that("a region list that says too little is refused before Python starts", {
  expect_error(segmentation_data("a", "b", regions = list()), "list of `list\\(name")
  expect_error(segmentation_data("a", "b", regions = "whole tumour"), "list of `list\\(name")
  # One region is binary segmentation, which `labels` already says - and says with a
  # background channel, which `regions` has none of. The engine's schema says the same with
  # `minItems: 2`; this says it before an interpreter starts.
  expect_error(
    segmentation_data("a", "b", regions = brats_regions[1]),
    "at least two entries"
  )
  expect_error(
    segmentation_data("a", "b", regions = list(list(name = "a"), list(of = 1))),
    "needs both `name` and `of`"
  )
  expect_error(
    segmentation_data("a", "b",
                      regions = list(list(name = c("a", "b"), of = 1),
                                     list(name = "c", of = 2))),
    "one non-empty string"
  )
  expect_error(
    segmentation_data("a", "b", regions = list(list(name = "a", of = 1.5),
                                               list(name = "b", of = 2))),
    "at least one whole number"
  )
  expect_error(
    segmentation_data("a", "b", regions = list(list(name = "a", of = 1),
                                               list(name = "a", of = 2))),
    "every region needs its own `name`"
  )
})

test_that("the engine accepts what `segmentation_data(regions = )` builds", {
  skip_if_no_regions()
  # Through `platypus_spec()` rather than by handing the constructor's list to the shim,
  # and the first version of this test is why: the raw list carries explicit NULLs for
  # every field nobody set, and the engine refuses `window: None` before it ever looks at
  # `regions`. `compact()` is what the real path applies, so a test that skips it is
  # testing a call no user makes - and it failed for a reason that had nothing to do with
  # the change.
  spec <- platypus_spec(
    data = segmentation_data(".", ".", regions = brats_regions),
    models = list(u_net("m", input_shape = c(64, 64), blocks = 2, filters = 4))
  )
  expect_s3_class(spec, "platypus_spec")
  # Read back out of the engine rather than off the R object: this is the asymmetry the
  # change closes, so what matters is what the engine ended up holding.
  sent <- as.list(spec)$data$regions
  expect_length(sent, 2L)
  expect_identical(vapply(sent, function(region) region$name, character(1)),
                   c("whole tumour", "enhancing"))
  expect_equal(unlist(sent[[2]]$of), 4L)
})

# --- `classes_from`: one binary file per class, the fourth way of naming them ------------
#
# `classes_from` shipped in the engine as `0.8.0a28`, and it is the half of
# `maju116/pyplatypus#91` that 2026-10-12's decision deferred rather than dropped. R
# forwarding it is a code change rather than a pin bump for the two reasons `regions`
# measured: `segmentation_data()` enumerates its parameters, so it would be an
# `unused argument` here, and the exclusivity refusal above is R's own and had to become
# four-way or the constructor and a YAML file would disagree about the same configuration.
# `maju116/rplatypus#180`.

test_that("`classes_from` travels as patterns, and nothing else names the classes", {
  data <- segmentation_data("a", "b", classes_from = two_class_files)
  expect_identical(data$classes_from, two_class_files)
  expect_null(data$colormap)
  expect_null(data$labels)
  expect_null(data$regions)
  # Unset it is NULL, which is what `compact()` drops on the way to the engine: an older
  # engine refuses a field it does not know, so every run that has nothing to do with
  # per-class files has to be unaffected. §3D.3.
  #
  # Asserted as NULL rather than as an absent *name*, which is what the first version of
  # this test said and why it failed: the constructor's list carries a name for every
  # field, NULL or not, and the dropping happens one layer up. The neighbouring `regions`
  # test says it the same way for `colormap` and `labels`, for the same reason.
  expect_null(segmentation_data("a", "b", labels = c(0, 1))$classes_from)
})

test_that("a pattern list that says too little is refused before Python starts", {
  # One pattern is ordinary binary segmentation, which `labels = c(0, 1)` already says -
  # the engine's schema says the same with `minItems: 2`, and this says it before an
  # interpreter starts.
  expect_error(
    segmentation_data("a", "b", classes_from = "_vessel\\.png$"),
    "one pattern per class, so at least two"
  )
  expect_error(
    segmentation_data("a", "b", classes_from = c("_v\\.png$", "_v\\.png$")),
    "would make one class into two"
  )
  # And the message is about classes, not channels: the two fields share the engine's
  # matcher and nearly share these two refusals, so a copied message is the likely slip.
  expect_error(
    segmentation_data("a", "b", labels = c(0, 1), channels_from = c("_t1\\.nii", "_t1\\.nii")),
    "would make one measurement into two"
  )
})

test_that("the engine accepts what `segmentation_data(classes_from = )` builds", {
  skip_if_no_classes_from()
  # Through `platypus_spec()` rather than by handing the constructor's list to the shim,
  # for the reason the regions test above records: the raw list carries explicit NULLs that
  # the engine refuses before it looks at the field being tested.
  spec <- platypus_spec(
    data = segmentation_data(".", ".", classes_from = two_class_files),
    models = list(u_net("m", input_shape = c(64, 64), blocks = 2, filters = 4))
  )
  expect_s3_class(spec, "platypus_spec")
  # Read back out of the engine rather than off the R object: this is the asymmetry the
  # change closes, so what matters is what the engine ended up holding - and in the order
  # it was written, since the order is the channel order and nothing downstream can tell
  # a swapped pair from a correct one.
  expect_identical(unlist(as.list(spec)$data$classes_from), two_class_files)
})

test_that("the engine refuses two namings at once, so R's refusal is not the only one", {
  skip_if_no_classes_from()
  # R's check is a second copy of the engine's sentence. A copy is only safe while the
  # original still says it, so this asks the engine directly - the same reason the
  # field-prose ledger exists one layer up.
  refused <- rplatypus:::shim()$build_spec(
    list(
      task = "semantic_segmentation",
      data = list(train_path = ".", validation_path = ".",
                  labels = list(0L, 1L),
                  classes_from = list("_vessel\\.png$", "_organ\\.png$")),
      models = list(list(name = "probe", input_shape = c(64L, 64L)))
    ),
    check_paths = FALSE
  )
  expect_false(isTRUE(refused$ok))
  expect_match(paste(unlist(refused), collapse = " "), "exactly one of")
})

# --- the learning rate schedules -----------------------------------------------------

test_that("callback_step_decay refuses both ways of saying when, and neither", {
  # R's own refusal, before the bridge: this one is cheap to get wrong and the message is
  # better from the side the call was written on. The engine refuses it too, because a
  # YAML specification never passes through this function.
  expect_error(callback_step_decay(), "one of `every` and `milestones`")
  expect_error(callback_step_decay(every = 30, milestones = c(30, 60)),
               "never both")
})

test_that("the two new schedules send what they were given and nothing else", {
  linear <- callback_linear_annealing()
  expect_identical(linear$name, "linear_annealing")
  expect_identical(linear$min_lr, 0)
  expect_null(linear$epochs)

  step <- callback_step_decay(milestones = c(30, 60))
  expect_identical(step$name, "step_decay")
  expect_identical(step$milestones, c(30L, 60L))
  expect_null(step$every)
})

test_that("a published recipe's staircase reaches the engine intact", {
  skip_if_no_engine()
  spec <- platypus_spec(
    data = segmentation_data(tempdir(), tempdir(), colormap = binary_colormap),
    models = list(u_net("unet", input_shape = c(32, 32), blocks = 2, filters = 4,
                        callbacks = list(callback_step_decay(milestones = c(30, 60)))))
  )
  built <- as.list(spec)$models[[1]]$callbacks[[1]]
  expect_identical(built$name, "step_decay")
  expect_equal(unlist(built$milestones), c(30L, 60L))
})

test_that("the engine refuses two schedules, and a schedule beside the plateau callback", {
  # Not R's refusal: R forwards both and the engine is where the rule lives, so this is
  # the test that the rule is reachable from here at all.
  skip_if_no_engine()
  two_schedules <- function() {
    platypus_spec(
      data = segmentation_data(tempdir(), tempdir(), colormap = binary_colormap),
      models = list(u_net("unet", input_shape = c(32, 32), blocks = 2, filters = 4,
                          callbacks = list(callback_cosine_annealing(),
                                           callback_linear_annealing())))
    )
  }
  expect_error(two_schedules(), "two learning rate schedules")

  with_plateau <- function() {
    platypus_spec(
      data = segmentation_data(tempdir(), tempdir(), colormap = binary_colormap),
      models = list(u_net("unet", input_shape = c(32, 32), blocks = 2, filters = 4,
                          callbacks = list(callback_linear_annealing(),
                                           callback_reduce_lr_on_plateau())))
    )
  }
  expect_error(with_plateau(), "erases what the plateau callback cut")
})
