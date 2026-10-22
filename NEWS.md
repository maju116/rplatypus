# Change Log

All notable changes to this package will be documented in this file. Two things about its
shape are worth stating, because neither is the usual one.

**There is no release yet.** `remotes::install_github("maju116/rplatypus")` serves the
default branch, so "the version I had working" is a commit rather than a tag. Entries are
therefore dated rather than numbered: the heading they sit under is the version in
`DESCRIPTION`, and the `0.1.1` below it is the 2020 package this one replaced.

**Every entry names the engine it needs.** The computation lives in
[pyplatypus](https://github.com/maju116/pyplatypus) and this package pins one exact version
of it. A feature lands in the engine, the engine is published to PyPI, and only then can
this package reach it - so the pin moving is part of a change here, not housekeeping
alongside it. The pin is what stops a release of this package breaking because the engine
drifted underneath it.

## [0.2.1] - unreleased

A resubmission to CRAN after the review of `0.2.0`, and nothing else: `Description` writes
`'PyTorch'` and `'Python'` in single quotes as the policy asks, and `colormaps.Rd` gained
the `\value` tag it was missing - written in the roxygen source, so the page and the code
cannot drift. No change to any function, argument or result.

## [0.2.0] - unreleased

A different package from 0.1.1 under the same name, and the section below says how
different.

### Migrating from 0.1.1

This was in the README until 2026-10-07 - seventy lines between `## Installing` and the first
example, about a version the reader does not have, before the one they do. It is here because
this file is where R keeps what changed between versions, and because the renames table below
was a second copy of one the README already carried; the fuller of the two survived.

**Code written against the 2020 release will not run on this one.** That version built Keras
models through the R `keras` package and handed them back to you; this one describes a whole
run as a specification and computes it in PyTorch. Of the 37 functions and objects the old
version exported, **30 are gone** — including all of `yolo3()`, `darknet53()`,
`load_darknet_weights()`, `get_boxes()`, `non_max_suppression()`, `plot_boxes()`,
`segmentation_generator()` and the annotation readers.

Seven names survive, and **three of them are the ones to watch**, because they are still
exported, still callable, and mean something different:

| name | 0.1.1 | now |
|---|---|---|
| `u_net()` | `u_net(net_h, net_w, grayscale, ...)` → a Keras model | `u_net(name, input_shape, ...)` → one model in a specification |
| `plot_masks()` | `plot_masks(images_paths, masks, labels, colormap)` | `plot_masks(images, prediction, truth, ...)` |
| `loss_dice()` | no arguments, returns a Keras loss | `loss_dice(smooth = 1)`, returns a loss to name in a specification |

The other four — `binary_colormap`, `voc_colormap`, `binary_labels`, `voc_labels` — are the
same data as before.

**Object detection is back, and the names are different.** The old package handed you a Keras
YOLOv3; this one describes a detector in a specification like everything else. So those five
names are gone rather than moved, and what replaces them is:

| 0.1.1 | now |
|---|---|
| `yolo3()`, `darknet53()` | `yolo3()` as one entry in `platypus_spec()` - same name, a specification rather than a model |
| `load_darknet_weights()` | `weights = "bccd-yolo3"`, or a path, or `hf://owner/repo/file@commit` |
| `get_boxes()`, `non_max_suppression()` | done inside `predict()`, which returns boxes already suppressed and in each image's own pixels |
| `plot_boxes()` | `plot_boxes()` - same name, takes what `predict()` returns |

The annotation readers are gone as functions and are now what `detection_data()` reads for
you: Pascal VOC XML or LabelMe JSON, named rather than guessed.

The old release is still there and still installable, pinned:

```r
remotes::install_github("maju116/rplatypus@0.1.1")
```

Its source is on the `master` branch, and the issues filed against it stay open. What has aged
is its dependencies rather than its code: the pinned TensorFlow no longer installs on a current
Python, which is the reason for a rewrite rather than a consequence of one.

### 2026-10-14 - the package is `rplatypus`

#### Changed

- **`library(platypus)` is `library(rplatypus)`.** The name collided with `Platypus`,
  archived from CRAN on 2026-02-02 - unrelated work in immunology - and the two differed
  only in case, which the policy treats as a conflict and which archiving does not release.
  `cran-comments.md` had promised to resubmit under another name rather than ask for an
  exception, so this is that name rather than a new idea: one name per language, beside the
  `pyplatypus` engine on PyPI, and a name that says what the package is - the R surface over
  a Python engine.

  `rplatypus` is in neither CRAN's current index nor its archive, checked against both with
  a positive control so that the absence means something.

- **The functions did not change.** `platypus_spec()`, `platypus_fit()`, `platypus_status()`,
  `platypus_device()` and `platypus_use_torch()` keep their names, and so do the S3 classes
  `platypus_fit`, `platypus_spec`, `platypus_split` and the rest, the `platypus_*` condition
  classes, the `PLATYPUS_*` environment variables and the headers `print()` writes. The rule
  is that the package's *identity* - what `library()` and CRAN see - is `rplatypus`, and the
  *brand* is still platypus. §3A already said the S3 class keeps the prefix even where its
  constructor loses it; this is the same line drawn one level up, and it means no released
  surface moved.

- **The repository was renamed too**, to `maju116/rplatypus`. Stars, forks, watchers and
  every issue came with it - read back from the API rather than assumed - and
  `github.com/maju116/platypus` redirects, so links in other people's issue comments keep
  working. The site moved with the repository and is now at
  [maju116.github.io/rplatypus](https://maju116.github.io/rplatypus/); the former address has
  no redirect, because a project page is served under the repository's own name and the only
  way to hold the old one would be to occupy the name the redirect needs.

  The dated entries below name `maju116/platypus` where they were written that way. They are
  the record of what it was called at the time and they still resolve, so they are left alone
  rather than rewritten.

### 2026-10-14 - engine 0.8.0a22

**This file has a gap and it is named rather than backfilled.** The entry below is dated
2026-10-08 and the pin moved twice between then and here - to `0.8.0a12` for `fives-unet`
(`#151`) and to `0.8.0a20` for the instance task (`#155`) - so the dates above this heading
are not a complete record of what the pin did. Writing those entries now would be writing
them from the commit log rather than from the work, which is a different thing from having
written them; the heading says what this change is and the omission stays visible.

#### Changed

- Engine pinned to `0.8.0a22`, for two things R forwards rather than implements.

- **A regression loss is refused as any segmentation model's own `loss`, not only an instance
  model's.** `?losses` claimed the narrower rule and was measured when it was written, so it
  was true rather than wrong - the engine's refusal lived on the instance class alone, and a
  *semantic* model accepted `loss_mse()` and trained with it, reporting a validation loss of
  0.0014 for a mask that was half missing where `loss_cce()` reaches a Dice of 1.0000. The
  default `where = "foreground"` is what made that look like a success: it averages the
  objective only inside the labelled objects and leaves the background unconstrained.
  `pyplatypus#223`.

  So `available_losses()` is **ten** rows now rather than thirteen, and
  `available_losses("instance_segmentation")` is thirteen - the three regression losses are
  reachable where they have a target, which is `separation_flows(loss = )`. Nothing R sends
  changes: a configuration refused after this pin move was refused by the engine before it.

- **`evaluate()` on an instance fit carries `foreground_dice`.** It is the mask column to
  read *across* models - the binary overlap of anything the model called an object against
  anything that is one, the same arithmetic whatever the separation is. The `dice` beside it
  is a mean over the class channels the head has, three for `separation_rim()` against two
  for `separation_flows()`, so it is read down one model's rows and never across two: on the
  Data Science Bowl's validation cases it showed two masks 0.09 apart that are 0.0062 apart,
  and in the other direction. `pyplatypus#222`.

#### Fixed

- `?losses`' `task` parameter listed two tasks and there have been three since the engine's
  `0.8.0a20`.

### 2026-10-08 - engine 0.8.0a2

#### Added

- **`metric_cldice()`**, for structures where Dice asks the wrong question. It scores each
  mask against the other's skeleton, so it measures whether a vessel is *connected* rather
  than whether its pixels coincide. Vessels, airways, neurons, cracks, catheters.

  The two disagree in a way worth knowing, measured on a nine-pixel vessel: one drawn two
  pixels thin scores Dice **0.875**, and the same vessel severed in the middle scores
  **0.947** - Dice prefers the severed one. clDice gives them 1.000 and 0.943. Its limit is
  measured too: at one pixel wide, a one-pixel displacement leaves no overlap at all and
  every overlap-based metric reads 0, this one included.

  `include_background` defaults to `FALSE` here and `TRUE` for the other three. The
  background's skeleton lies inside the background by construction, so that class scores 1
  whatever the model did.

#### Changed

- Engine pinned to `0.8.0a2`.

### 2026-10-08 - engine 0.8.0a1

#### Added

- **`drawing_style()`**, the five decisions every figure in this package makes when you do
  not give it one: which colours mean found, missed and invented, how much of the image an
  overlay lets through, how a box is labelled, and which boxes are worth drawing. Reach for
  it when you want to match a figure rather than restate it -
  `colours = drawing_style()$box_colours` keeps one source where typing the hex codes
  starts a second.

#### Changed

- **The drawing decisions now come from the engine.** They were written out in ten places
  across `R/plot.R` and `R/masks.R`, and `pyplatypus.style` held the same five values -
  which is two copies that happened to agree, not one source. They agreed because five
  differences between the two packages' figures had been found by laying them side by side
  and fixing them by hand.

  Nothing changes in any picture: the values are identical, and a test compares every one
  of them against the engine's, so a change on that side now fails this package's CI
  instead of being noticed by eye.

  **Drawing still needs no Python.** That is why the values are mirrored in `R/style.R`
  rather than fetched: `plot_masks()`, `plot_boxes()` and `overlay_agreement()` return
  without touching the bridge, and a default colour that called the engine would mean a
  five-gigabyte download to draw a mask.

### 2026-10-07 - engine 0.6.0a2, then 0.6.0a4, then 0.7.0a1

#### Changed, and it breaks code

 - **Eight functions were renamed.** The engine and this package had grown two words for the
   same thing in eight places, and a reader moving between the halves paid for every one.
   One name per concept now, and where the two disagreed **the engine's name won**, because
   it is the layer that cannot be renamed later without changing the configuration format
   and the schema. The exception is `available_transforms()`, where this package already had
   a family of `available_*` names and the engine followed instead.

   | was | is | why |
   |---|---|---|
   | `platypus_split()` | `split_dataset()` | the engine's name. The S3 **class** is still `platypus_split` - that is the object's identity, and every class here is prefixed |
   | `split_files()` | `split_path()` | it reads one split's path; it does not split files. `split_samples()` in the engine is a different function, and the two names invited pairing them |
   | `mask_report()` | `inspect_masks()` | the engine's name, and the method it calls |
   | `mask_classes()` | `colours_to_classes()` | the engine's name, and it says which way the conversion goes |
   | `mask_colours()` | `classes_to_colours()` | likewise. Note the engine's `onehot_to_colours()` is **not** this function - it takes probabilities and argmaxes them, this takes class indices |
   | `save_weights()` | `export_weights()` | the engine's name; "export" says a sidecar is written beside the file |
   | `available_augmentations()` | `available_transforms()` | the engine's name, and albumentations' own word for them |
   | `augment()` | `augmentation_step()` | `augment` is a generic in **broom** and means something else there. `augmentation` alone would have shadowed the `augmentation =` argument it builds a list for |

   No aliases: two names for one thing is what this removes. The S3 **class** returned by
   `split_dataset()` is still `platypus_split` - that is the object's identity, and every
   class in the package is prefixed.

   `evaluate()`, `evaluate_cases()`, `evaluate_classes()` and `evaluate_images()` keep their names
   and so does `platypus_fit()`. The prefix on that one is not an inconsistency: `fit` is a generic
   in the tidymodels packages, so a bare `fit` would have been theirs to own, while `evaluate` is a
   generic here and dispatches on the fit's class whichever package was attached last.

 - `PYPLATYPUS_VERSION` is `pyplatypus_version`. It was the only ALL-CAPS name in the
   package, so keeping it would have meant a lint exception for a style used exactly once.

#### Added

 - **`callback_swa()`**: average the weights over the last part of the run. What it is worth
   is not in the score column - Dice and per-case error do not move - it is in the spread.
   Measured over three seeds, the volume bias went from `+4.5% / +12.2% / -11.6%` to
   `-0.1% / +4.2% / +2.1%`, 5.7 times tighter. The help page says so in those words, because
   somebody reading "weight averaging" will look at Dice, find nothing, and conclude wrongly.
   Refused beside `callback_cosine_annealing()`: a cosine has decayed to its floor by the
   time averaging begins, so the average is the last epoch.

 - **`segmentation_data(validation = FALSE)`**: say a run has no validation set. The third
   answer to the question a path and a split already answered, and it had to be a stated
   value rather than an absence, because "I have no validation set" and "I forgot" look
   identical and only one of them is a decision. It went in the same argument rather than a
   new one, so nothing can contradict it.

#### Fixed

 - The Python shim shipped inside this package is now formatted and linted by ruff in CI,
   beside lintr. It had never been.

### 2026-10-07 - the documentation site

 - **The site is Quarto, not pkgdown**, generated from `tools/reference-groups.yml` into a
   sidebar nested in eight groups, and themed from a `_brand.yml` that is byte-identical to
   pyplatypus's - so the two sites look alike by construction rather than by anybody
   remembering to copy a colour.
 - **Every old address still works.** 105 redirect stubs cover all 99 addresses the pkgdown
   site published, the eight renames among them.

### 2026-10-06 - engine 0.5.0a1 through 0.6.0a1

#### Added

 - **`segmentation_data(split = )`** and `detection_data(split = )`: divide one training
   folder into splits without writing any files. The argument is a list of `fractions` (two
   numbers, or three to cut a test set too) and `group_by`, which is a **required key that
   may be `NULL`**. The mistake it prevents leaves no trace: slices of one patient on both
   sides make validation measure memory rather than generalisation, and nothing in the output
   says so. An omitted key would be that choice made silently; `NULL` is the same choice made
   on purpose. For detection this is the only way to divide one folder, because
   `split_dataset()` writes a `masks` column.
 - **`detection_crops()`**: cut the detected objects out of the images they were found in, at
   a fixed size, for handing to a classifier. Crops come from the source image through the
   same reader the dataset uses, are rounded outward so the whole box survives, and
   letterbox rather than stretch.
 - **`yolo3(box_loss = "giou")`**. Measured on BCCD over three seeds, 150 epochs, it is
   *worse* on the metric it targets - matched overlap 0.7929 against 0.8038, established at
   2.7 standard errors - and its spread is sixty times wider. It ships because its
   coordinate term reads zero when the boxes are right, where the default term cannot reach
   zero however right they are. `?yolo3` leads with that table, because the name invites
   choosing it and the measured answer is the other way.
 - **`loss_boundary()`**: a region loss plus the signed distance to the truth's boundary.
   `region` and `alpha` default to `NULL` here and are left out of the request, so the
   engine's own defaults apply - `alpha = 0.9`, which it pins with a test, because at 0.5 the
   surface term owns half the objective while the prediction is still random and the volume
   bias spread goes to +/-28%. What the loss trades is accuracy per case for being unbiased
   over a series: measured over three seeds, the systematic volume bias went from -5.18% to
   -0.06% and the per-case absolute error from 16.90% to 22.17%.

#### Fixed

 - Every help page has an `\examples` section but one - 47 of 48 at the time, `encoders`
   being a concept page with no `\usage` - and a test parses every example in every `.Rd`,
   including inside `\dontrun{}`, and fails if it names a function that does not exist. What
   was at risk was never the functionality; it is the example *text* drifting from the API.
 - lintr runs over the package in CI and gates on its findings. Of 906 findings at lintr's
   defaults, 890 were the 80-character line limit this package does not use; at 100
   characters and `lint_package()`, 25 - two of which were defects rather than style.

### 2026-10-05 - engine 0.3.0a15, then 0.4.0a1

 - **`evaluate_images()`**: one row per image for a detector - `n_truth`, `n_predicted`,
   `matched`, `missed`, `spurious`, `mean_matched_iou`. Order by `missed` for the frames it
   cannot see, by `mean_matched_iou` for the ones where it finds everything and places it
   badly. No average precision per image: AP is the area under a ranking's curve and on one
   picture it moves on a single box.
 - **`platypus_spec(task = )`** can be stated, and is checked rather than trusted - it can
   confirm or refuse, never override. Unset, it is still derived from the constructors.
   Required in YAML and optional here is not an inconsistency: `task` is needed exactly where
   the type is not already stated, and `segmentation_data()` with `u_net()` can only mean one
   thing.

### 2026-10-04 - engine 0.3.0a12, then 0.3.0a13

 - **Object detection, from R.** `detection_data()`, `yolo3()`, `detection_anchors()`,
   `plot_boxes()`, and `predict()` returning a list of boxes in each image's own pixels -
   not an array, because images differ in size, so does the number of boxes, and a box in a
   letterboxed frame cannot be drawn on the photograph it came from.
 - **`plot_anchors()`**: the fitted anchors against the boxes they were fitted to. It is in
   the vignette twice, on the split they were fitted on and the one they were not.
 - A README figure for detection, drawn by the published `bccd-yolo3` with no training, and
   `tools/readme_figures.R` that reproduces it.
 - **Corrected**: the claim that COCO's anchors cover BCCD's boxes at 0.67 where fitted ones
   reach 0.92. Re-measured on the 2,805 real training boxes, the honest pair is **0.65
   against 0.88**. The direction survives and is large; both numbers were wrong in opposite
   directions and the gap was right by coincidence.

### 2026-10-03 - engine 0.3.0a10, then 0.3.0a11

 - **`u_net(encoder = "resnet34", pretrained = TRUE)`**, with `freeze_encoder` and
   `encoder_learning_rate`. `pretrained` is a separate explicit flag so that naming a
   backbone never downloads anything nobody asked for. Measured on three datasets,
   pretraining never clearly beats the built-in encoder; what it buys is epochs, and what a
   swappable encoder buys is capacity where the target is thin. The help page carries the
   table.
 - **`inspect_masks()`** and `platypus_fit(check_masks = FALSE)`: a declared class appearing
   in no mask has a target channel that is zero everywhere, so the model is never shown what
   it is being asked to find, and `platypus_fit()` now refuses on it. A threshold on the
   unmatched fraction cannot do this job - on a 0.6% lesion a wholly wrong colormap is
   quieter than JPEG artefacts in healthy data.
 - **Every help page renders its markdown.** `DESCRIPTION` had no
   `Roxygen: list(markdown = TRUE)` although every page had been written in markdown since
   the rewrite began, so not one cross-reference was a link: 0 to 42 links, 0 to 266 inline
   code spans, 36 of 40 pages changed. Nothing in the sources was wrong; nothing was
   converting them.

### 2026-09-27 - engine 0.3.0a6, then 0.3.0a8

 - **`predict(space = "source")`**: map a prediction back out of the model's grid onto the
   grid of the scan it came from, undoing the resampling and the crop. Returns a list, and
   the type change is the API being honest - scans differ in size, and quietly resizing them
   to match is how a mask ends up describing anatomy it was not computed from.
 - **Named weights.** `weights = "dsbowl-unet"` from the registry, `hf://owner/repo/file@commit`,
   or a local path, plus `export_weights()` for your own. A registry name carries a commit
   and the `hf://` form requires one, because weights that change under a stable name are the
   worst kind of irreproducibility.
 - The Data Science Bowl vignette now opens with a mask in four lines - published weights,
   `fit = FALSE`, `plot_masks()` - before any mention of training. First contact should not
   need a GPU and an afternoon.
 - **Fixed, and found by writing that vignette:** `weights = "dsbowl-unet"` could not work
   from R at all. The bridge asked for `pyplatypus` with no extras, so `huggingface_hub` was
   never in the environment reticulate builds. Nothing in either test suite could have caught
   it - the engine's tests install the extra deliberately and the R tests ran where it was
   already present.
 - The README says what changed since 0.1.1, written by diffing the two `NAMESPACE` files
   rather than from memory: of 0.1.1's 37 exports, 30 are gone, and three of the seven
   survivors are worse than gone because they are still callable and mean something else.

### 2026-09-26 - engine 0.2.0a2 through 0.3.0a5

The day the package stopped being a bridge and became a surface. Five engine releases, each
followed here.

 - **A worked vignette** on the Data Science Bowl, precomputed so that reading it needs no
   GPU, and a README.
 - **Continuous integration**: five `R CMD check` jobs - Ubuntu on R devel, release and
   oldrel-1, plus macOS and Windows on release - and an `engine` job that installs the built
   package and runs the suite against the engine resolved from PyPI. That last one is the
   job that matters: `pkgload::load_all()` exposes a package's internals, `library()` does
   not, and local work had been using the most permissive of the three ways a test can
   reach them.
 - **Plotting and masks**: `plot_masks()`, `plot_boxes()`, `overlay_mask()`,
   `overlay_agreement()`, `read_masks()`, `unite_masks()`, `mask_coverage()`.
 - **DICOM**, properly: modality LUT, a fixed window, MONOCHROME1 inverted. Plus
   `series_report()` for a folder of slices, whose decision is that **a problem is a column,
   not an exception** - a hundred cases contain a few bad ones, and stopping at the first
   turns an afternoon into a week.
 - **Splitting by patient** (`split_dataset()`, `split_path()`) and `evaluate_cases()`.
 - **Volumes.** `input_shape = c(64, 64, 32)` had been building a 3D U-Net since the first
   release; what was missing was reading NIfTI, where orientation is the whole problem, and
   `labels` as a second way to describe a mask, because volumes label with integers.
   `save_volumes()` writes NIfTI **carrying the affine of the scan the mask was predicted
   from** - without it a mask cannot be laid over its scan by any viewer, and the file looks
   perfectly normal while being wrong. `mask_volume()` reports millilitres, because a voxel
   count is meaningless outside one scanner.
 - **`target_spacing`**: resample to a common voxel size. What makes it necessary is not
   slice thickness but field of view - forty slices of 1 mm is 40 mm of patient and forty of
   2.5 mm is 100 mm, which is the ordinary state of clinical data.
 - **`channels_from`**: one channel per file, stating the order and never inferring it. A
   model trained with FLAIR in channel one and used where channel one is T1 answers
   plausibly, with the right shape and range, and nothing downstream can tell.
 - **Augmentation in 3D**, and `available_transforms(rank = 3)` to say what is usable - 97 of
   albumentations' transforms accept a volume and the rest raise from inside the library.
 - A second vignette, on volumes, which generates its own data. It ends on a model at **Dice
   0.88 whose volumes are 12-23% too large**, which is the argument for reporting volume
   beside overlap: Dice is dominated by an object's interior and forgiving about its
   boundary.
 - `segmentation_data(window = )` replaced `dicom_window`, since NIfTI needs the same
   thing. The old name is still accepted; giving both is an error.

### 2026-09-25 - engine 0.2.0a1

The package exists.

 - **The bridge.** `py_require()` plus uv, resolving an isolated ephemeral environment at
   `library(rplatypus)` - deliberately not the shared-Python arrangement that broke this
   package's Keras stack in 2020. `platypus_status()` says what it found rather than leaving
   a failed import to be guessed at, and `PLATYPUS_ENGINE_PATH` points the bridge at a source
   tree during development.
 - **`platypus_spec()`**, built either from arguments or from a YAML file and producing the
   same thing. One pipeline, two constructors.
 - **`platypus_fit()`**, `evaluate()`, `predict()`, `training_history()`, and the engine's
   complaints translated into R conditions rather than passed through as Python tracebacks.

## [0.1.1] - 2020-10-17

The last release of the TensorFlow package, kept here for the record rather than as an
ancestor of the entries above. It built Keras models through the R `keras` package: `yolo3()`
and `darknet53()` with `load_darknet_weights()` for the original Darknet weights, a plain
`u_net()`, `segmentation_generator()`, `loss_dice()`, the COCO and VOC colormaps, and
readers for LabelMe JSON and Pascal VOC XML.

It is still installable and still pinned:

```r
remotes::install_github("maju116/rplatypus@0.1.1")
```

Its source is on the `master` branch and the issues filed against it stay open. What has
aged is its dependencies rather than its code - the pinned TensorFlow no longer installs on
a current Python, which is the reason for a rewrite rather than a consequence of one.
