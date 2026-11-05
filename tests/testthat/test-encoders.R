# A backbone as the contracting path.
#
# The measurement behind this feature says transfer does not beat the built-in encoder on
# any of the three datasets tried, so most of what is worth testing is that asking for one
# reaches the engine intact, and that a refusal arrives as a sentence rather than a
# traceback. Those parts need no Python at all.

test_that("the four encoder fields are absent unless asked for", {
  # The point of the NULL default, and the reason an older engine keeps working for
  # everyone who is not asking: compact() drops the key entirely.
  plain <- u_net("m", input_shape = c(256, 256))
  # Five since `normalise` arrived in 0.8.0a65; it was missing from this list, which is the
  # same omission one level up as the forward `maju116/rplatypus#278` is about.
  for (field in c("encoder", "pretrained", "normalise", "freeze_encoder",
                  "encoder_learning_rate")) {
    expect_null(plain[[field]], info = field)
  }

  config <- rplatypus:::compact(plain)
  expect_false("encoder" %in% names(config))
  expect_false("pretrained" %in% names(config))
})

test_that("asking for a backbone puts it in the request", {
  model <- u_net("m", input_shape = c(256, 256), encoder = "resnet34", pretrained = TRUE,
                 freeze_encoder = 5, encoder_learning_rate = 1e-4)
  expect_identical(model$encoder, "resnet34")
  expect_true(model$pretrained)
  expect_identical(model$freeze_encoder, 5L)
  expect_identical(model$encoder_learning_rate, 1e-4)

  config <- rplatypus:::compact(model)
  expect_true(all(c("encoder", "pretrained", "freeze_encoder", "encoder_learning_rate")
                  %in% names(config)))
})

test_that("freeze_encoder crosses as an integer", {
  # pydantic wants an int, and R's 5 is a double. Checked because the value survives the
  # crossing either way and only fails at the far end.
  model <- u_net("m", input_shape = c(256, 256), encoder = "resnet34", freeze_encoder = 5)
  expect_type(model$freeze_encoder, "integer")
})

test_that("every architecture takes a backbone", {
  for (make in list(u_net, u_net_plus_plus, res_u_net, linknet)) {
    model <- make("m", input_shape = c(256, 256), encoder = "resnet34")
    expect_identical(model$encoder, "resnet34")
  }
})

test_that("the bridge always asks for both extras, on either route", {
  requirement <- rplatypus:::.platypus_requirement()

  # Both extras, every time. Leaving one out is how `weights = "dsbowl-unet"` shipped
  # unusable from R: the pin's test surface is the package, never its extras.
  expect_match(requirement, "hub")
  expect_match(requirement, "encoders")

  # This used to skip whenever PLATYPUS_ENGINE_PATH was set, because the development route
  # returned a bare path with no extras at all. That was the defect rather than a reason to
  # skip: the blood-cell vignette could not be precomputed, since `weights = "bccd-yolo3"`
  # found no huggingface_hub in the environment the development route builds. A development
  # route that differs from the installed one hides exactly the class of problem it exists
  # to surface, so now both carry the extras and both are checked here.
  if (grepl("^/", requirement)) {
    expect_true(dir.exists(sub("\\[.*$", "", requirement)))
  } else {
    expect_match(requirement, paste0("==", rplatypus:::pyplatypus_version), fixed = TRUE)
  }
})


# --- against a real engine -------------------------------------------------------------

test_that("the engine accepts a backbone and reports it back", {
  skip_if_no_encoders()
  spec <- platypus_spec(
    data = segmentation_data("a", "b", colormap = binary_colormap),
    models = list(u_net("m", input_shape = c(64, 64), encoder = "resnet34",
                        pretrained = FALSE, freeze_encoder = 2)),
    check_paths = FALSE
  )
  model <- as.list(spec)$models[[1]]
  expect_identical(model$encoder, "resnet34")
  expect_identical(model$freeze_encoder, 2L)
})

