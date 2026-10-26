# The pair for `maju116/pyplatypus#270`, which put every physical-unit measurement in the
# engine - and the receipt for the one R function that forwards to it.
#
# **Two implementations on purpose, and the rule is where the line falls.** A measurement that
# is *arithmetic* stays in R: `mask_volume()` and `instance_sizes()` are a count times a
# product, and making them cross would buy speed - 0.035 s against 0.341 s on a
# 512 x 512 x 300 label map - with the engine's 5 GB first call, on functions a reader can
# verify by eye. A measurement that needs a *library* crosses: `ellipse_measure()` wants
# connected components, hole filling and an eigendecomposition, and reimplementing those here
# would be a second implementation rather than a second copy of two lines.
#
# Forwarding the first two was written, measured and reverted. What settled it was not the
# speed but `R CMD check`: it runs examples, CRAN has no Python, and forwarding would have put
# `mask_volume()`'s page into `\dontrun{}` - which is how `volume_info()`'s page already
# reads, and the right shape for `ellipse_measure()`, and the wrong shape for arithmetic.
#
# So this file is two things. For the two that stayed, it is a **pair** in CLAUDE.md §3F's
# sense: R's answer against the engine's own, through reticulate, on the same arrays, with a
# positive control - because two implementations agreeing on zero is not agreement. For
# `ellipse_measure()` it is a **receipt**: there is one implementation and what can go wrong
# is the forward.

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

test_that("ellipse_measure reads its foreground by class and not by anything above zero", {
  skip_if_no_engine()
  py <- engine_measure()

  # A `which.max` map: background is 1, not 0. Reading the foreground as `> 0` - which is
  # right for the engine's own `argmax` masks - makes every pixel of this one foreground,
  # and the measured ellipse becomes the whole image. That is the trap `class` exists for,
  # and it is asserted rather than described: measured, 459.8 mm against 158.8, which is 2.9
  # times. The whole frame is 201 x 301 pixels of 0.5 mm, and the second moments of a filled
  # rectangle of side L give a semi-axis of L / sqrt(3), so that number is arithmetic rather
  # than an observation - 86.9 by 58.0 mm, whose perimeter is 459.8.
  rows <- matrix(rep(seq_len(201), 301), nrow = 201)
  columns <- matrix(rep(seq_len(301), each = 201), nrow = 201)
  mask <- ifelse(((columns - 150) / 60)^2 + ((rows - 100) / 40)^2 <= 1, 2L, 1L)
  expect_identical(sum(mask == 1L) > 0L, TRUE)

  got <- ellipse_measure(mask, spacing = c(0.5, 0.5))
  expect_equal(got$circumference, py$ellipse_circumference(mask == 2L, spacing = c(0.5, 0.5)),
               tolerance = 1e-12)
  expect_equal(c(got$major, got$minor),
               as.numeric(py$ellipse_axes(mask == 2L, spacing = c(0.5, 0.5))),
               tolerance = 1e-12)

  # The arithmetic by hand as well, because agreeing with the engine says the forward works
  # and not that the number is a circumference: semi-axes of 60 and 40 pixels on half
  # millimetre pixels are 30 mm and 20 mm, and Ramanujan puts their perimeter at 158.8 mm.
  expect_equal(got$major, 30, tolerance = 0.02)
  expect_equal(got$minor, 20, tolerance = 0.02)
  expect_equal(got$circumference, 158.8, tolerance = 0.5)

  # And the control for the trap: measuring everything above zero gives a different number,
  # so the `class` argument is doing work rather than being decoration.
  everything <- py$ellipse_circumference(mask > 0L, spacing = c(0.5, 0.5))
  expect_equal(everything, 459.8, tolerance = 0.5)
  expect_gt(everything, 2.5 * got$circumference)
})

test_that("ellipse_measure in pixels is the same shape measured without a spacing", {
  skip_if_no_engine()
  rows <- matrix(rep(seq_len(201), 301), nrow = 201)
  columns <- matrix(rep(seq_len(301), each = 201), nrow = 201)
  mask <- ifelse(((columns - 150) / 60)^2 + ((rows - 100) / 40)^2 <= 1, 2L, 1L)

  pixels <- ellipse_measure(mask)
  millimetres <- ellipse_measure(mask, spacing = c(0.5, 0.5))
  # Square pixels, so this one scaling is exact - which is the only case where it is. The
  # engine scales the coordinates rather than the answer, because an ellipse perimeter is
  # not separable in its axes; equal sides is where the two agree to the last digit.
  expect_equal(millimetres$circumference, pixels$circumference * 0.5, tolerance = 1e-12)

  # Anisotropic pixels, where no single factor works: 0.5 x 0.25 makes the 60 x 40 pixel
  # ellipse 30 mm by 10 mm, and neither scaling of the pixel answer lands there.
  thin <- ellipse_measure(mask, spacing = c(0.25, 0.5))
  expect_equal(thin$major, 30, tolerance = 0.05)
  expect_equal(thin$minor, 10, tolerance = 0.05)
  expect_gt(abs(thin$circumference - pixels$circumference * 0.5), 10)
  expect_gt(abs(thin$circumference - pixels$circumference * 0.25), 10)
})

