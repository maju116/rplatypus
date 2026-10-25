# The receipt for `maju116/pyplatypus#270`, which moved three measurements into the engine.
#
# `mask_volume()` and `instance_sizes()` kept their names, their arguments and their
# refusals, and lost their arithmetic: it is `pyplatypus.measure`'s now. Every other test in
# this suite asserts what those functions answer, which is what makes the deletion *appear*
# behaviour-preserving. This file is what makes it provable - R's answer against the engine's
# own, through reticulate, on the same arrays.
#
# This is a receipt rather than a pair, in the sense of CLAUDE.md §3F: the drift it guards is
# one-directional, because there is now exactly one implementation and R forwards to it. What
# it would catch is the forward itself going wrong - a class number translated by somebody who
# read the two conventions and decided they disagree, a unit named after the wrong rank, a size
# column appearing with no spacing. Measured: of seven mutations of the two forwards, five are
# caught here and by nothing else, the control that removes the measurement among them.
#
# **The two that are not caught are not defects, and that is worth writing down rather than
# fixing.** Reversing `spacing` before sending it changes nothing, because a volume and an area
# are the product of all the sides and a product does not care about their order. The only
# measurement where the order matters is the ellipse, which is the engine's - and that batch
# found a gap in the engine's own suite rather than in this one: a *circle* cannot tell
# `(row, column)` from `(column, row)` either, so the claim is pinned there on an elongated
# mask now.

engine_measure <- function() {
  reticulate::import("pyplatypus")
}

test_that("mask_volume answers what the engine answers, on R's own class numbering", {
  skip_if_no_engine()
  py <- engine_measure()

  # A `which.max` map, deliberately not half and half: the first check written for this
  # agreed for the wrong reason on an array of two equal halves, which is §4's "a number
  # that agrees is not evidence" inside the instrument written to settle the question.
  mask <- array(1L, dim = c(10, 10, 4))
  mask[3:6, 3:6, 2:3] <- 2L
  expect_identical(sum(mask == 2L), 32L)
  expect_identical(sum(mask == 1L), 368L)

  for (spacing in list(c(1, 1, 1), c(2, 2, 5), c(0.7, 0.7, 3.2))) {
    for (class in c(1L, 2L)) {
      expect_equal(
        mask_volume(mask, spacing = spacing, class = class),
        py$mask_volume(mask, spacing = spacing, class_index = class),
        tolerance = 1e-12,
        info = paste(paste(spacing, collapse = "/"), "class", class)
      )
    }
  }

  # The positive control, because two implementations agreeing on zero is not agreement:
  # the numbers compared above are different from each other and none of them is zero.
  volumes <- c(
    mask_volume(mask, spacing = c(2, 2, 5), class = 1L),
    mask_volume(mask, spacing = c(2, 2, 5), class = 2L),
    mask_volume(mask, spacing = c(1, 1, 1), class = 2L)
  )
  expect_true(all(volumes > 0))
  expect_identical(length(unique(volumes)), 3L)
})

test_that("instance_sizes answers what the engine answers, column by column", {
  skip_if_no_engine()
  py <- engine_measure()

  labels <- matrix(0L, nrow = 8, ncol = 8)
  labels[2:4, 2:4] <- 1L
  labels[6:7, 6:8] <- 4L     # a gap in the numbering, which is three objects minus one
  sizes <- instance_sizes(labels, spacing = c(0.5, 0.25))
  rows <- py$instance_sizes(labels, spacing = c(0.5, 0.25))

  expect_identical(nrow(sizes), length(rows))
  expect_identical(sizes$object, vapply(rows, function(r) as.integer(r$object), integer(1)))
  expect_identical(sizes$voxels, vapply(rows, function(r) as.integer(r$voxels), integer(1)))
  expect_equal(sizes$area_mm2, vapply(rows, function(r) as.numeric(r$area_mm2), numeric(1)),
               tolerance = 1e-12)
  # And an anisotropic spacing is the control for the order the two sides agree on: with
  # 0.5 x 0.25 the area is 0.125 per pixel, and a transposed pair would answer the same, so
  # the number is asserted by hand as well.
  expect_equal(sizes$area_mm2, c(9, 6) * 0.125, tolerance = 1e-12)

  volume <- array(0L, dim = c(4, 4, 4))
  volume[1:2, 1:2, 1:2] <- 3L
  rows <- py$instance_sizes(volume, spacing = c(2, 2, 5))
  expect_equal(instance_sizes(volume, spacing = c(2, 2, 5))$volume_ml,
               vapply(rows, function(r) as.numeric(r$volume_ml), numeric(1)),
               tolerance = 1e-12)
  expect_equal(instance_sizes(volume, spacing = c(2, 2, 5))$volume_ml, 0.16)
})

test_that("volume_info's voxel_ml is the same millilitre as mask_volume's", {
  skip_if_no_volumes()
  root <- tiny_volume_dataset(cases = 1, spacing = c(2, 2, 5))
  scan <- list.files(root, pattern = "ct[.]nii[.]gz$", recursive = TRUE, full.names = TRUE)

  info <- volume_info(scan)
  spacing <- c(info$spacing_1, info$spacing_2, info$spacing_3)

  # `voxel_ml` is computed in the shim rather than by the engine, and deliberately: it is a
  # restatement of `spacing` rather than a measurement of a mask, so there is nothing in
  # `pyplatypus.measure` that it would call. What it does share with `mask_volume()` is the
  # convention that the divisor is 1000, and a convention in two places with nothing holding
  # them together is the shape §3F is a list of. This holds them: one voxel of foreground
  # must measure exactly one voxel's worth of millilitres.
  mask <- array(1L, dim = c(info$shape_1, info$shape_2, info$shape_3))
  mask[1, 1, 1] <- 2L
  expect_equal(mask_volume(mask, spacing = spacing, class = 2L), info$voxel_ml,
               tolerance = 1e-12)

  mask[2, 1, 1] <- 2L
  expect_equal(mask_volume(mask, spacing = spacing, class = 2L), 2 * info$voxel_ml,
               tolerance = 1e-12)
  # The control: a voxel here is not one cubic millimetre, so the two would not agree by
  # accident on a spacing of all ones.
  expect_false(isTRUE(all.equal(info$voxel_ml, 0.001)))
})
