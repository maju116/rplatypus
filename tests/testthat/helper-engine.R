# Every test that needs Python goes through this.
#
# R CMD check has to pass on a machine with no Python, no network and no patience - that
# is how CRAN runs it, and how a reviewer will see the package. So nothing below starts
# the engine unless it is already there or the environment says it is allowed to.

engine_available <- function() {
  if (!identical(Sys.getenv("PLATYPUS_TEST_ENGINE"), "true")) {
    return(FALSE)
  }
  # With the flag set, a failure to start is a failure, not a skip.
  #
  # This cost an afternoon's confidence once: pyplatypus 0.3.0a4 had just been published, uv
  # was still answering from its cached index, the engine could not start - and every test
  # skipped. The run looked exactly like a machine with no Python: 72 skipped, 99 passed, green.
  # Reporting that as a pass would have been wrong, and only the changed skip count gave it
  # away. The `engine` CI job already refuses to pass with skips; this makes a local run as
  # honest as CI.
  started <- tryCatch({
    platypus_status()
    reticulate::py_available(initialize = TRUE)
  }, error = function(e) conditionMessage(e))

  if (isTRUE(started)) {
    return(TRUE)
  }
  stop("PLATYPUS_TEST_ENGINE=true but the engine could not start, so these tests would have ",
       "skipped silently: ",
       if (is.character(started)) started else "reticulate reported no Python",
       call. = FALSE)
}

skip_if_no_engine <- function() {
  testthat::skip_if_not(
    engine_available(),
    "engine not started (set PLATYPUS_TEST_ENGINE=true to run these)"
  )
}

