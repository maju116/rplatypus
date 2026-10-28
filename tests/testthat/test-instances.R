# The R surface for instance segmentation, in the parts that need no Python.
#
# Everything here is about what R itself decides: which constructor tags which task, which
# fields a constructor refuses by not having them, and that nothing is sent that nobody
# asked for. What the engine makes of the request is a different file and a different gate.

test_that("instance_data tags its own task, and that is the whole mechanism", {
  data <- instance_data("train/", "valid/")
  expect_s3_class(data, "platypus_instance_data")
  expect_identical(attr(data, "task", exact = TRUE), "instance_segmentation")
  expect_identical(data$train_path, "train/")
  expect_identical(data$validation_path, "valid/")
})

test_that("instance_data refuses the five fields that do not apply, by not having them", {
  # The point of a separate constructor rather than a flag: these are refused by R's own
  # argument matching, with no table to keep in step with the engine. A directory of
  # per-object masks has no colormap, no label list, no regions, no channel order to state
  # and no spacing to resample to.
  for (field in c("colormap", "labels", "regions", "channels_from", "target_spacing")) {
    arguments <- list("train/", "valid/")
    arguments[[field]] <- 1
    expect_error(do.call(instance_data, arguments), "unused argument", info = field)
  }
  # And the one that distinguishes it from `segmentation_data()` in the other direction:
  # that constructor *requires* exactly one of colormap and labels, this one neither.
  expect_error(segmentation_data("train/", "valid/"), "exactly one of")
  expect_no_error(instance_data("train/", "valid/"))
})

test_that("a model names its task, and separation is what makes it instances", {
  # These two assertions were `expect_null()` until `#239`: a semantic model returned the
  # plain list and let `task_of()`'s default speak for it, which is what made a built model
  # indistinguishable from a bare one. The tag is explicit now and the thing being tested is
  # unchanged - `separation` is the only field that turns it into instances.
  semantic <- u_net("m", input_shape = c(256, 256))
  expect_identical(attr(semantic, "task", exact = TRUE), "semantic_segmentation")

  instance <- u_net("m", input_shape = c(256, 256), separation = separation_rim())
  expect_identical(attr(instance, "task", exact = TRUE), "instance_segmentation")
  expect_identical(instance$separation, list(name = "rim"))

  # `decode` alone must not make it an instance model: it is optional on one, so a model
  # that decoded without predicting a signal would be a specification with no way to
  # produce one.
  decoded <- u_net("m", input_shape = c(256, 256), decode = list(decode_watershed()))
  expect_identical(attr(decoded, "task", exact = TRUE), "semantic_segmentation")

  # And `weights` without `separation` is the one that admits either, which pyplatypus
  # `0.8.0a28` permits because the sidecar records what the channels predict.
  weighted <- u_net("m", input_shape = c(256, 256), weights = "dsbowl-instances")
  expect_identical(
    attr(weighted, "task", exact = TRUE),
    c("semantic_segmentation", "instance_segmentation")
  )
})

test_that("all four architectures carry separation, not just the one that was tested", {
  for (architecture in list(u_net, u_net_plus_plus, res_u_net, linknet)) {
    model <- architecture("m", input_shape = c(256, 256), separation = separation_flows())
    expect_identical(attr(model, "task", exact = TRUE), "instance_segmentation")
    expect_identical(model$separation$name, "flows")
  }
})

test_that("a separation block sends only what it was given", {
  # §3D's rule: defaults live in the engine. `width` is the sharp case - the engine's 2
  # stands on an argument rather than a measurement, so an R-side copy of it would freeze
  # a number that is expected to move.
  expect_identical(separation_rim(), list(name = "rim"))
  expect_identical(separation_rim(width = 3), list(name = "rim", width = 3L))
  expect_identical(separation_flows(), list(name = "flows"))
  expect_identical(
    separation_flows(mode = "centroid", weight = 2),
    list(name = "flows", mode = "centroid", weight = 2)
  )
})

