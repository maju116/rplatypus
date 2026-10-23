# Volumes from R. The tests that matter are the ones about geometry: a mask written without
# the scan's affine is a file that opens and lies.

test_that("classes are named one way or the other, and the check costs no Python", {
  expect_error(segmentation_data("a", "b"), "exactly one of")
  expect_error(
    segmentation_data("a", "b", colormap = binary_colormap, labels = c(0, 1)),
    "exactly one of"
  )
  data <- segmentation_data("a", "b", labels = c(0, 1, 2))
  expect_identical(data$labels, c(0L, 1L, 2L))
  expect_null(data$colormap)
})

test_that("`window` is the name, and `dicom_window` still answers", {
  expect_identical(segmentation_data("a", "b", labels = c(0, 1), window = "lung")$window,
                   "lung")
  expect_identical(
    segmentation_data("a", "b", labels = c(0, 1), dicom_window = "bone")$window,
    "bone"
  )
  expect_error(
    segmentation_data("a", "b", labels = c(0, 1), window = "lung", dicom_window = "bone"),
    "former name"
  )
})

test_that("an unset window is left out of the request entirely", {
  # Same reason as when DICOM arrived: sending a default nobody asked for would break every
  # run against an engine that does not know the field.
  data <- segmentation_data("a", "b", labels = c(0, 1))
  expect_false("window" %in% names(rplatypus:::compact(data)))
})

test_that("mask_volume turns voxels into millilitres", {
  # 32 voxels of 2 x 2 x 5 mm = 640 mm^3 = 0.64 ml. Checked by hand because this is the
  # number that would go in a report, and an arithmetic slip here is invisible.
  mask <- array(1L, dim = c(10, 10, 4))
  mask[3:6, 3:6, 2:3] <- 2L
  expect_equal(mask_volume(mask, spacing = c(2, 2, 5)), 0.64)
  expect_equal(mask_volume(mask, spacing = c(1, 1, 1)), 0.032)
})

test_that("mask_volume refuses what it cannot measure", {
  expect_error(mask_volume(array(1L, c(4, 4, 2)), spacing = c(1, 1)), "three positive")
  expect_error(mask_volume(array(1L, c(4, 4, 2)), spacing = c(1, 1, -1)), "three positive")
  expect_error(mask_volume(array(1L, c(4, 4)), spacing = c(1, 1, 1)), "three dimensions")
})

test_that("save_masks refuses the volume case a shape can prove", {
  # Five dimensions can only be volumes. Four cannot be told apart from a stack of images
  # with a class axis, and this function does not guess - the documentation points at
  # save_volumes() instead of a check pretending to know.
  expect_error(save_masks(array(1L, c(2, 8, 8, 4, 2)), tempdir(), binary_colormap),
               "save_volumes")
})

test_that("save_volumes states what each rank means rather than guessing", {
  # Four dimensions is a stack of class-index volumes, always. Reading it as one volume's
  # probabilities when the stack happens to be small is how a silent misinterpretation gets
  # into a package - it would write one wrong file and look like it worked.
  skip_if_no_volumes()
  root <- tiny_volume_dataset(cases = 2)
  scans <- sort(list.files(root, pattern = "ct[.]nii[.]gz$", recursive = TRUE,
                           full.names = TRUE))
  written <- save_volumes(array(1L, c(2, 8, 8, 4)), withr::local_tempdir(),
                          reference = scans, names = c("first", "second"))
  # Files on disk, not just returned paths: the earlier version of these tests counted paths
  # while both masks went to one file, and passed.
  expect_length(unique(written), 2)
  expect_true(all(file.exists(written)))

  expect_error(save_volumes(array(1L, c(8, 8)), withr::local_tempdir(), reference = scans),
               "expected 3")
})

test_that("plot_masks insists on a slice for volumes, and refuses one for images", {
  volumes <- array(0, dim = c(2, 8, 8, 4, 3))
  expect_error(plot_masks(volumes), "Choose a slice")
  images <- array(0, dim = c(2, 8, 8, 3))
  expect_error(plot_masks(images, slice = 2), "only applies to volumes")
})