#' A tiny dataset on disk, laid out the way `nested_dirs` expects
#'
#' Written through the engine's own Python rather than by adding an image-writing
#' dependency to this package: these tests need the engine anyway, so nothing is gained by
#' having two ways to make a PNG.
tiny_dataset <- function(n = 6, size = 32) {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  reticulate::py_run_string(sprintf("
import numpy as np, pathlib
from PIL import Image
root = pathlib.Path(%s)
rng = np.random.default_rng(0)
for i in range(%d):
    sample = root / f'sample_{i:02d}'
    (sample / 'images').mkdir(parents=True, exist_ok=True)
    (sample / 'masks').mkdir(parents=True, exist_ok=True)
    mask = np.zeros((%d, %d), np.uint8)
    top = 4 + (i %% 8)
    mask[top:top + 12, 6:22] = 255
    image = np.clip(mask.astype(np.float32) * 0.7 + rng.random((%d, %d)) * 70, 0, 255)
    Image.fromarray(image.astype(np.uint8)).convert('RGB').save(sample / 'images' / 'a.png')
    Image.fromarray(mask).convert('RGB').save(sample / 'masks' / 'a.png')
", shQuote(root), n, size, size, size, size))
  root
}

#' The same, with the masks kept apart instead of united
#'
#' One file per object, which is the layout `instance_data()` is named for and the whole
#' difference between the two tasks on disk: `tiny_dataset()` writes one mask per sample and
#' two touching squares in it are one region forever.
#'
#' Two objects a case, deliberately **touching** - they share a column - because a dataset
#' whose objects never touch cannot tell a separation signal from connected components, and a
#' fixture that cannot distinguish the thing under test is §4's probe answering an adjacent
#' question.
tiny_instance_dataset <- function(n = 6, size = 32) {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  reticulate::py_run_string(sprintf("
import numpy as np, pathlib
from PIL import Image
root = pathlib.Path(%s)
rng = np.random.default_rng(0)
for i in range(%d):
    sample = root / f'sample_{i:02d}'
    (sample / 'images').mkdir(parents=True, exist_ok=True)
    (sample / 'masks').mkdir(parents=True, exist_ok=True)
    top = 4 + (i %% 8)
    first = np.zeros((%d, %d), np.uint8)
    second = np.zeros((%d, %d), np.uint8)
    first[top:top + 10, 6:14] = 255
    second[top:top + 10, 14:22] = 255     # shares the seam at column 14
    both = np.maximum(first, second)
    image = np.clip(both.astype(np.float32) * 0.7 + rng.random((%d, %d)) * 70, 0, 255)
    Image.fromarray(image.astype(np.uint8)).convert('RGB').save(sample / 'images' / 'a.png')
    Image.fromarray(first).save(sample / 'masks' / 'object_0.png')
    Image.fromarray(second).save(sample / 'masks' / 'object_1.png')
", shQuote(root), n, size, size, size, size, size, size))
  root
}

#' Images in class directories, which is what `nested_dirs` means for a classifier
#'
#' Two classes, and the difference between them is **learnable in one epoch on purpose**: a
#' fixture whose classes a model cannot separate would report a trained run and an untrained
#' one as the same thing, which is §4's probe answering an adjacent question. `bright`
#' carries a square and `dark` does not, so a single pooled feature divides them - and the
#' test that checks a fit learned anything is what that is for.
#'
#' Balanced, so that nothing here depends on the prevalence argument the engine's own
#' metric choice was made from: an unbalanced fixture would make `accuracy` and `auc` move
#' together and hide exactly the distinction this task's default is about.
tiny_classification_dataset <- function(per_class = 4, size = 32) {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  reticulate::py_run_string(sprintf("
import numpy as np, pathlib
from PIL import Image
root = pathlib.Path(%s)
rng = np.random.default_rng(0)
for name in ('dark', 'bright'):
    (root / name).mkdir(parents=True, exist_ok=True)
for i in range(%d):
    for name in ('dark', 'bright'):
        picture = rng.random((%d, %d)) * 60
        if name == 'bright':
            picture[8:24, 8:24] += 170
        image = np.clip(picture, 0, 255).astype(np.uint8)
        Image.fromarray(image).convert('RGB').save(root / name / f'{name}_{i:02d}.png')
", shQuote(root), per_class, size, size))
  root
}

tiny_classification_spec <- function(root, ...) {
  platypus_spec(
    data = classification_data(root, root, classes = c("dark", "bright")),
    models = list(classifier("tiny", input_shape = c(32, 32), blocks = 2, filters = 4,
                             epochs = 1, batch_size = 2, ...))
  )
}

tiny_instance_spec <- function(root, ...) {
  platypus_spec(
    data = instance_data(root, root),
    models = list(u_net("tiny", input_shape = c(32, 32), blocks = 2, filters = 4,
                        separation = separation_rim(width = 1),
                        epochs = 1, batch_size = 2, ...))
  )
}

tiny_spec <- function(root, ...) {
  platypus_spec(
    data = segmentation_data(root, root, colormap = binary_colormap),
    models = list(u_net("tiny", input_shape = c(32, 32), blocks = 2, filters = 4,
                        metrics = list(metric_dice(include_background = FALSE)),
                        epochs = 1, batch_size = 2, ...))
  )
}

#' Does the engine in use know about DICOM?
#'
#' The R package pins an exact pyplatypus, which is what stops a release breaking when the
#' engine drifts - but it also means a feature can exist here before the engine carrying it
#' is published. Until then CI runs against the released version, and these tests have to
#' notice that rather than fail over it.
engine_reads_dicom <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch({
    length(rplatypus:::shim()$window_presets()) > 0
  }, error = function(e) FALSE))
}

skip_if_no_dicom <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(
    engine_reads_dicom(),
    "the engine in use predates DICOM support"
  )
}


#' Does the engine in use know how to split a dataset and score cases?
#'
#' Same reasoning as `engine_reads_dicom()`: the pin means this package can describe a
#' feature before the published engine carries it, and CI runs against the published one.
#' Asking the engine what it has beats assuming.
engine_splits_data <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch({
    engine <- rplatypus:::engine()
    reticulate::py_has_attr(engine, "split_dataset") &&
      reticulate::py_has_attr(engine, "summarise_cases")
  }, error = function(e) FALSE))
}

skip_if_no_splits <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(
    engine_splits_data(),
    "the engine in use predates dataset splitting"
  )
}