test_that("every decoding the engine offers has a constructor, and they agree on names", {
  # This test said "the engine offers" and asked a list written here, so the engine could
  # have grown a fifth decoding with nothing failing - the shape §4 calls a declaration
  # beside a mechanism that does not describe it. It asks now, which is what
  # `available_decodings()` is for beyond discoverability.
  skip_if_no_engine()
  constructors <- list(
    connected_components = decode_connected_components,
    nearest_seed = decode_nearest_seed,
    watershed = decode_watershed,
    follow_flows = decode_follow_flows
  )
  expect_setequal(available_decodings()$name, names(constructors))
  for (expected in available_decodings()$name) {
    expect_true(expected %in% names(constructors), info = expected)
    expect_identical(constructors[[expected]](), list(name = expected), info = expected)
  }
})

test_that("every separation the engine offers has a constructor too", {
  skip_if_no_engine()
  constructors <- list(rim = separation_rim, flows = separation_flows)
  expect_setequal(available_separations()$name, names(constructors))
  for (expected in available_separations()$name) {
    expect_identical(constructors[[expected]](), list(name = expected), info = expected)
  }
})

test_that("the two instance listings carry the column they are asked for", {
  # `needs` is the question somebody opens `available_decodings()` to answer: a decoding
  # that needs `rim` cannot be put on a model predicting `flows`, and the engine refuses it.
  # Empty for `connected_components`, which is why it is the one always available.
  skip_if_no_engine()
  decodings <- available_decodings()
  expect_true(all(c("name", "arguments", "description", "needs") %in% names(decodings)))
  needs <- stats::setNames(decodings$needs, decodings$name)
  expect_identical(needs[["connected_components"]], "")
  expect_identical(needs[["follow_flows"]], "flows")
  expect_identical(needs[["nearest_seed"]], "rim")
  expect_identical(needs[["watershed"]], "rim")

  separations <- available_separations()
  expect_true("head_channels" %in% names(separations))
  widths <- stats::setNames(separations$head_channels, separations$name)
  expect_identical(as.integer(widths[["rim"]]), 3L)
  expect_identical(as.integer(widths[["flows"]]), 4L)
})

test_that("the six listings with no extra field still have exactly three columns", {
  # The control for the generalisation: columns are taken from the engine's rows, so a bug
  # there would show as a stray column on every listing rather than a missing one.
  skip_if_no_engine()
  for (listing in list(available_tasks, available_models, available_losses,
                       available_metrics, available_optimizers, available_callbacks)) {
    expect_identical(names(listing()), c("name", "arguments", "description"))
  }
})

test_that("a decoding sends its own settings and nothing else", {
  expect_identical(
    decode_connected_components(minimum_area = 20),
    list(name = "connected_components", minimum_area = 20L)
  )
  expect_identical(
    decode_follow_flows(steps = 50, step_size = 0.5, minimum_area = 4),
    list(name = "follow_flows", steps = 50L, step_size = 0.5, minimum_area = 4L)
  )
  # `step_size` is a distance in pixels and the interesting values are below 1. Coercing it
  # the way every count here is coerced would turn 0.5 into a decoding that never moves,
  # which is a wrong answer rather than an error - so it is the one field here left as a
  # double, and this is the assertion that says so.
  expect_identical(decode_follow_flows(step_size = 0.5)$step_size, 0.5)
  expect_type(decode_follow_flows(steps = 50)$steps, "integer")
})

test_that("the three regression losses exist in R, because separation_flows asks for one", {
  # `separation_flows(loss = )` documents an objective R could not build until the pin
  # moved: the engine gained `mse`, `l1` and `smooth_l1` in 0.8.0a17 and nothing in R named
  # them. A help page pointing at a constructor that does not exist is §4's "an instruction
  # addressed to a human is code nothing runs".
  expect_identical(loss_mse(), list(name = "mse"))
  expect_identical(loss_l1(where = "everywhere"), list(name = "l1", where = "everywhere"))
  expect_identical(
    loss_smooth_l1(beta = 0.1, where = "foreground"),
    list(name = "smooth_l1", beta = 0.1, where = "foreground")
  )
  # Nothing is sent that nobody asked for: the engine's `where` default stands on a
  # measurement of this dataset's foreground fraction, and an R-side copy would be
  # indistinguishable from a user's choice.
  expect_named(loss_smooth_l1(), "name")

  built <- separation_flows(loss = loss_mse(where = "foreground"), weight = 0.5)
  expect_identical(built$loss, list(name = "mse", where = "foreground"))
  expect_identical(built$name, "flows")
})

