# `save_spec()` and `deterministic`, the two halves of 0.8.0a11 R had to take.
#
# The round trip is the test that matters, and not because the file parses. The engine writes
# the fields that were *set*, because a model given `weights` and no `architecture` adopts the
# architecture from the weights sidecar and the adoption fires on the field never having been
# set. A `save_spec` that wrote every resolved default would produce a file that looks like the
# original and quietly stops doing what the original did - and a parse test passes straight
# through that.

specification <- function(...) {
  platypus_spec(
    data = segmentation_data("train/", "valid/", colormap = binary_colormap),
    models = list(u_net("m", input_shape = c(32, 32))),
    check_paths = FALSE,
    ...
  )
}

test_that("a saved specification reads back as the same specification", {
  skip_if_no_engine()
  spec <- specification()
  path <- withr::local_tempfile(fileext = ".yaml")

  expect_identical(save_spec(spec, path), path)
  expect_true(file.exists(path))
  expect_identical(as.list(platypus_spec(path, check_paths = FALSE)), as.list(spec))
})

test_that("what was never set stays unset in the file", {
  skip_if_no_engine()
  path <- withr::local_tempfile(fileext = ".yaml")
  save_spec(specification(), path)
  written <- yaml::read_yaml(path)

  # The engine resolves 30 fields on this model. Writing them all is what would break the
  # adoption described at the top of this file, so the lean file is the contract.
  expect_lt(length(written$models[[1]]), 10)
  expect_false("loss" %in% names(written$models[[1]]))
  expect_false("optimizer" %in% names(written$models[[1]]))
  expect_false("epochs" %in% names(written$models[[1]]))

  # And the discriminators survive, or the file cannot be read back at all.
  expect_identical(written$task, "semantic_segmentation")
})

test_that("defaults = TRUE freezes the run and says so by being bigger", {
  skip_if_no_engine()
  lean <- withr::local_tempfile(fileext = ".yaml")
  frozen <- withr::local_tempfile(fileext = ".yaml")
  spec <- specification()
  save_spec(spec, lean)
  save_spec(spec, frozen, defaults = TRUE)

  expect_identical(length(yaml::read_yaml(frozen)$models[[1]]), 30L)
  expect_gt(length(yaml::read_yaml(frozen)$models[[1]]),
            length(yaml::read_yaml(lean)$models[[1]]))
  # Both still describe the same experiment once the engine has resolved them.
  expect_identical(
    as.list(platypus_spec(lean, check_paths = FALSE)),
    as.list(platypus_spec(frozen, check_paths = FALSE))
  )
})

test_that("a file that leaves the architecture to the weights keeps leaving it", {
  # The case platypus#120 was filed about, end to end through R: read a configuration that
  # names weights and no architecture, save it, and the architecture is still absent. With a
  # naive dump it would be written in, and the adoption could never fire again.
  skip_if_no_engine()
  source_path <- withr::local_tempfile(fileext = ".yaml")
  writeLines(c(
    "task: semantic_segmentation",
    "data:",
    "  train_path: train/",
    "  validation_path: valid/",
    "  colormap: [[0, 0, 0], [255, 255, 255]]",
    "models:",
    "  - name: m",
    "    input_shape: [32, 32]",
    "    weights: dsbowl-unet"
  ), source_path)

  spec <- platypus_spec(source_path, check_paths = FALSE)
  written_path <- withr::local_tempfile(fileext = ".yaml")
  save_spec(spec, written_path)
  written <- yaml::read_yaml(written_path)

  expect_identical(written$models[[1]]$weights, "dsbowl-unet")
  expect_false("architecture" %in% names(written$models[[1]]))
})

test_that("save_spec refuses what is not a specification", {
  expect_error(save_spec(list(), "x.yaml"), "platypus_spec")
  skip_if_no_engine()
  expect_error(save_spec(specification(), character(0)), "single file path")
})

test_that("R sends nothing the caller did not give, which the saved file shows", {
  # This test is the reason #148 exists: written on 2026-10-11 it asserted the *presence*
  # of `mode`, `subdirs`, `column_sep` and `shuffle` - four R-side defaults crossing the
  # bridge as values somebody chose - and it now asserts their absence. §3D: defaults live
  # in the engine, because an R-side default silences a schema or a weights file that knows
  # better.
  #
  # `architecture` stays, and is the legitimate case: in R the constructor *is* the
  # architecture (§3A), so `u_net()` naming it is correct. The cost is in ?save_spec.
  skip_if_no_engine()
  path <- withr::local_tempfile(fileext = ".yaml")
  save_spec(specification(), path)
  written <- yaml::read_yaml(path)

  expect_setequal(names(written$data), c("train_path", "validation_path", "colormap"))
  expect_setequal(names(written$models[[1]]), c("name", "input_shape", "architecture"))
})

test_that("deterministic is refused without a seed", {
  skip_if_no_engine()
  expect_error(specification(deterministic = TRUE), class = "platypus_error")
  expect_error(specification(deterministic = TRUE), "seed")
})

test_that("deterministic with a seed reaches the engine and is written", {
  skip_if_no_engine()
  spec <- specification(seed = 1, deterministic = TRUE)
  expect_true(as.list(spec)$deterministic)

  path <- withr::local_tempfile(fileext = ".yaml")
  save_spec(spec, path)
  written <- yaml::read_yaml(path)
  expect_true(written$deterministic)
  expect_identical(written$seed, 1L)
})

test_that("leaving deterministic unset sends nothing, so an older engine still works", {
  # §3D.3: a new option defaults to NULL and is dropped from the request. Asserted on the
  # saved file, which is the only place the difference between "false" and "not sent" shows.
  skip_if_no_engine()
  path <- withr::local_tempfile(fileext = ".yaml")
  save_spec(specification(seed = 1), path)
  expect_false("deterministic" %in% names(yaml::read_yaml(path)))
})