#' A dataset laid out as scans of several patients
#'
#' Keys look like `patient03_slice001`, which is the shape a group pattern is written for.
#' @param envir The frame the directory should outlive. Training reads the files once, but
#'   `evaluate_cases()` reads them again afterwards, so a dataset tied to a helper's own
#'   frame vanishes between the two - which is how this argument came to exist.
tiny_patient_dataset <- function(patients = 8, slices = 2, size = 32,
                                 envir = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = envir)
  reticulate::py_run_string(sprintf("
import numpy as np, pathlib
from PIL import Image
root = pathlib.Path(%s)
rng = np.random.default_rng(0)
for p in range(%d):
    for s in range(%d):
        sample = root / f'patient{p:02d}_slice{s:03d}'
        (sample / 'images').mkdir(parents=True, exist_ok=True)
        (sample / 'masks').mkdir(parents=True, exist_ok=True)
        mask = np.zeros((%d, %d), np.uint8)
        top = 4 + p
        mask[top:top + 12, 6:22] = 255
        image = np.clip(mask.astype(np.float32) * 0.7 + rng.random((%d, %d)) * 70, 0, 255)
        Image.fromarray(image.astype(np.uint8)).convert('RGB').save(sample / 'images' / 'a.png')
        Image.fromarray(mask).convert('RGB').save(sample / 'masks' / 'a.png')
", shQuote(root), patients, slices, size, size, size, size))
  root
}


#' Can the engine in use read volumes?
engine_reads_volumes <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch(rplatypus:::shim()$volume_support(), error = function(e) FALSE))
}

skip_if_no_volumes <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(
    engine_reads_volumes(),
    "the engine in use predates volume support"
  )
}

#' A dataset of NIfTI volumes with label-map masks
#'
#' Deliberately tiny. A 3D fixture that takes a minute gets skipped, and a skipped test
#' proves nothing.
tiny_volume_dataset <- function(cases = 4, shape = c(8, 8, 4), spacing = c(2, 2, 5),
                                envir = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = envir)
  reticulate::py_run_string(sprintf("
import numpy as np, pathlib, nibabel as nib
root = pathlib.Path(%s)
shape = (%d, %d, %d)
affine = np.diag([%f, %f, %f, 1.0])
for n in range(%d):
    sample = root / f'case_{n:02d}'
    (sample / 'images').mkdir(parents=True, exist_ok=True)
    (sample / 'masks').mkdir(parents=True, exist_ok=True)
    labels = np.zeros(shape, np.float32)
    labels[2:6, 2:6, 1:3] = 1
    scan = np.where(labels > 0, 40.0, -1000.0).astype(np.float32)
    nib.save(nib.Nifti1Image(scan, affine), str(sample / 'images' / 'ct.nii.gz'))
    nib.save(nib.Nifti1Image(labels, affine), str(sample / 'masks' / 'seg.nii.gz'))
# The heredoc above ends at column 0 because its contents are Python source and
# must not be indented, so the arguments that follow cannot align under sprintf(.
", shQuote(root), shape[1], shape[2], shape[3],
   spacing[1], spacing[2], spacing[3], cases))  # nolint: indentation_linter.
  root
}


#' A dataset of NIfTI volumes whose masks are label maps with two classes
#'
#' Two shapes of the same data, and the second is why this exists rather than a flag on
#' `tiny_volume_dataset()`. With `background = TRUE` the masks hold 0, 1 and 2, so
#' `labels = c(1, 2)` leaves every background voxel matching nothing. With
#' `background = FALSE` every voxel is 1 or 2, so the same `labels` is **correct** and has
#' to keep working.
#'
#' A fixture that could only produce the first would make "refuse whenever 0 is missing"
#' indistinguishable from what the engine actually does, which is to refuse only when the
#' data has unmatched voxels. §4's probe that cannot fail for the reason it is asking about.
tiny_label_dataset <- function(background = TRUE, cases = 4, shape = c(8, 8, 4),
                               envir = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = envir)
  reticulate::py_run_string(sprintf("
import numpy as np, pathlib, nibabel as nib
root = pathlib.Path(%s)
shape = (%d, %d, %d)
affine = np.diag([2.0, 2.0, 5.0, 1.0])
background = %s
for n in range(%d):
    sample = root / f'case_{n:02d}'
    (sample / 'images').mkdir(parents=True, exist_ok=True)
    (sample / 'masks').mkdir(parents=True, exist_ok=True)
    labels = np.zeros(shape, np.float32) if background else np.ones(shape, np.float32)
    labels[2:6, 2:6, 1:3] = 1
    labels[0:2, 0:8, 0:4] = 2
    scan = np.where(labels > 1, 40.0, -1000.0).astype(np.float32)
    nib.save(nib.Nifti1Image(scan, affine), str(sample / 'images' / 'ct.nii.gz'))
    nib.save(nib.Nifti1Image(labels, affine), str(sample / 'masks' / 'seg.nii.gz'))
", shQuote(root), shape[1], shape[2], shape[3],
   if (background) "True" else "False", cases))  # nolint: indentation_linter.
  root
}