# --- the task is inferred from the pair, and mixing is refused ----------------------------

test_that("an instance data block and an instance model agree on one task", {
  expect_identical(
    rplatypus:::agreed_task(
      instance_data("a/", "b/"),
      list(u_net("u", input_shape = c(64, 64), separation = separation_rim()))
    ),
    "instance_segmentation"
  )
})

test_that("instance data with a plain segmentation model is refused, and named", {
  # The pair that would otherwise be silent: the same directory layout and the same
  # architecture, differing only in whether a signal is predicted at all.
  #
  # Still true after `0.8.0a28` widened what a silent model may be, and this is the case
  # that kept the widening narrow: a model with no `weights` has nothing to adopt the
  # separation from, so it cannot be an instance model. `maju116/rplatypus#181`.
  caught <- tryCatch(
    rplatypus:::agreed_task(
      instance_data("a/", "b/"),
      list(u_net("plain", input_shape = c(64, 64)))
    ),
    error = function(e) conditionMessage(e)
  )
  expect_match(caught, "mixes them")
  expect_match(caught, "the data is instance_segmentation")
  expect_match(caught, "plain is semantic_segmentation")
})

test_that("a model that leaves the separation to its weights is admissible for instances", {
  # `0.8.0a28` lets an instance model omit `separation` when `weights` names a file whose
  # sidecar records what it was trained to predict. R reads a model's task from that field,
  # so until this a silent model was read as semantic and the pair below was refused as two
  # tasks in one specification - which made the engine's own headline example, written as
  # an R snippet, impossible to write in R. `maju116/rplatypus#181`.
  expect_identical(
    rplatypus:::agreed_task(
      instance_data("a/", "b/"),
      list(u_net("objects", input_shape = c(64, 64), weights = "dsbowl-instances"))
    ),
    "instance_segmentation"
  )
  # The same model beside semantic data is still semantic: the data decides inside the
  # overlap, and `weights` widens what a model *may* be rather than what it is.
  expect_identical(
    rplatypus:::agreed_task(
      segmentation_data("a/", "b/", colormap = binary_colormap),
      list(u_net("m", input_shape = c(64, 64), weights = "dsbowl-unet"))
    ),
    "semantic_segmentation"
  )
  # And the case the fix must not swallow, which is why it is an intersection rather than
  # "the data decides when the model is silent": a u_net says nothing about detection.
  expect_error(
    rplatypus:::agreed_task(
      detection_data("a/", "b/", classes = c("rbc", "wbc")),
      list(u_net("m", input_shape = c(64, 64), weights = "dsbowl-unet"))
    ),
    "mixes them"
  )
})

test_that("the engine refuses a silent model whose file does not say either", {
  skip_if_no_engine()
  # The other half of the permission, and it is the engine's because only the engine can
  # read a sidecar: a model that leaves `separation` to a *semantic* weights file is
  # admissible here and refused there, naming the file rather than the field.
  refused <- rplatypus:::shim()$build_spec(
    list(
      task = "instance_segmentation",
      data = list(train_path = ".", validation_path = "."),
      models = list(list(name = "objects", input_shape = c(64L, 64L),
                         weights = "dsbowl-unet"))
    ),
    check_paths = FALSE
  )
  # The specification itself is accepted - the refusal belongs to `fit`, where the registry
  # is reachable - so what this asserts is that R's side no longer stands in the way.
  expect_true(isTRUE(refused$ok))
})