test_that("a backbone with a 3D input_shape is refused, with the reason", {
  skip_if_no_encoders()
  # Caught while the specification is read, before anything is downloaded or a GPU touched.
  expect_error(
    platypus_spec(
      data = segmentation_data("a", "b", labels = c(0, 1)),
      models = list(u_net("m", input_shape = c(64, 64, 32), encoder = "resnet34")),
      check_paths = FALSE
    ),
    "ImageNet is images"
  )
})

test_that("pretrained without a backbone is refused", {
  skip_if_no_encoders()
  expect_error(
    platypus_spec(
      data = segmentation_data("a", "b", colormap = binary_colormap),
      models = list(u_net("m", input_shape = c(64, 64), pretrained = TRUE)),
      check_paths = FALSE
    ),
    "needs `encoder`"
  )
})

test_that("the backbones the documentation names are the ones that work", {
  skip_if_no_timm()
  # The help page lists families rather than a generated list, so this is what keeps the
  # list honest. A name that stopped working would otherwise be found by a user.
  for (name in c("resnet34", "efficientnet_b0", "mobilenetv3_large_100", "vgg16")) {
    built <- reticulate::import("pyplatypus.models.encoders")$PretrainedEncoder(
      name, in_channels = 3L, blocks = 4L, filters = 16L
    )
    expect_length(built$channels, 5L)
  }
})

test_that("a patch-based backbone is refused by name, as documented", {
  skip_if_no_timm()
  encoders <- reticulate::import("pyplatypus.models.encoders")
  expect_error(
    encoders$PretrainedEncoder("convnext_tiny", in_channels = 3L, blocks = 4L,
                               filters = 16L),
    "convnext_tiny"
  )
})

test_that("a model with a backbone trains and predicts at the input size", {
  skip_if_no_timm()
  root <- tiny_dataset(n = 4, size = 64)
  spec <- platypus_spec(
    data = segmentation_data(root, root, colormap = binary_colormap),
    models = list(u_net("m", input_shape = c(64, 64), blocks = 4, filters = 8,
                        encoder = "resnet34", epochs = 1, batch_size = 2))
  )
  fit <- platypus_fit(spec)
  masks <- predict(fit, split = "validation")
  # Level 0 of a backbone is at half resolution; the decoder's head sits on level 0, so a
  # mask the size of the input is the proof that the full-resolution stage is in place.
  expect_identical(dim(masks)[2:3], c(64L, 64L))
})


test_that("normalise reaches the request from every constructor that takes an encoder", {
  # `maju116/rplatypus#278`, and the finding is that nothing held this. One line per
  # constructor forwards the field - `normalise = normalise` - and deleting either of the
  # two sites in R left the whole suite at 1948 passed. The engine's own halves could be
  # deleted the same way (`maju116/pyplatypus#385`), and the result is the silence the
  # fingerprint exists to refuse: a record saying the input was normalised for a network
  # that never normalised it.
  #
  # Read off the request rather than from a fit: a fit would need the engine and a
  # backbone, and the question is whether the key arrives.
  segmentation <- list(u_net = u_net, u_net_plus_plus = u_net_plus_plus,
                       res_u_net = res_u_net, linknet = linknet)
  for (name in names(segmentation)) {
    make <- segmentation[[name]]
    asked <- make("m", input_shape = c(256, 256), encoder = "resnet34",
                  pretrained = FALSE, normalise = TRUE)
    expect_true(asked$normalise, info = name)
    expect_true("normalise" %in% names(rplatypus:::compact(asked)), info = name)

    # And FALSE is a value the caller gave rather than nothing, so it must survive
    # `compact()` too - the trap `group_by` is documented for.
    refused <- make("m", input_shape = c(256, 256), encoder = "resnet34", normalise = FALSE)
    expect_false(refused$normalise, info = name)
    expect_true("normalise" %in% names(rplatypus:::compact(refused)), info = name)
  }

  classification <- classifier("c", input_shape = c(224, 224), encoder = "resnet34",
                               pretrained = FALSE, normalise = TRUE)
  expect_true(classification$normalise)
  expect_true("normalise" %in% names(rplatypus:::compact(classification)))
})