#' Can the engine in use assemble a DICOM series?
engine_reads_series <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch(rplatypus:::shim()$series_support(), error = function(e) FALSE))
}

skip_if_no_series <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(
    engine_reads_series(),
    "the engine in use predates DICOM series support"
  )
}

#' A folder of DICOM slices, written through the engine's pydicom
#'
#' `positions` are millimetres along the slice normal, so a caller can leave a gap or repeat a
#' position to build the broken cases the report exists to find. File names deliberately sort
#' differently from the anatomy.
#' @param prefix Distinguishes two series written into one directory, which is the state an
#'   archive export arrives in and what the report exists to catch. Without it the second call
#'   writes the same filenames and silently replaces the first.
tiny_series <- function(directory, positions = c(0, 2.5, 5, 7.5), uid = NULL,
                        prefix = "IM") {
  reticulate::py_run_string(sprintf("
import pathlib, pydicom
from pydicom.data import get_testdata_file
directory = pathlib.Path(%s)
directory.mkdir(parents=True, exist_ok=True)
positions = [%s]
uid = %s or pydicom.uid.generate_uid()
prefix = %s
for index, position in enumerate(positions):
    dataset = pydicom.dcmread(get_testdata_file('CT_small.dcm'))
    dataset.SeriesInstanceUID = uid
    dataset.ImageOrientationPatient = [1, 0, 0, 0, 1, 0]
    dataset.ImagePositionPatient = [0.0, 0.0, float(position)]
    dataset.PixelSpacing = [0.8, 0.8]
    dataset.SliceThickness = 2.5
    dataset.InstanceNumber = index + 1
    dataset.save_as(directory / f'{prefix}{(len(positions) - index) * 7 %% 100:02d}.dcm')
# The heredoc above ends at column 0 because its contents are Python source and
# must not be indented, so the arguments that follow cannot align under sprintf(.
", shQuote(directory), paste(positions, collapse = ", "),
   if (is.null(uid)) "None" else shQuote(uid), shQuote(prefix)))  # nolint: indentation_linter.
  directory
}


#' Does the engine in use resample volumes?
engine_resamples <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch({
    schema <- rplatypus:::engine()$spec_schema()
    "target_spacing" %in% names(schema$`$defs`$SegmentationData$properties)
  }, error = function(e) FALSE))
}

skip_if_no_resampling <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(
    engine_resamples(),
    "the engine in use predates resampling"
  )
}