test_that("volume_info reports spacing and voxel size", {
  skip_if_no_volumes()
  root <- tiny_volume_dataset(cases = 2, spacing = c(2, 2, 5))
  scans <- list.files(root, pattern = "ct[.]nii[.]gz$", recursive = TRUE,
                      full.names = TRUE)

  info <- volume_info(scans)
  expect_equal(nrow(info), 2)
  expect_equal(info$spacing_3, c(5, 5))
  # 2 x 2 x 5 mm = 20 mm^3 = 0.02 ml per voxel.
  expect_equal(info$voxel_ml, c(0.02, 0.02))
  expect_equal(info$shape_1, c(8, 8))
})

test_that("a volume spec trains from R", {
  skip_if_no_volumes()
  root <- tiny_volume_dataset()
  spec <- platypus_spec(
    data = segmentation_data(root, root, labels = c(0, 1), window = "soft_tissue"),
    models = list(u_net("unet3d", input_shape = c(8, 8, 4), channels = 1, blocks = 2,
                        filters = 4, epochs = 1, batch_size = 1,
                        metrics = list(metric_dice())))
  )
  fit <- platypus_fit(spec, num_workers = 0)

  expect_s3_class(fit, "platypus_fit")
  masks <- predict(fit, split = "validation")
  expect_equal(dim(masks), c(4L, 8L, 8L, 4L))
})

test_that("a predicted volume is written with the geometry of the scan it came from", {
  # The reason save_volumes() exists. A mask whose affine does not match the scan lands in
  # the wrong place in every viewer, and nothing about the file looks wrong.
  skip_if_no_volumes()
  root <- tiny_volume_dataset(cases = 2, spacing = c(2, 2, 5))
  scans <- sort(list.files(root, pattern = "ct[.]nii[.]gz$", recursive = TRUE,
                           full.names = TRUE))
  out <- withr::local_tempdir()

  masks <- array(1L, dim = c(2, 8, 8, 4))
  masks[, 3:6, 3:6, 2:3] <- 2L

  written <- save_volumes(masks, out, reference = scans, names = c("case_00", "case_01"))
  expect_length(unique(written), 2)
  expect_true(all(file.exists(written)))
  expect_match(basename(written[[1]]), "^case_00[.]nii[.]gz$")

  # Same spacing as the scan, which is the part that makes it overlay.
  expect_equal(volume_info(written)$spacing_3, volume_info(scans)$spacing_3)
  expect_equal(volume_info(written)$shape_1, volume_info(scans)$shape_1)
})

test_that("a mask that does not match its scan is refused rather than written", {
  skip_if_no_volumes()
  root <- tiny_volume_dataset(cases = 1)
  scan <- list.files(root, pattern = "ct[.]nii[.]gz$", recursive = TRUE,
                     full.names = TRUE)
  wrong_size <- array(1L, dim = c(1, 4, 4, 2))
  expect_error(save_volumes(wrong_size, withr::local_tempdir(), reference = scan),
               "does not match")
})

test_that("masks and reference volumes have to line up", {
  skip_if_no_volumes()
  masks <- array(1L, dim = c(2, 8, 8, 4))
  expect_error(save_volumes(masks, withr::local_tempdir(), reference = "only-one.nii.gz"),
               "have to line up")
})

test_that("predicted volumes can be measured in millilitres end to end", {
  # The whole point of carrying spacing: from a prediction to a number that goes in a report
  # without the user doing arithmetic on voxel counts.
  skip_if_no_volumes()
  root <- tiny_volume_dataset(cases = 1, spacing = c(2, 2, 5))
  scan <- list.files(root, pattern = "ct[.]nii[.]gz$", recursive = TRUE, full.names = TRUE)
  info <- volume_info(scan)

  truth <- array(1L, dim = c(8, 8, 4))
  truth[3:6, 3:6, 2:3] <- 2L
  millilitres <- mask_volume(truth, spacing = c(info$spacing_1, info$spacing_2,
                                                info$spacing_3))
  expect_equal(millilitres, 32 * 2 * 2 * 5 / 1000)
})

test_that("a series report says which directories are usable", {
  skip_if_no_series()
  root <- withr::local_tempdir()
  tiny_series(file.path(root, "case_00"))
  tiny_series(file.path(root, "case_01"), positions = c(0, 2.5, 5, 7.5))

  report <- series_report(list.dirs(root, recursive = FALSE))
  expect_s3_class(report, "platypus_series_report")
  expect_true(all(report$ok))
  expect_equal(report$slices, c(4L, 4L))
  expect_equal(report$sorted_by, c("position", "position"))
  expect_equal(report$spacing_3, c(2.5, 2.5))
})