test_that("ellipse_measure refuses a stack and a spacing of the wrong length", {
  skip_if_no_engine()
  expect_error(ellipse_measure(array(1L, dim = c(2, 8, 8))), "two dimensions")
  expect_error(ellipse_measure(matrix(1L, 8, 8), spacing = c(1, 1, 1)), "two positive")
  expect_error(ellipse_measure(matrix(1L, 8, 8), spacing = c(0, 1)), "two positive")
})

test_that("a class nothing matches measures nothing rather than failing", {
  skip_if_no_engine()
  # A model that found no head has measured no head. Raising here would make a loop over a
  # split fail on its worst case instead of reporting it.
  empty <- ellipse_measure(matrix(1L, 40, 40), spacing = c(0.5, 0.5))
  expect_identical(c(empty$major, empty$minor, empty$circumference), c(0, 0, 0))
})

test_that("the measurements that stay in R do not reach the engine", {
  # The constraint the header is about, as a check rather than a paragraph. `R CMD check`
  # runs every example not wrapped in `\dontrun{}`, CRAN has no Python, and CRAN is where
  # this package is going - so a function documented with a runnable example must not touch
  # the bridge. Reading the body is the right instrument: *calling* these proves nothing,
  # because this machine has the engine, which is exactly how the forwarding version passed
  # `R CMD check` here before it was reverted.
  #
  # Asked of the installed namespace rather than of the Rd files, because `tools::Rd_db()`
  # reads installed help and answers "corrupt" whenever the sources have moved since the
  # last install - which is a question about this working copy and not about the package.
  reaches_engine <- function(name) {
    body <- paste(deparse(get(name, envir = asNamespace("rplatypus"))), collapse = " ")
    grepl("shim()", body, fixed = TRUE) || grepl("engine()", body, fixed = TRUE)
  }

  for (name in c("mask_volume", "instance_sizes", "mask_coverage")) {
    expect_false(reaches_engine(name), info = paste(name, "now reaches the engine, so its ",
                                                    "example needs Python and its page has ",
                                                    "to go into \\dontrun{}"))
  }

  # The control, without which the predicate above could be broken and silent: the
  # measurements that DO cross say so, and their pages are guarded for that reason.
  for (name in c("ellipse_measure", "instance_shapes")) {
    expect_true(reaches_engine(name), info = paste(name, "no longer reaches the engine"))
  }
})


test_that("instance_shapes forwards, and eccentricity is not spacing-free", {
  skip_if_no_engine()

  # A receipt rather than a pair: there is one implementation and what can go wrong is the
  # forward. But the forward has a shape worth asserting - the key set changes with the rank
  # and with whether a spacing was given, and R builds its columns from the names the engine
  # sent rather than from its own guess about them.
  size <- 201
  centre <- (size + 1) / 2
  rows <- matrix(rep(seq_len(size), size), nrow = size)
  columns <- matrix(rep(seq_len(size), each = size), nrow = size)
  circle <- ifelse((rows - centre)^2 + (columns - centre)^2 <= 80^2, 1L, 0L)

  grid <- instance_shapes(circle)
  expect_identical(names(grid), c("object", "major_px", "minor_px", "eccentricity"))
  expect_identical(nrow(grid), 1L)
  expect_identical(grid$object, 1L)
  expect_equal(grid$eccentricity, 0, tolerance = 1e-9)

  # The trap the help page is written around, and the reason it is a test rather than a
  # sentence: a circle on anisotropic pixels IS an ellipse, and the grid cannot say so.
  stretched <- instance_shapes(circle, spacing = c(2, 1))
  expect_identical(names(stretched), c("object", "major_mm", "minor_mm", "eccentricity"))
  expect_equal(stretched$eccentricity, sqrt(1 - 0.25), tolerance = 5e-4)
  expect_equal(stretched$major_mm, 2 * grid$major_px, tolerance = 1e-9)

  # The other direction, without which the assertion above is satisfied by anything that
  # merely scales with `spacing`: a grid ellipse the spacing turns back into a circle.
  ellipse <- ifelse(((rows - centre) / 80)^2 + ((columns - centre) / 40)^2 <= 1, 1L, 0L)
  expect_equal(instance_shapes(ellipse)$eccentricity, 0.8667, tolerance = 5e-4)
  expect_equal(instance_shapes(ellipse, spacing = c(1, 2))$eccentricity, 0.0685,
               tolerance = 5e-3)

  # A volume: three axes, no eccentricity, because an ellipsoid has no single one.
  volume <- array(0L, dim = c(40, 40, 40))
  volume[11:30, 14:27, 16:25] <- 1L
  solid <- instance_shapes(volume, spacing = c(1, 1, 1))
  expect_identical(names(solid), c("object", "major_mm", "middle_mm", "minor_mm"))
  expect_true(solid$major_mm > solid$middle_mm && solid$middle_mm > solid$minor_mm)

  # And the refusals are R's own, named for R's argument rather than arriving from Python.
  expect_error(instance_shapes(array(0L, dim = c(2, 2, 2, 2))), "two dimensions")
  expect_error(instance_shapes(matrix(0L, 4, 4), spacing = c(1, 1, 1)), "2 positive numbers")
})