#' Volumes of the same ball acquired over different lengths of patient
#'
#' `thickness` is the slice spacing in millimetres, so two datasets with the same number of
#' slices cover different amounts of anatomy - which is what makes a plain resize wrong and the
#' reason target_spacing exists.
tiny_scaled_dataset <- function(cases = c(1.0, 2.5), slices = 32, envir = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = envir)
  reticulate::py_run_string(sprintf("
import numpy as np, pathlib, nibabel as nib
root = pathlib.Path(%s)
for index, thickness in enumerate([%s]):
    sample = root / f'case_{index:02d}'
    (sample / 'images').mkdir(parents=True, exist_ok=True)
    (sample / 'masks').mkdir(parents=True, exist_ok=True)
    shape = (32, 32, %d)
    spacing = (1.0, 1.0, thickness)
    grid = np.indices(shape).astype(np.float32)
    centre = (np.asarray(shape, np.float32) - 1) / 2
    mm = [(grid[a] - centre[a]) * spacing[a] for a in range(3)]
    inside = np.sqrt(sum(x ** 2 for x in mm)) <= 8.0
    scan = np.where(inside, 40.0, -1000.0).astype(np.float32)
    affine = np.diag([*spacing, 1.0])
    nib.save(nib.Nifti1Image(scan, affine), str(sample / 'images' / 'ct.nii.gz'))
    nib.save(nib.Nifti1Image(inside.astype(np.float32), affine),
             str(sample / 'masks' / 'seg.nii.gz'))
", shQuote(root), paste(cases, collapse = ", "), slices))
  root
}


#' Does the engine in use read one channel per file?
engine_stacks_channels <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch({
    schema <- rplatypus:::engine()$spec_schema()
    "channels_from" %in% names(schema$`$defs`$SegmentationData$properties)
  }, error = function(e) FALSE))
}

skip_if_no_channels <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(
    engine_stacks_channels(),
    "the engine in use predates channels_from"
  )
}

#' A dataset shaped like BraTS: four sequences per case, plus a label map
#'
#' Each sequence is filled with its own value, so which channel it lands in is visible. The
#' filenames sort as flair, t1, t1ce, t2 - the order nobody wants - which is the point.
tiny_multimodal_dataset <- function(cases = 2, shape = c(16, 16, 8),
                                    envir = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = envir)
  reticulate::py_run_string(sprintf("
import numpy as np, pathlib, nibabel as nib
root = pathlib.Path(%s)
shape = (%d, %d, %d)
affine = np.eye(4)
values = {'t1': 100.0, 't1ce': 200.0, 't2': 300.0, 'flair': 400.0}
for index in range(%d):
    name = f'case_{index:03d}'
    sample = root / name
    (sample / 'images').mkdir(parents=True, exist_ok=True)
    (sample / 'masks').mkdir(parents=True, exist_ok=True)
    for sequence, value in values.items():
        nib.save(nib.Nifti1Image(np.full(shape, value, np.float32), affine),
                 str(sample / 'images' / f'{name}_{sequence}.nii.gz'))
    labels = np.zeros(shape, np.float32)
    labels[4:12, 4:12, 2:6] = 1
    nib.save(nib.Nifti1Image(labels, affine), str(sample / 'masks' / f'{name}_seg.nii.gz'))
", shQuote(root), shape[1], shape[2], shape[3], cases))
  root
}


#' Does the engine in use augmentation_step volumes?
engine_augments_volumes <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch({
    result <- rplatypus:::shim()$transform_names(rank = 3L)
    isTRUE(result$ok) && length(result$transforms) > 0
  }, error = function(e) FALSE))
}

skip_if_no_3d_augmentation <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(
    engine_augments_volumes(),
    "the engine in use predates 3D augmentation"
  )
}

#' Can the engine in use map predictions back to the source grid?
engine_maps_to_source <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch({
    # Called for the side effect, not the value: it starts the engine, which is what
    # makes the version answerable below. Assigning the result said the opposite.
    rplatypus:::engine()$spec_schema()
    version <- platypus_status()$engine_version
    !is.na(version) && utils::compareVersion(gsub("a", ".", version), "0.3.0.6") >= 0
  }, error = function(e) FALSE))
}

skip_if_no_source_space <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(
    engine_maps_to_source(),
    "the engine in use predates predictions in source space"
  )
}

#' Does the engine in use have the weights registry?
engine_has_weights_registry <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch({
    result <- rplatypus:::shim()$weights_listing()
    isTRUE(result$ok)
  }, error = function(e) FALSE))
}

skip_if_no_weights_registry <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(
    engine_has_weights_registry(),
    "the engine in use predates the weights registry"
  )
}