test_that("a broken series is a row with a problem, not a stopped run", {
  # The reason this returns a table. An archive export contains a few bad cases and finding
  # them one exception at a time is an afternoon per dataset.
  skip_if_no_series()
  root <- withr::local_tempdir()
  tiny_series(file.path(root, "good"))
  tiny_series(file.path(root, "gap"), positions = c(0, 2.5, 7.5, 10))
  tiny_series(file.path(root, "duplicate"), positions = c(0, 2.5, 2.5, 5))

  report <- series_report(list.dirs(root, recursive = FALSE))

  expect_equal(sum(report$ok), 1)
  expect_match(report$problem[report$path == file.path(root, "gap")], "evenly spaced")
  expect_match(report$problem[report$path == file.path(root, "duplicate")], "same position")
  expect_true(is.na(report$problem[report$path == file.path(root, "good")]))
})

test_that("two series in one directory are reported as such", {
  skip_if_no_series()
  root <- withr::local_tempdir()
  mixed <- file.path(root, "mixed")
  tiny_series(mixed, positions = c(0, 2.5), uid = "1.2.3.4", prefix = "SCOUT")
  tiny_series(mixed, positions = c(0, 2.5), uid = "5.6.7.8", prefix = "RECON")

  report <- series_report(mixed)
  expect_false(report$ok)
  expect_match(report$problem, "different series")
})

test_that("the printed report leads with what needs attention", {
  skip_if_no_series()
  root <- withr::local_tempdir()
  tiny_series(file.path(root, "good"))
  tiny_series(file.path(root, "gap"), positions = c(0, 2.5, 7.5, 10))

  output <- capture.output(print(series_report(list.dirs(root, recursive = FALSE))))
  expect_true(any(grepl("1 of 2 usable", output)))
  expect_true(any(grepl("not usable", output)))
})

