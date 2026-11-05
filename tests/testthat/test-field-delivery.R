# Every model field a constructor takes has to appear in the request it assembles.
#
# `maju116/rplatypus#281`, and the shape rather than the list is the point. The eleventh
# review pass deleted one key at a time from `segmentation_model`'s and `classifier`'s
# `compact(list(...))` and found **nine of twenty survive the whole suite**:
# `block_width`, `batch_normalization`, `separable_conv`, `spatial_dropout`, `upsample`,
# `deep_supervision`, `activation` and `initialiser` on the segmentation side, and
# `pretrained` on the classifier.
#
# **Six of those nine now have a guard on the engine's side** (`maju116/pyplatypus#386`),
# and it cannot see them: a guard that checks the engine builds what the request says is
# blind to a field that never arrives. `u_net(batch_normalization = FALSE)` would send
# nothing and the engine would build with batch normalisation, correctly, from its own
# default.
#
# So this is ONE enumerating test rather than nine, read off `formals()` for each
# constructor - which is the only shape under which a field added next month is covered
# without anybody remembering. Every survivor in both review passes was a read nobody
# enumerated, which is exactly what `#278`'s per-field `normalise` test could not prevent.

# Fields a constructor takes that are NOT model settings the engine reads from the request,
# each with the reason, so this list is a statement rather than a filter widened until green.
not_a_model_field <- c(
  name = "the model's own name, asserted by test-spec.R",
  input_shape = "shape-bearing; every spec test reads it back",
  n_class = "a data-level count the engine derives when it is absent",
  channels = "shape-bearing",
  loss = "a component, held by test-component-defaults.R",
  metrics = "a component list, held by test-component-defaults.R",
  optimizer = "a component",
  callbacks = "a component list",
  augmentation = "a component list",
  weights = "a path, held by test-weights.R",
  fit = "a flag the engine reads off the request, held by test-spec.R",
  separation = "instance-only, held by test-instances.R",
  decode = "instance-only, held by test-instances.R",
  splits = "tiling, held by test-spec.R",
  encoder = "a backbone name, held by test-encoders.R"
)
# `architecture`, `regions`, `classes_from` and `labels_from` stood here on the first run
# and no constructor takes any of them - `architecture` is set by the constructor itself
# and the other three are data-level namings. The staleness check below is what said so,
# which is the half of this test that earns its place: a list of exemptions nobody checks
# is a list that drifts away from the code it is about.

# A non-default for every field this does cover. `NULL` defaults mean anything is
# non-default; where the engine's own default is a value, the one here differs from it.
non_default <- list(
  blocks = 3L,
  filters = 16L,
  block_width = 3L,
  batch_normalization = FALSE,
  separable_conv = TRUE,
  spatial_dropout = FALSE,
  dropout = 0.5,
  activation = "gelu",
  initialiser = "glorot_uniform",
  upsample = TRUE,
  deep_supervision = TRUE,
  epochs = 3L,
  batch_size = 3L,
  pretrained = TRUE,
  normalise = TRUE,
  freeze_encoder = 2L,
  encoder_learning_rate = 1e-5,
  pooling = "max",
  head_dropout = 0.5
)

constructors <- list(
  u_net = u_net, u_net_plus_plus = u_net_plus_plus,
  res_u_net = res_u_net, linknet = linknet, classifier = classifier
)

shape_for <- function(name) if (name == "classifier") c(224, 224) else c(256, 256)

test_that("every field a constructor takes is either enumerated here or named", {
  # The half that makes this an enumeration: a field added to a constructor next month is
  # not in `non_default` and not in `not_a_model_field`, so this is what fails.
  for (name in names(constructors)) {
    taken <- setdiff(names(formals(constructors[[name]])), "...")
    uncovered <- setdiff(taken, c(names(non_default), names(not_a_model_field)))
    said <- paste(name, "takes fields neither enumerated nor named:",
                  paste(uncovered, collapse = ", "))
    expect_identical(uncovered, character(0), info = said)
  }
  # And the exemptions are real rather than a list that drifted away from the code.
  all_taken <- unique(unlist(lapply(constructors, function(f) names(formals(f)))))
  stale <- setdiff(names(not_a_model_field), all_taken)
  said <- paste("not_a_model_field names arguments no constructor takes:",
                paste(stale, collapse = ", "))
  expect_identical(stale, character(0), info = said)
})

test_that("a non-default reaches the assembled request, every field and constructor", {
  for (name in names(constructors)) {
    make <- constructors[[name]]
    taken <- intersect(names(formals(make)), names(non_default))
    for (field in taken) {
      value <- non_default[[field]]
      args <- list("m", input_shape = shape_for(name))
      args[[field]] <- value
      # `pretrained`, `normalise` and the two encoder settings need a backbone to be
      # admissible at all, which is the companion mechanism the engine's own enumeration
      # carries for `spatial_dropout` and `separable_conv`.
      if (field %in% c("pretrained", "normalise", "freeze_encoder", "encoder_learning_rate")) {
        args$encoder <- "resnet34"
      }
      if (field == "deep_supervision") {
        if (name != "u_net_plus_plus") next
        args$blocks <- 3L
      }
      if (field == "normalise") args$pretrained <- FALSE

      asked <- do.call(make, args)
      request <- rplatypus:::compact(asked)
      dropped <- paste(name, "drops", field, "from the request it assembles")
      expect_true(field %in% names(request), info = dropped)
      sent <- if (field %in% names(request)) format(request[[field]]) else "nothing"
      wrong <- paste(name, "sends", field, "as", sent, "not", format(value))
      expect_equal(request[[field]], value, info = wrong)
    }
  }
})

test_that("a field left unset is absent, which is what makes the test above a reading", {
  # The control: every one of these is dropped by `compact()` when nobody asks, so the
  # assertion above is about the value arriving rather than about the key always being there.
  plain <- rplatypus:::compact(u_net("m", input_shape = c(256, 256)))
  for (field in c("dropout", "upsample", "deep_supervision", "encoder", "pretrained")) {
    expect_false(field %in% names(plain), info = field)
  }
})