#' Does the engine in use accept a pretrained encoder?
#'
#' Probed by offering it the field and seeing whether it is refused. The spec forbids
#' unknown keys, so an engine that predates `encoder` rejects this outright - which is the
#' pin working, and exactly what §4f of the project notes predicts. No new engine function
#' is needed to ask the question, which matters: adding one would have meant another
#' release before this could be tested at all.
engine_has_encoders <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch({
    result <- rplatypus:::shim()$build_spec(
      list(
        # `task` has to be here, and its absence is how this probe lied once: without it
        # the engine refuses the configuration for a reason that has nothing to do with
        # `encoder`, the probe reads that refusal as "no such field", and every encoder
        # test skips against an engine that supports them perfectly well. A probe has to
        # fail for the one reason it is asking about.
        task = "semantic_segmentation",
        data = list(train_path = ".", validation_path = ".",
                    colormap = list(c(0L, 0L, 0L), c(255L, 255L, 255L))),
        models = list(list(name = "probe", input_shape = c(64L, 64L),
                           encoder = "resnet34"))
      ),
      check_paths = FALSE
    )
    isTRUE(result$ok)
  }, error = function(e) FALSE))
}

#' Does the engine in use understand `regions`?
#'
#' Offered the field rather than asked for a version, the way the encoder probe is - and
#' with `task` present for the same reason it learnt: without it the engine refuses the
#' configuration for a reason that has nothing to do with `regions`, this reads that
#' refusal as "no such field", and every regions test skips against an engine that
#' supports them. Two entries because the schema's minimum is two, so one would be
#' refused by an engine that has the field.
engine_has_regions <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch({
    result <- rplatypus:::shim()$build_spec(
      list(
        task = "semantic_segmentation",
        data = list(train_path = ".", validation_path = ".",
                    regions = list(list(name = "a", of = list(1L)),
                                   list(name = "b", of = list(2L)))),
        models = list(list(name = "probe", input_shape = c(64L, 64L)))
      ),
      check_paths = FALSE
    )
    isTRUE(result$ok)
  }, error = function(e) FALSE))
}

#' Does the engine in use understand `classes_from`?
#'
#' The same probe as `regions`, for the same reason and with the same two lessons built in:
#' `task` is present, because without it the engine refuses the configuration for a reason
#' that has nothing to do with the field and every test here would skip against an engine
#' that supports it; and there are two patterns, because the schema's minimum is two, so one
#' would be refused by an engine that has the field.
engine_has_classes_from <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch({
    result <- rplatypus:::shim()$build_spec(
      list(
        task = "semantic_segmentation",
        data = list(train_path = ".", validation_path = ".",
                    classes_from = list("_vessel\\.png$", "_organ\\.png$")),
        models = list(list(name = "probe", input_shape = c(64L, 64L)))
      ),
      check_paths = FALSE
    )
    isTRUE(result$ok)
  }, error = function(e) FALSE))
}

skip_if_no_classes_from <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(
    engine_has_classes_from(),
    "the engine in use predates `classes_from`"
  )
}

skip_if_no_regions <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(
    engine_has_regions(),
    "the engine in use predates `regions`"
  )
}

skip_if_no_encoders <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(
    engine_has_encoders(),
    "the engine in use predates pretrained encoders"
  )
}

#' Is timm actually installed in the environment the engine runs in?
#'
#' Separate from `engine_has_encoders()` on purpose. The engine can accept the field while
#' the extra that implements it is missing, and those are different failures with different
#' fixes: one is an old engine, the other an environment built without `[encoders]`. Keeping
#' them apart is what would have caught the `hub` hole a release earlier.
engine_has_timm <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch(
    reticulate::py_module_available("timm"),
    error = function(e) FALSE
  ))
}

skip_if_no_timm <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(engine_has_timm(), "timm is not installed in this environment")
}