test_that("stating the task is still checked rather than trusted", {
  # The rule the whole decision turned on: a constructor decides, `task` confirms.
  expect_identical(
    rplatypus:::agreed_task(
      instance_data("a/", "b/"),
      list(u_net("u", input_shape = c(64, 64), separation = separation_flows())),
      stated = "instance_segmentation"
    ),
    "instance_segmentation"
  )
  expect_error(
    rplatypus:::agreed_task(
      instance_data("a/", "b/"),
      list(u_net("u", input_shape = c(64, 64), separation = separation_flows())),
      stated = "semantic_segmentation"
    ),
    "disagrees with what this specification is built from"
  )
  # And it is a known value now, so it no longer reaches the "must be one of" refusal.
  expect_error(
    rplatypus:::agreed_task(instance_data("a/", "b/"), list(u_net("u", input_shape = c(64, 64))),
                            stated = "instances"),
    "`task` must be one of"
  )
})

# --- and the half that does need Python ---------------------------------------------------
#
# Everything above is R deciding things on its own, and green on all of it would still leave
# the question §4 keeps asking: has anything used this the way a user reaches it? These send
# the request. Without them the surface could be wrong in the one way R cannot see - a field
# the engine does not have, or has under another name - and the whole suite would pass.

test_that("an instance specification reaches the engine intact", {
  skip_if_no_engine()
  spec <- platypus_spec(
    data = instance_data(tempdir(), tempdir()),
    models = list(u_net(
      "rim", input_shape = c(128, 128), blocks = 3, filters = 8,
      separation = separation_rim(width = 2),
      decode = list(decode_nearest_seed(), decode_connected_components(minimum_area = 4))
    ))
  )
  expect_s3_class(spec, "platypus_spec")

  built <- as.list(spec)
  expect_identical(built$task, "instance_segmentation")
  model <- built$models[[1]]
  expect_identical(model$separation$name, "rim")
  expect_equal(model$separation$width, 2L)
  expect_identical(vapply(model$decode, function(d) d$name, character(1)),
                   c("nearest_seed", "connected_components"))
  expect_equal(model$decode[[2]]$minimum_area, 4L)
})

test_that("the flow surface reaches the engine too, with its own loss", {
  skip_if_no_engine()
  built <- as.list(platypus_spec(
    data = instance_data(tempdir(), tempdir()),
    models = list(u_net(
      "flows", input_shape = c(128, 128),
      separation = separation_flows(mode = "diffusion",
                                    loss = loss_mse(where = "foreground"), weight = 1),
      decode = list(decode_follow_flows(step_size = 0.5))
    ))
  ))
  separation <- built$models[[1]]$separation
  expect_identical(separation$name, "flows")
  expect_identical(separation$mode, "diffusion")
  expect_identical(separation$loss$name, "mse")
  expect_identical(separation$loss$where, "foreground")
  expect_equal(built$models[[1]]$decode[[1]]$step_size, 0.5)
})

test_that("the engine refuses the combinations R deliberately does not police", {
  # R sends what it was given and the engine decides. Both of these are refusals R has no
  # copy of, which is the point: a second rule here would be a second place to keep in step.
  skip_if_no_engine()
  expect_error(
    platypus_spec(
      data = instance_data(tempdir(), tempdir()),
      models = list(u_net("m", input_shape = c(64, 64),
                          separation = separation_flows(loss = loss_dice())))
    ),
    "defined over classes"
  )
  # A decoding that cannot read the signal it is given, named at both ends rather than
  # returning a label map of something else.
  expect_error(
    platypus_spec(
      data = instance_data(tempdir(), tempdir()),
      models = list(u_net("m", input_shape = c(64, 64),
                          separation = separation_rim(),
                          decode = list(decode_follow_flows())))
    ),
    "follow_flows"
  )
})

