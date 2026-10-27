# Every default this package writes down is one the engine also writes down.
#
# The loss and metric constructors restate the engine's defaults in their own
# signatures - `metric_dice(smooth = 1, include_background = TRUE)` and so on - and when this
# was first measured all thirteen agreed exactly. That was a state and not a guarantee:
# nothing compared them, and nothing would have said when they drifted.
#
# `clDice` is why it stopped being hypothetical. It is the first metric whose
# `include_background` differs from its siblings - FALSE, because the background's skeleton
# lies inside the background by construction and the class scores 1 whatever happened - and a
# default copied from the row above would have silently contradicted the engine.
#
# The models were fixed differently, in `JOURNAL.md` §4aa: their R defaults became NULL and
# the engine supplies them, so a weights file that knows better can be heard. That cannot be
# done here without losing the signature as documentation, so these are compared instead.

test_that("every loss and metric default matches the engine's", {
  skip_if_no_engine()

  schema <- rplatypus:::engine()$spec_schema()$`$defs`
  theirs <- list()
  for (key in names(schema)) {
    props <- schema[[key]]$properties
    tag <- props$name$const %||% props$name$enum[[1]] %||% NULL
    if (is.null(tag)) next
    family <- if (grepl("Metric$", key)) "metric_" else if (grepl("Loss$", key)) "loss_" else next
    theirs[[paste0(family, tag)]] <- props
  }

  ours <- grep("^(loss|metric)_", getNamespaceExports("rplatypus"), value = TRUE)
  expect_gt(length(ours), 10)

  for (name in sort(ours)) {
    props <- theirs[[name]]
    expect_false(is.null(props), info = paste(name, "names nothing the engine accepts"))

    arguments <- formals(get(name, asNamespace("rplatypus")))
    for (argument in names(arguments)) {
      # The empty symbol has to be recognised *before* it is bound to a name: binding it and
      # then asking `is.null()` raises "argument is missing, with no default", which is
      # exactly how this loop broke on the day `metric_surface_dice(tau)` arrived. The test
      # had been green for every release because no constructor in either family had a
      # required argument - §4's passing test whose fixture never contained the case.
      if (identical(arguments[[argument]], quote(expr = ))) next
      ours_default <- arguments[[argument]]
      # R sends nothing for an unset argument, so the engine's default applies and there is
      # nothing to compare - which is the arrangement the model constructors all use.
      if (is.null(ours_default)) next
      theirs_default <- props[[argument]]$default
      expect_false(
        is.null(theirs_default),
        info = sprintf("%s(%s=) has a default here and none in the engine", name, argument)
      )
      expect_equal(
        eval(ours_default), theirs_default,
        info = sprintf("%s(%s=)", name, argument)
      )
    }
  }
})

test_that("the two mask metrics whose background default differs are those two, on both sides", {
  # This test was called "clDice is the one" until the pin moved to 0.8.0a26, and it would
  # have gone on passing while its own title was false: it asserted FALSE for clDice and
  # TRUE for the three overlap metrics and said nothing about a fifth metric. So the
  # partition is asserted rather than one side of it - every metric is in exactly one of the
  # two groups, and a new one has to be put in a group here before this passes.
  skip_if_no_engine()

  ours <- sort(grep("^metric_", getNamespaceExports("rplatypus"), value = TRUE))

  # The label metrics are a third group and they are DERIVED rather than listed: a metric
  # that scores one label per image has no background class to leave in or out, so it has
  # no such argument at all. Read off the engine's own listing, so a fifth classification
  # metric arriving upstream lands in this group by itself - and fails here if R has no
  # constructor for it, which is the half this comparison adds.
  label <- paste0("metric_", available_metrics("classification")$name)
  expect_gt(length(label), 0)
  expect_identical(setdiff(label, ours), character(0),
                   info = "the engine lists a label metric R has no constructor for")
  for (name in label) {
    expect_false("include_background" %in% names(formals(get(name, asNamespace("rplatypus")))),
                 info = sprintf("%s takes `include_background` and has no background", name))
  }

  masks <- setdiff(ours, label)
  background_left_out <- c("metric_cldice", "metric_surface_dice")
  expect_identical(
    sort(masks),
    sort(c(background_left_out, "metric_dice", "metric_iou", "metric_tversky")),
    info = "a mask metric arrived: decide which group its `include_background` default is in"
  )

  for (name in masks) {
    default <- eval(formals(get(name, asNamespace("rplatypus")))$include_background)
    expect_identical(default, !name %in% background_left_out, info = name)
  }

  # And the engine agrees for both of them, which is the half R cannot assert about itself.
  defs <- rplatypus:::engine()$spec_schema()$`$defs`
  expect_false(defs$ClDiceMetric$properties$include_background$default)
  expect_false(defs$SurfaceDiceMetric$properties$include_background$default)
  expect_true(defs$DiceMetric$properties$include_background$default)
})

test_that("the one required argument in either family is `tau`, and the engine requires it", {
  # Every other loss and metric constructor can be called bare, because every one of their
  # arguments has a default on both sides. `metric_surface_dice()` cannot, and that is the
  # point of it: a tolerance belongs to the structure. Asserted as a property of the whole
  # family so that a second required argument has to be noticed here.
  skip_if_no_engine()

  ours <- grep("^(loss|metric)_", getNamespaceExports("rplatypus"), value = TRUE)
  required <- character(0)
  for (name in sort(ours)) {
    arguments <- formals(get(name, asNamespace("rplatypus")))
    for (argument in names(arguments)) {
      if (identical(arguments[[argument]], quote(expr = ))) {
        required <- c(required, sprintf("%s(%s)", name, argument))
      }
    }
  }
  expect_identical(required, "metric_surface_dice(tau)")

  # The engine's schema is where "required" is the authority, and R's missing default is
  # only a copy of it. `required` there is the list of fields with no default.
  defs <- rplatypus:::engine()$spec_schema()$`$defs`
  expect_true("tau" %in% unlist(defs$SurfaceDiceMetric$required))
  expect_false("smooth" %in% unlist(defs$SurfaceDiceMetric$required))
})