#' Does the engine in use refuse masks the colormap does not describe?
#'
#' Asked of `Engine`'s signature rather than by trying it, which is unusual here and
#' deliberate. The first version of this probe built an engine with `check_masks = FALSE`
#' over a path with no data, and got back "'.' yielded no usable samples" - so it reported
#' the feature missing when the engine had it, and every test below skipped against a
#' published engine that supports them. **It was conflating "no data" with "no feature".**
#'
#' What is actually being asked is whether R may pass this argument at all, and that is a
#' property of the signature. The behaviour behind it is what the tests themselves cover.
engine_checks_masks <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch({
    # Asked entirely in Python. `names()` on a reticulate-wrapped mapping returns the
    # mapping's *methods* - copy, get, items, keys, values - not its keys, so asking R for
    # the parameter names answers a different question and answers it quietly: the probe
    # reported the feature missing against an engine that has it.
    reticulate::py_eval(paste0(
      "'check_masks' in __import__('inspect')",
      ".signature(__import__('pyplatypus').Engine.__init__).parameters"
    ))
  }, error = function(e) FALSE))
}

skip_if_no_mask_check <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(
    engine_checks_masks(),
    "the engine in use predates the mask check"
  )
}

#' Does the engine in use train detectors?
#'
#' Asked of the module rather than by trying it, because building a detection engine needs
#' data on disk and "no usable samples" would read as "no feature" - the mistake the mask
#' probe made twice before it was asked in Python (see `engine_checks_masks`).
engine_does_detection <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch(
    reticulate::py_eval(
      "hasattr(__import__('pyplatypus'), 'DetectionEngine')"
    ),
    error = function(e) FALSE
  ))
}

skip_if_no_detection <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(engine_does_detection(),
                        "the engine in use predates object detection")
}

#' A tiny detection dataset in nested_dirs layout, written with the png package
#'
#' Deliberately not square and not the model's size, so the letterbox is exercised rather
#' than an identity transform.
write_detection_split <- function(root, prefix, count, seed = 1) {
  set.seed(seed)
  classes <- c("square", "bar")
  for (n in seq_len(count)) {
    key <- sprintf("%s_%d", prefix, n)
    sample_dir <- file.path(root, key)
    dir.create(file.path(sample_dir, "images"), recursive = TRUE, showWarnings = FALSE)
    dir.create(file.path(sample_dir, "annotations"), recursive = TRUE,
               showWarnings = FALSE)

    height <- 128L
    width <- 160L
    image <- array(30 / 255, dim = c(height, width, 3))
    x0 <- sample(4:50, 1)
    y0 <- sample(4:50, 1)
    side <- sample(16:38, 1)
    bar <- sample(28:56, 1)
    boxes <- list(c(x0, y0, x0 + side, y0 + side), c(96, 20, 96 + bar, 34))
    for (k in seq_along(boxes)) {
      b <- boxes[[k]]
      image[b[2]:b[4], b[1]:b[3], ] <- if (k == 1L) 220 / 255 else 120 / 255
    }
    png::writePNG(image, file.path(sample_dir, "images", paste0(key, ".png")))

    objects <- vapply(seq_along(boxes), function(k) {
      b <- boxes[[k]]
      sprintf(paste0("<object><name>%s</name><bndbox><xmin>%d</xmin><ymin>%d</ymin>",
                     "<xmax>%d</xmax><ymax>%d</ymax></bndbox></object>"),
              classes[k], b[1] + 1L, b[2] + 1L, b[3], b[4])
    }, character(1))
    writeLines(
      sprintf(paste0("<annotation><size><width>%d</width><height>%d</height>",
                     "<depth>3</depth></size>%s</annotation>"),
              width, height, paste(objects, collapse = "")),
      file.path(sample_dir, "annotations", paste0(key, ".xml"))
    )
  }
  root
}


#' Does the engine in use draw the anchor fit?
#'
#' Asked of the class rather than by calling it, because calling needs a trained detector
#' and "no model called 'd'" would read as "no feature" - the conflation the mask probe
#' made twice before it was asked in Python.
engine_has_anchor_plot <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch(
    reticulate::py_eval(
      "hasattr(__import__('pyplatypus').DetectionEngine, 'box_shapes')"
    ),
    error = function(e) FALSE
  ))
}