test_that("an instance run goes all the way through, from R", {
  # The one that decides whether this is shipped. `platypus_fit()` and `evaluate()` reach
  # the instance engine through `build_engine()` and `engine.evaluate(split)`, which
  # dispatch on the task tag - so they *should* work, and §4 has an entry about what a
  # should is worth. This runs one.
  skip_if_no_engine()
  root <- tiny_instance_dataset()
  fit <- platypus_fit(tiny_instance_spec(root), num_workers = 0)
  expect_s3_class(fit, "platypus_fit")
  expect_identical(fit$task, "instance_segmentation")

  scored <- evaluate(fit)
  # A row per (model, decoding) rather than per model, which is the shape this task's table
  # has and the semantic one's does not - so a column check is what says the instance
  # engine answered rather than something that merely returned a data frame.
  expect_true(all(c("model", "decode", "average_precision") %in% names(scored)))
  # `foreground_dice` arrived with the pin at 0.8.0a22 and is asserted here rather than left
  # to arrive unnoticed: it is the mask column this table can be read *across* models, where
  # the `dice` beside it is a mean over the class channels a head has - three for `rim` and
  # two for `flows` - and reading that one across two models is the defect it was added for
  # (`pyplatypus#222`). One number per model, so it is the same on every row of one.
  expect_true("foreground_dice" %in% names(scored))
  expect_identical(length(unique(scored$foreground_dice)), 1L)
  expect_true(all(scored$foreground_dice >= 0 & scored$foreground_dice <= 1))
  expect_gt(nrow(scored), 1L)
  expect_true("connected_components" %in% scored$decode)
  expect_true(all(scored$model == "tiny"))
  # This model left `decode` unset, so the pair it derives is the signal's own decoding plus
  # the yardstick. The comment here said the yardstick is in the table *whether or not
  # anybody asked for it*, which is the claim `pyplatypus#225` corrected in three places on
  # the engine side and is wrong in the same way here: a model that writes its own `decode`
  # list gets the list it wrote.
  expect_setequal(scored$decode, c("nearest_seed", "connected_components"))
})