test_that("a series trains from R with nothing new in the specification", {
  # The rank is derived from input_shape, so a folder of slices needs no new setting - which
  # is the design holding up after four releases.
  skip_if_no_series()
  root <- withr::local_tempdir()
  for (case in c("case_00", "case_01")) {
    tiny_series(file.path(root, case, "images"))
    reticulate::py_run_string(sprintf("
import pathlib, numpy as np, nibabel as nib
masks = pathlib.Path(%s)
masks.mkdir(parents=True, exist_ok=True)
labels = np.zeros((128, 128, 4), np.float32)
labels[20:60, 20:60, 1:3] = 1
nib.save(nib.Nifti1Image(labels, np.diag([0.8, 0.8, 2.5, 1.0])), str(masks / 'seg.nii.gz'))
", shQuote(file.path(root, case, "masks"))))
  }

  spec <- platypus_spec(
    data = segmentation_data(root, root, labels = c(0, 1), window = "soft_tissue"),
    models = list(u_net("unet3d", input_shape = c(32, 32, 4), channels = 1, blocks = 2,
                        filters = 4, epochs = 1, batch_size = 1,
                        metrics = list(metric_dice())))
  )
  fit <- platypus_fit(spec, num_workers = 0)
  masks <- predict(fit, split = "validation")
  expect_equal(dim(masks), c(2L, 32L, 32L, 4L))
})


test_that("`target_spacing` is checked before Python starts", {
  expect_error(segmentation_data("a", "b", labels = c(0, 1), target_spacing = c(1, 1)),
               "three positive")
  expect_error(segmentation_data("a", "b", labels = c(0, 1), target_spacing = c(1, 1, 0)),
               "three positive")
})

test_that("an unset target_spacing is left out of the request", {
  data <- segmentation_data("a", "b", labels = c(0, 1))
  expect_false("target_spacing" %in% names(rplatypus:::compact(data)))
})

test_that("target_spacing crosses to the engine intact", {
  skip_if_no_resampling()
  spec <- platypus_spec(
    data = segmentation_data(tempdir(), tempdir(), labels = c(0, 1),
                             target_spacing = c(1, 1, 1.5)),
    models = list(u_net("u", input_shape = c(32, 32, 32), channels = 1))
  )
  expect_equal(unlist(as.list(spec)$data$target_spacing), c(1, 1, 1.5))
})

test_that("a resampled 3D spec trains through the bridge", {
  # What the R side is responsible for: the option reaching the engine and the run working.
  # That resampling puts two fields of view on one physical scale is measured in the engine's
  # own tests, where the dataset is reachable - asserting it here through shapes alone would
  # be a test that passes whatever happens.
  skip_if_no_resampling()
  root <- tiny_scaled_dataset(cases = c(1.0, 2.5))

  spec <- platypus_spec(
    data = segmentation_data(root, root, labels = c(0, 1), window = "soft_tissue",
                             target_spacing = c(1, 1, 1)),
    models = list(u_net("u", input_shape = c(32, 32, 32), channels = 1, blocks = 2,
                        filters = 4, epochs = 1, batch_size = 1,
                        metrics = list(metric_dice())))
  )
  fit <- platypus_fit(spec, num_workers = 0)

  expect_s3_class(fit, "platypus_fit")
  expect_true("val_dice" %in% names(training_history(fit)))
  expect_equal(dim(predict(fit, split = "validation")), c(2L, 32L, 32L, 32L))
})


# ----------------------------------------------------------------- channels
brats_patterns <- c("_t1\\.nii", "_t1ce\\.nii", "_t2\\.nii", "_flair\\.nii")

test_that("`channels_from` is checked before Python starts", {
  expect_error(segmentation_data("a", "b", labels = c(0, 1), channels_from = "_t1\\.nii"),
               "at least two")
  expect_error(
    segmentation_data("a", "b", labels = c(0, 1),
                      channels_from = c("_t1\\.nii", "_t1\\.nii")),
    "must be distinct"
  )
})

test_that("channel patterns cross to the engine as written", {
  # Not translated on the way through, for the same reason as group_by: a mistranslation would
  # produce a working run with the channels in the wrong order.
  skip_if_no_channels()
  spec <- platypus_spec(
    data = segmentation_data(tempdir(), tempdir(), labels = c(0, 1),
                             channels_from = brats_patterns),
    models = list(u_net("u", input_shape = c(16, 16, 8), channels = 4, blocks = 2))
  )
  expect_equal(unlist(as.list(spec)$data$channels_from), brats_patterns)
})

test_that("a channel count that disagrees with the model is caught as a spec error", {
  skip_if_no_channels()
  expect_error(
    platypus_spec(
      data = segmentation_data(tempdir(), tempdir(), labels = c(0, 1),
                               channels_from = brats_patterns),
      models = list(u_net("u", input_shape = c(16, 16, 8), channels = 1, blocks = 2))
    ),
    "channels_from lists 4"
  )
})

test_that("four sequences per case train as four channels", {
  skip_if_no_channels()
  root <- tiny_multimodal_dataset(cases = 2)

  spec <- platypus_spec(
    data = segmentation_data(root, root, labels = c(0, 1), channels_from = brats_patterns,
                             window = c(250, 500)),
    models = list(u_net("brats", input_shape = c(16, 16, 8), channels = 4, blocks = 2,
                        filters = 4, epochs = 1, batch_size = 1,
                        metrics = list(metric_dice())))
  )
  fit <- platypus_fit(spec, num_workers = 0)

  expect_s3_class(fit, "platypus_fit")
  expect_equal(dim(predict(fit, split = "validation")), c(2L, 16L, 16L, 8L))
})

test_that("a pattern matching two files is refused with a readable message", {
  # '_t1' matches both _t1.nii.gz and _t1ce.nii.gz. Taking the first would decide the channel
  # order by directory listing, which is the mistake the argument exists to prevent.
  skip_if_no_channels()
  root <- tiny_multimodal_dataset(cases = 1)

  spec <- platypus_spec(
    data = segmentation_data(root, root, labels = c(0, 1), window = c(250, 500),
                             channels_from = c("_t1", "_t1ce\\.nii", "_t2\\.nii",
                                               "_flair\\.nii")),
    models = list(u_net("brats", input_shape = c(16, 16, 8), channels = 4, blocks = 2,
                        filters = 4, epochs = 1, batch_size = 1))
  )
  expect_error(platypus_fit(spec, num_workers = 0), "matches 2 files")
})


# ------------------------------------------------------- augmenting volumes
test_that("`rank` is checked before Python starts", {
  expect_error(available_transforms(rank = 4), "2 for images")
})

test_that("the volume list is shorter than the image list and not empty", {
  skip_if_no_3d_augmentation()
  flat <- available_transforms()
  volumes <- available_transforms(rank = 3)

  expect_true(length(volumes) > 50)
  expect_true(length(volumes) < length(flat))
  expect_true(all(volumes %in% flat))
  # The gap is the point of the function existing: these cannot be used on a volume.
  expect_true("GaussNoise" %in% setdiff(flat, volumes))
})

test_that("the geometric transforms worth having are listed for volumes", {
  skip_if_no_3d_augmentation()
  volumes <- available_transforms(rank = 3)
  for (name in c("Affine", "ElasticTransform", "CubicSymmetry", "HorizontalFlip")) {
    expect_true(name %in% volumes, info = name)
  }
})

test_that("the listing can be filtered for browsing", {
  skip_if_no_3d_augmentation()
  flips <- available_transforms(rank = 3, pattern = "Flip")
  expect_true(length(flips) >= 2)
  expect_true(all(grepl("Flip", flips)))
})

test_that("a 3D model trains with augmentation", {
  skip_if_no_3d_augmentation()
  root <- tiny_volume_dataset()
  spec <- platypus_spec(
    data = segmentation_data(root, root, labels = c(0, 1), window = "soft_tissue"),
    models = list(u_net("unet3d", input_shape = c(8, 8, 4), channels = 1, blocks = 2,
                        filters = 4, epochs = 1, batch_size = 1,
                        metrics = list(metric_dice()),
                        augmentation = list(augmentation_step("HorizontalFlip", p = 0.5),
                                            augmentation_step("CubicSymmetry", p = 0.5))))
  )
  fit <- platypus_fit(spec, num_workers = 0)
  expect_s3_class(fit, "platypus_fit")
})

test_that("a transform that cannot do volumes is named when the run starts", {
  # Not an hour later, and not as `KeyError: 'images'` from inside albumentations.
  skip_if_no_3d_augmentation()
  root <- tiny_volume_dataset()
  spec <- platypus_spec(
    data = segmentation_data(root, root, labels = c(0, 1)),
    models = list(u_net("unet3d", input_shape = c(8, 8, 4), channels = 1, blocks = 2,
                        filters = 4, epochs = 1, batch_size = 1,
                        augmentation = list(augmentation_step("GaussNoise"))))
  )
  expect_error(platypus_fit(spec, num_workers = 0), "GaussNoise")
})

# --------------------------------------------------- reading a split back in
test_that("split_path resolves the paths the CSV stores relatively", {
  # The CSVs store paths relative to themselves *when they can*, so a dataset and its split
  # travel together. read.csv() then hands back paths that do not open from wherever the session
  # happens to be - a trap worth removing rather than documenting.
  #
  # Writing the split above the data is what produces the relative form; the first version of
  # this test put the two in unrelated temporary directories, where the paths come out absolute
  # and there was nothing to resolve.
  skip_if_no_splits()
  root <- tiny_patient_dataset(patients = 6, slices = 2)
  split <- split_dataset(root, dirname(root), group_by = "^(patient\\d+)_",
                         fractions = c(0.5, 0.5))

  raw <- utils::read.csv(split$train_path)
  expect_false(any(startsWith(raw$images, "/")))   # as stored: relative
  expect_false(all(file.exists(raw$images)))       # and not usable from here

  table <- split_path(split, "train")
  expect_true(all(file.exists(table$images)))      # as returned: usable
  expect_true(all(file.exists(table$masks)))
  expect_true(all(c("key", "group", "images", "masks") %in% names(table)))
  expect_equal(nrow(table), split$samples[["train"]])
})

test_that("split_path refuses a part the split does not have", {
  skip_if_no_splits()
  root <- tiny_patient_dataset(patients = 4, slices = 1)
  split <- split_dataset(root, withr::local_tempdir(), group_by = "^(patient\\d+)_",
                         fractions = c(0.75, 0.25))
  expect_error(split_path(split, "test"), "no 'test' part")
})

test_that("split_path insists on a split", {
  expect_error(split_path(list(train_path = "a.csv"), "train"), "split_dataset")
})

# ------------------------------------------------------- masks as label maps
test_that("read_masks reads label maps as well as pictures", {
  skip_if_no_volumes()
  root <- tiny_volume_dataset(cases = 2)
  masks <- list.files(root, pattern = "seg[.]nii[.]gz$", recursive = TRUE, full.names = TRUE)

  classes <- read_masks(masks, labels = c(0, 1), size = c(8, 8, 4))
  expect_equal(dim(classes), c(2L, 8L, 8L, 4L))
  # Counted from 1, as everywhere in the R surface.
  expect_setequal(unique(as.vector(classes)), c(1L, 2L))
})

test_that("read_masks wants exactly one way of naming classes", {
  expect_error(read_masks("a.png"), "exactly one of")
  expect_error(read_masks("a.png", colormap = binary_colormap, labels = c(0, 1)),
               "exactly one of")
})

test_that("a label that misses becomes background rather than an error", {
  # Label maps arrive as floats, so the comparison is to within half a unit. A value in the
  # file that no label claims is background - the same convention as an unmatched colour.
  skip_if_no_volumes()
  root <- tiny_volume_dataset(cases = 1)
  masks <- list.files(root, pattern = "seg[.]nii[.]gz$", recursive = TRUE, full.names = TRUE)
  classes <- read_masks(masks, labels = c(0, 7), size = c(8, 8, 4))
  expect_setequal(unique(as.vector(classes)), 1L)
})

# --------------------------------------------- predictions in the scan's space
test_that("`space` is checked before Python starts", {
  fit <- structure(list(models = "m", engine = NULL), class = "platypus_fit")
  expect_error(predict(fit, space = "patient"), "'arg' should be one of")
})

test_that("source space returns one mask per scan, on that scan's grid", {
  # The two spaces return different shapes of thing, and that is the API being explicit: scans
  # differ in size, so they cannot be stacked, and resizing them to match is how a mask ends up
  # describing anatomy it was not computed from.
  skip_if_no_source_space()
  root <- tiny_volume_dataset(cases = 2, shape = c(16, 16, 8), spacing = c(1, 1, 2))
  spec <- platypus_spec(
    data = segmentation_data(root, root, labels = c(0, 1), window = "soft_tissue",
                             target_spacing = c(1, 1, 1)),
    models = list(u_net("u", input_shape = c(8, 8, 8), channels = 1, blocks = 2, filters = 4,
                        epochs = 1, batch_size = 1))
  )
  fit <- platypus_fit(spec, num_workers = 0)

  on_model <- predict(fit, split = "validation")
  expect_true(is.array(on_model))
  expect_equal(dim(on_model), c(2L, 8L, 8L, 8L))

  on_source <- predict(fit, split = "validation", space = "source")
  expect_true(is.list(on_source))
  expect_length(on_source, 2)
  # Back to the scan's own shape - 16 x 16 x 8 - not the model's 8 x 8 x 8.
  expect_equal(dim(on_source[[1]]), c(16L, 16L, 8L))
})

test_that("a mask in the scan's space can be written over that scan", {
  # The whole point of the feature: with resampling, this used to be refused because the
  # prediction was on the model's grid and a mask with the wrong geometry lands in the wrong
  # place. Now the two agree by construction.
  skip_if_no_source_space()
  root <- tiny_volume_dataset(cases = 2, shape = c(16, 16, 8), spacing = c(1, 1, 2))
  scans <- sort(list.files(root, pattern = "ct[.]nii[.]gz$", recursive = TRUE,
                           full.names = TRUE))
  spec <- platypus_spec(
    data = segmentation_data(root, root, labels = c(0, 1), window = "soft_tissue",
                             target_spacing = c(1, 1, 1)),
    models = list(u_net("u", input_shape = c(8, 8, 8), channels = 1, blocks = 2, filters = 4,
                        epochs = 1, batch_size = 1))
  )
  fit <- platypus_fit(spec, num_workers = 0)
  masks <- predict(fit, split = "validation", space = "source")

  written <- save_volumes(masks, withr::local_tempdir(), reference = scans,
                          names = c("case_00", "case_01"))
  expect_length(unique(written), 2)
  expect_true(all(file.exists(written)))
  expect_equal(volume_info(written)$spacing_3, volume_info(scans)$spacing_3)
  expect_equal(volume_info(written)$shape_1, volume_info(scans)$shape_1)
})

test_that("a prediction on the model's grid is still refused, with the reason", {
  skip_if_no_source_space()
  root <- tiny_volume_dataset(cases = 1, shape = c(16, 16, 8), spacing = c(1, 1, 2))
  scan <- list.files(root, pattern = "ct[.]nii[.]gz$", recursive = TRUE, full.names = TRUE)
  spec <- platypus_spec(
    data = segmentation_data(root, root, labels = c(0, 1), window = "soft_tissue",
                             target_spacing = c(1, 1, 1)),
    models = list(u_net("u", input_shape = c(8, 8, 8), channels = 1, blocks = 2, filters = 4,
                        epochs = 1, batch_size = 1))
  )
  fit <- platypus_fit(spec, num_workers = 0)
  expect_error(
    save_volumes(predict(fit, split = "validation"), withr::local_tempdir(),
                 reference = scan),
    "does not match"
  )
})

test_that("save_volumes takes probabilities in a list too", {
  skip_if_no_source_space()
  root <- tiny_volume_dataset(cases = 1, shape = c(16, 16, 8), spacing = c(1, 1, 2))
  scan <- list.files(root, pattern = "ct[.]nii[.]gz$", recursive = TRUE, full.names = TRUE)
  spec <- platypus_spec(
    data = segmentation_data(root, root, labels = c(0, 1), window = "soft_tissue",
                             target_spacing = c(1, 1, 1)),
    models = list(u_net("u", input_shape = c(8, 8, 8), channels = 1, blocks = 2, filters = 4,
                        epochs = 1, batch_size = 1))
  )
  fit <- platypus_fit(spec, num_workers = 0)
  probabilities <- predict(fit, split = "validation", type = "probability",
                           space = "source")
  expect_equal(dim(probabilities[[1]]), c(16L, 16L, 8L, 2L))

  written <- save_volumes(probabilities, withr::local_tempdir(), reference = scan)
  expect_length(written, 1)
})

test_that("a list member of the wrong rank is refused", {
  expect_error(
    save_volumes(list(array(1L, c(8, 8))), tempdir(), reference = "a.nii.gz"),
    "expected 3"
  )
})

test_that("masks that would overwrite each other are refused", {
  # One directory per case with the same filename inside is the normal layout, so the default
  # names collide and every mask would be written to one path - keeping the last and losing the
  # rest without a word. The vignette walked into this: six masks, one file.
  skip_if_no_volumes()
  root <- tiny_volume_dataset(cases = 3)
  scans <- sort(list.files(root, pattern = "ct[.]nii[.]gz$", recursive = TRUE,
                           full.names = TRUE))
  masks <- lapply(seq_along(scans), function(i) array(1L, dim = c(8, 8, 4)))

  expect_error(save_volumes(masks, withr::local_tempdir(), reference = scans),
               "written to the same name")

  written <- save_volumes(masks, withr::local_tempdir(), reference = scans,
                          names = c("case_a", "case_b", "case_c"))
  expect_length(unique(basename(written)), 3)
})


# --- overlapping classes have no label map, and this is the case `regions` was built for --
#
# BraTS names three overlapping regions and stores them as volumes, so the volume writer is
# where this matters most - and `#152` named `save_masks()` while `save_volumes()` reduced a
# prediction in **two** places: a 4-dimensional array inside a list and a 5-dimensional
# stack. A label-map NIfTI holds one integer per voxel, so there is nothing an overlap could
# be written as.

overlapping_volumes <- function(cases = 2L, shape = c(8, 8, 4)) {
  # A label map of {0, 1, 2} turned into unions, so the overlap is a consequence of the data
  # rather than something a test asserted into existence.
  labels <- array(0L, dim = shape)
  labels[1:4, , ] <- 1L
  labels[5:8, , ] <- 2L
  channels <- lapply(list(c(1, 2), 2), function(of) as.numeric(labels %in% of))
  one <- array(unlist(channels), dim = c(shape, 2L))
  lapply(seq_len(cases), function(i) one)
}

test_that("save_volumes refuses an overlapping prediction in a list", {
  expect_error(
    save_volumes(overlapping_volumes(), withr::local_tempdir(), reference = c("a", "b")),
    "2 classes at once"
  )
  expect_error(
    save_volumes(overlapping_volumes(), withr::local_tempdir(), reference = c("a", "b")),
    "save_class_volumes"
  )
})

test_that("save_volumes refuses an overlapping prediction as a stack", {
  stacked <- array(unlist(overlapping_volumes(cases = 2L)), dim = c(2, 8, 8, 4, 2))
  expect_error(
    save_volumes(stacked, withr::local_tempdir(), reference = c("a", "b")),
    "2 classes at once"
  )
})

test_that("an exclusive volume prediction is still reduced rather than refused", {
  # The control, and the one that matters: a softmax prediction must pass both of the places
  # the refusal was added, or every ordinary volume run would start failing.
  skip_if_no_volumes()
  root <- tiny_volume_dataset(cases = 1)
  scan <- list.files(root, pattern = "ct[.]nii[.]gz$", recursive = TRUE, full.names = TRUE)
  softmax <- array(0, dim = c(8, 8, 4, 2))
  softmax[, , , 1] <- 0.7
  softmax[, , , 2] <- 0.3
  written <- save_volumes(list(softmax), withr::local_tempdir(), reference = scan)
  expect_length(written, 1L)
  stacked <- array(softmax, dim = c(1, 8, 8, 4, 2))
  expect_length(save_volumes(stacked, withr::local_tempdir(), reference = scan), 1L)
})

test_that("save_class_volumes writes one NIfTI per class, carrying the scan's geometry", {
  skip_if_no_volumes()
  root <- tiny_volume_dataset(cases = 2)
  scans <- sort(list.files(root, pattern = "ct[.]nii[.]gz$", recursive = TRUE,
                           full.names = TRUE))
  out <- withr::local_tempdir()
  written <- save_class_volumes(
    overlapping_volumes(cases = 2L), out, reference = scans,
    classes = c("whole tumour", "enhancing"),
    names = c("case_a", "case_b")
  )

  # Volume by volume, class within volume - the order a caller zips against its case names.
  expect_identical(
    basename(written),
    c("case_a_whole_tumour.nii.gz", "case_a_enhancing.nii.gz",
      "case_b_whole_tumour.nii.gz", "case_b_enhancing.nii.gz")
  )
  # Read back the content, not the count: a writer that put the same channel in both would
  # pass a test that only looked at the names. `whole tumour` is both halves, `enhancing` is
  # the second half alone, and the overlap is what no label map could have held.
  read_back <- function(path) {
    reticulate::py_run_string(sprintf(
      "import nibabel as nib, numpy as np\nout = np.asarray(nib.load(%s).dataobj)",
      shQuote(path, type = "cmd")
    ))$out
  }
  whole <- read_back(file.path(out, "case_a_whole_tumour.nii.gz"))
  enhancing <- read_back(file.path(out, "case_a_enhancing.nii.gz"))
  expect_true(all(whole == 1L))
  expect_true(all(enhancing[1:4, , ] == 0L))
  expect_true(all(enhancing[5:8, , ] == 1L))

  # And the geometry, which is the only reason this is not `save_class_masks()` with another
  # extension: every class of a scan carries that scan's spacing.
  expect_equal(volume_info(written)$spacing_3, rep(volume_info(scans)$spacing_3, each = 2))
})

test_that("save_class_volumes counts its class names against the channels", {
  expect_error(
    save_class_volumes(overlapping_volumes(), withr::local_tempdir(),
                       reference = c("a", "b"), classes = "only one"),
    "2 channels and 1 class names"
  )
})

test_that("save_class_volumes refuses two class names that become one file", {
  expect_error(
    save_class_volumes(overlapping_volumes(), withr::local_tempdir(),
                       reference = c("a", "b"), classes = c("core 1", "core_1")),
    "same filename"
  )
})

test_that("save_class_volumes states the ranks it takes rather than guessing", {
  # Unlike `save_volumes()`, no rank here is ambiguous: a prediction with a class axis always
  # has one dimension more than the volume, so there is nothing to guess between.
  expect_error(
    save_class_volumes(array(1L, dim = c(8, 8, 4)), withr::local_tempdir(),
                       reference = "a", classes = c("x", "y")),
    "3 dimensions; expected 4"
  )
})

test_that("the engine names a class file, and this package no longer has an opinion", {
  # This replaces a §3F pair rather than dropping one. The test that stood here compared
  # `rplatypus:::class_file_names()` against the engine's `class_filename` over awkward
  # names, because `save_class_volumes()` could not forward and had to carry the rule
  # itself. `pyplatypus 0.8.0a29` moved the volume writer into the engine, so the second
  # copy is gone - and what is worth checking is no longer that two rules agree but that
  # the one rule is what reaches disk from here, on names that are awkward for a path.
  skip_if_no_volumes()
  root <- tiny_volume_dataset(cases = 2)
  scans <- sort(list.files(root, pattern = "ct[.]nii[.]gz$", recursive = TRUE,
                           full.names = TRUE))
  written <- save_class_volumes(
    overlapping_volumes(), withr::local_tempdir(), reference = scans,
    classes = c("whole tumour", "Core / rim"), names = c("case_01", "case_02")
  )
  expect_identical(
    basename(written),
    c("case_01_whole_tumour.nii.gz", "case_01_Core_rim.nii.gz",
      "case_02_whole_tumour.nii.gz", "case_02_Core_rim.nii.gz")
  )
})