#' Whether this engine scores per image.
#'
#' Asked of the class, for the same reason as the anchor plot above: calling it needs a
#' trained detector and a split with annotations, and either missing would answer "no
#' feature" for a reason that has nothing to do with the feature.
engine_has_evaluate_images <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch(
    reticulate::py_eval(
      "hasattr(__import__('pyplatypus').DetectionEngine, 'evaluate_images')"
    ),
    error = function(e) FALSE
  ))
}

#' Whether this engine records which splits carry masks.
#'
#' Asked of the class, like the probes beside it: calling would need a trained model and a
#' test split, and either missing would answer "no feature" for a reason that has nothing
#' to do with the feature.
engine_has_labelled_splits <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch(
    reticulate::py_eval(
      "hasattr(__import__('pyplatypus').Engine, '_needs_masks')"
    ),
    error = function(e) FALSE
  ))
}

#' Whether this engine accepts a `split` block in the data.
#' A trained detector small enough to ask questions of
#'
#' Two epochs on the processor: the questions below are about shapes and alignment, not
#' about quality, and training five of these would cost a minute for nothing.
tiny_detection_fit <- function(envir = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = envir)
  write_detection_split(file.path(root, "train"), "train", 6, seed = 1)
  write_detection_split(file.path(root, "valid"), "valid", 3, seed = 2)

  spec <- platypus_spec(
    data = detection_data(file.path(root, "train"), file.path(root, "valid"),
                          classes = c("square", "bar")),
    models = list(yolo3("d", input_shape = c(128, 128), anchors_per_grid = 2,
                        epochs = 1, batch_size = 2)),
    seed = 1
  )
  platypus_fit(spec, device = "cpu")
}

engine_has_swa <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch(
    reticulate::py_eval(
      "hasattr(__import__('pyplatypus').spec.components, 'Swa')"
    ),
    error = function(e) FALSE
  ))
}

skip_if_no_swa <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(engine_has_swa(), "the engine in use predates swa")
}

engine_has_optional_validation <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch(
    reticulate::py_eval(
      "'validation' in __import__('pyplatypus').spec.data.DataSpec.model_fields"
    ),
    error = function(e) FALSE
  ))
}

skip_if_no_optional_validation <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(engine_has_optional_validation(),
                        "the engine in use always requires a validation set")
}

engine_has_boundary_loss <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch(
    reticulate::py_eval(
      "hasattr(__import__('pyplatypus').spec.components, 'BoundaryLoss')"
    ),
    error = function(e) FALSE
  ))
}

skip_if_no_boundary_loss <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(engine_has_boundary_loss(),
                        "the engine in use predates the boundary loss")
}

engine_has_crops <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch(
    reticulate::py_eval(
      "hasattr(__import__('pyplatypus').detection_engine.DetectionEngine, 'crops')"
    ),
    error = function(e) FALSE
  ))
}

skip_if_no_crops <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(engine_has_crops(),
                        "the engine in use predates crops()")
}

engine_has_box_loss <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch(
    reticulate::py_eval(
      "'box_loss' in __import__('pyplatypus').spec.detection.DetectionModel.model_fields"
    ),
    error = function(e) FALSE
  ))
}

skip_if_no_box_loss <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(engine_has_box_loss(),
                        "the engine in use predates box_loss")
}

engine_has_split_block <- function() {
  if (!engine_available()) return(FALSE)
  isTRUE(tryCatch(
    reticulate::py_eval(
      "'split' in __import__('pyplatypus').spec.data.DataSpec.model_fields"
    ),
    error = function(e) FALSE
  ))
}

skip_if_no_split_block <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(engine_has_split_block(),
                        "the engine in use predates the split block")
}

skip_if_no_labelled_splits <- function() {
  skip_if_no_engine()
  testthat::skip_if_not(engine_has_labelled_splits(),
                        "the engine in use predates labelled split tracking")
}

skip_if_no_evaluate_images <- function() {
  skip_if_no_detection()
  testthat::skip_if_not(engine_has_evaluate_images(),
                        "the engine in use predates per-image detection scores")
}

skip_if_no_anchor_plot <- function() {
  skip_if_no_detection()
  testthat::skip_if_not(engine_has_anchor_plot(),
                        "the engine in use predates the anchor plot")
}