test_that("the fixture's objects touch, which is what makes it a fixture for this", {
  # Guarding the fixture rather than the code, because a fixture whose objects never touch
  # would make every row of the table above identical and the test would still pass. The
  # engine reads the two files as one label map; two values that share a seam are what the
  # separation signal exists to tell apart.
  skip_if_no_engine()
  root <- tiny_instance_dataset(n = 1)
  reticulate::py_run_string(sprintf("
import numpy as np, pathlib
from PIL import Image
masks = sorted((pathlib.Path(%s) / 'sample_00' / 'masks').glob('*.png'))
arrays = [np.array(Image.open(m)) > 0 for m in masks]
r_objects = len(arrays)
# Touching: one object's pixels are adjacent to the other's, so a connected-components read
# of their union finds one region where the truth has two.
union = np.logical_or(*arrays)
from scipy import ndimage
r_regions = int(ndimage.label(union)[1])
", shQuote(root)))
  expect_identical(reticulate::py$r_objects, 2L)
  expect_identical(reticulate::py$r_regions, 1L)
})

# --- `predict()` brings the objects back ------------------------------------------------
#
# This refused by name until `#103`, and the refusal was right for as long as the bridge had
# no call that returned a label map. The refusal's own test is replaced rather than kept
# beside the new behaviour, because a test asserting the old message would now be asserting
# that the feature is absent.
#
# What is still refused, and for reasons rather than for lack of code, is below: `space`,
# because resampling a label map interpolates between object numbers, and
# `type = "probability"`, because an instance model's vector channels are not probabilities.

test_that("predict() returns one label map per case, named by the case", {
  skip_if_no_engine()
  root <- tiny_instance_dataset(n = 2)
  fit <- platypus_fit(tiny_instance_spec(root), num_workers = 0)
  maps <- predict(fit, split = "validation")

  expect_type(maps, "list")
  expect_length(maps, 2L)
  # Named rather than ordered. The engine's own list is unnamed, and anything pairing two
  # sequences by position is one dropped batch away from naming the wrong picture - which is
  # the reason `predict_stream` exists on the semantic side.
  expect_true(all(nzchar(names(maps))))
  expect_identical(names(maps), unique(names(maps)))
  for (one in maps) {
    expect_identical(length(dim(one)), 2L)
    expect_type(as.vector(one), "integer")
    expect_gte(min(one), 0L)
  }
})

test_that("the names are the keys evaluate_cases() reports, not positions", {
  # The pairing this is worth having: if the names came from somewhere else than the cases
  # the engine scores, a figure would be labelled with one picture's key and drawn from
  # another's pixels, and nothing in either object would say so.
  skip_if_no_engine()
  root <- tiny_instance_dataset(n = 2)
  fit <- platypus_fit(tiny_instance_spec(root), num_workers = 0)
  maps <- predict(fit, split = "validation")
  # `case` here rather than `key`: an instance case table names the column `case`, which is
  # what the engine's own rows call it, and a test written against `key` passed `NULL` into
  # `expect_setequal` and failed for the instrument's reason rather than the pairing's.
  scored <- evaluate_cases(fit, split = "validation")
  expect_setequal(names(maps), scored$case)
})

test_that("`decode` picks the decoding and an unknown one is refused by name", {
  skip_if_no_engine()
  root <- tiny_instance_dataset(n = 2)
  spec <- tiny_instance_spec(
    root,
    decode = list(decode_connected_components(), decode_watershed())
  )
  fit <- platypus_fit(spec, num_workers = 0)
  expect_length(predict(fit, split = "validation", decode = "watershed"), 2L)
  expect_error(predict(fit, split = "validation", decode = "follow_flows"),
               "does not decode")
})

test_that("`decode` is refused on a fit that decodes nothing", {
  skip_if_no_engine()
  root <- tiny_dataset(n = 2)
  fit <- platypus_fit(tiny_spec(root), num_workers = 0)
  expect_error(predict(fit, split = "validation", decode = "watershed"),
               "only an instance model")
})

test_that("`space` is refused on an instance fit, and the reason is the label map", {
  # Not "unsupported": resampling a label map interpolates between object numbers, so
  # object 3 beside object 5 comes back with a rim of object 4. A refusal that said only
  # "not supported" would read as a gap somebody might fill.
  skip_if_no_engine()
  root <- tiny_instance_dataset(n = 2)
  fit <- platypus_fit(tiny_instance_spec(root), num_workers = 0)
  expect_error(predict(fit, split = "validation", space = "source"),
               "interpolates between object numbers")
})

test_that("`type = \"probability\"` is refused and `\"channels\"` is what it means", {
  skip_if_no_engine()
  root <- tiny_instance_dataset(n = 2)
  fit <- platypus_fit(tiny_instance_spec(root), num_workers = 0)
  expect_error(predict(fit, split = "validation", type = "probability"),
               "not all probabilities")
  channels <- predict(fit, split = "validation", type = "channels")
  # Stacked, channels-last, and as many channels as the head has - three for `rim`:
  # background, interior and the rim band.
  expect_identical(length(dim(channels)), 4L)
  expect_identical(dim(channels)[[1]], 2L)
  expect_identical(dim(channels)[[4]], 3L)
})

test_that("`type = \"channels\"` is refused where the channels are probabilities", {
  skip_if_no_engine()
  root <- tiny_dataset(n = 2)
  fit <- platypus_fit(tiny_spec(root), num_workers = 0)
  expect_error(predict(fit, split = "validation", type = "channels"),
               "ask for `type = \"probability\"`")
})

test_that("a predicted map draws and measures without leaving R", {
  # §4: a feature is not shipped until something has used it the way a user reaches it. The
  # way a user reaches this is predict, then draw, then measure - and the three were built
  # in two pull requests, so the join is the thing neither of them proved.
  skip_if_no_engine()
  root <- tiny_instance_dataset(n = 2)
  fit <- platypus_fit(tiny_instance_spec(root), num_workers = 0)
  maps <- predict(fit, split = "validation")
  one <- maps[[1]]
  image <- array(0.5, dim = c(dim(one), 3L))
  drawn <- overlay_instances(image, one)
  expect_identical(dim(drawn), c(dim(one), 3L))
  sizes <- instance_sizes(one, spacing = c(0.25, 0.25))
  expect_identical(names(sizes), c("object", "voxels", "area_mm2"))
  expect_identical(nrow(sizes), length(setdiff(unique(as.vector(one)), 0L)))
})
