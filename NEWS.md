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

## [0.3.0] - unreleased

### 2026-10-29 (evening) - the seam, and a class that went missing (engine `0.8.0a56`)

**Five findings from the reviewer's second pass. Four are the same shape - this package
answered a question the engine already answers, and the two disagreed - and the fifth is
this package's own arithmetic.** No engine release: the pin stays at `0.8.0a56` because
every fix is on this side.

**`predict()` with `type = "class"` was refused for `regions` and computed for
`classes_from`.** `maju116/rplatypus#252`. Both namings make a pixel's classes independent -
the engine has one switch for it and its own documentation says everything downstream reads
that rather than either field - and this package read `regions`. So a `classes_from` fit
returned the most likely channel over sigmoids with **no background channel**, which gives
every background pixel a class. Nothing downstream could see it: `save_class_masks()`
detects an overlap from a probability array and a class map has none.

Measured on a 4-sample 32x32 fixture with two binary mask files each: the call returned a
`4 x 32 x 32` array holding only 1 and 2, with a pixel outside both masks given class 2 on
probabilities of 0.497-0.500 and 0.499-0.527. The control is the same pictures written as
one label map with `regions`, which was refused. The refusal also names the naming the
caller actually wrote now, where it said `regions` whatever had been given.

**`print()` of a specification said `classes : 0` for three of the four namings.**
`maju116/rplatypus#256`. It counted the colormap's length, which only `colormap` fills, so
`labels`, `regions` and `classes_from` all printed zero on the one summary a user prints
first - and it reads as *the classes were not understood*. The count comes from the engine
now: `labels = c(0, 1, 2)` prints 3, with `voc_colormap`'s 21 as the control.

**A misspelt key in `split` was accepted here and refused by name in a YAML file.**
`maju116/rplatypus#253`. The block was rebuilt from `fractions`, `group_by` and `seed` and
everything else dropped, so `sed = 7` reached the engine as a seed of 0 - an unseeded run
whose author believes it is seeded. Worse, `$` on an R list matches a name by **prefix**, so
`seeds = 7` was read as `seed` and simply worked. Both are refused by the engine now,
because unknown keys are forwarded rather than discarded, and `[[` replaces `$`.

The two halves are separate claims and the forwarding one hides the other, which the
mutation batch is what showed: with every key forwarded, putting `$` back failed nothing.
So the prefix is asserted against what this package **sends** rather than against the
engine's answer - and the first draft of that test used `$` and reported the field as set,
which is the defect demonstrating itself.

**A fractional whole number was truncated in silence.** `maju116/rplatypus#254`.
`as.integer(1.5)` is 1, so `labels = c(0, 1.5)` became `c(0, 1)` and a colormap entry of
255.9 became 255 - a *different valid value* rather than a message, where the engine refuses
a number with a fractional part by name. The comment above that coercion had always said it
was there so nobody "gets a puzzling message from a library they never invoked", which
described the intention and not the code. The test is `trunc`, which `segmentation_data()`
has always used for `regions`.

**And one finding is not about the seam at all: `mask_coverage()` hid a class with no
pixels.** `maju116/rplatypus#255`. `tabulate()` sizes its table by the largest value it
sees, so a declared class above that got no row - and `?mask_coverage`'s own example says a
class with 0 pixels *"is the thing to look for"*. With `labels = c("bg", "liver", "tumour")`
a mask holding only 1 and 2 returned **two** rows; a mask holding 1 and 3 returned three,
with liver at 0, which is the control that says the last row was the only one affected. The
highest-numbered class is the usual position of a rare foreground, so the row that
disappeared was the one worth reading. The count now comes from `n_class` if given, then
from `labels`, and only then from the mask.

No field's description moved, so the field-prose ledger is unchanged and no `@param` needed
re-reading.

### 2026-10-29 - the pin, and the metric that path was built for (engine `0.8.0a56`)

**The pin moves to `0.8.0a56`, which is a defect reaching an R user and nothing else.**
`maju116/rplatypus#247`: `evaluate()` and `evaluate_cases()` with `at = "source"` raised a
`ValueError` for `cldice` and `surface_dice`, naming neither the metric nor `at` - and
`?evaluate` calls that route *"the answer to that warning"*. The whole fix is the engine's,
so this is §3E's *None beyond the pin* in the version that costs somebody something, the
same shape as `0.8.0a47` and `a48`.

Measured on the engine's side before the release: four 64x64 cases with `[dice]` returned a
number on both grids while `[dice, cldice]` raised on `at = "source"` from both functions,
with the `dice`-only row as the control. After: `cldice` 0.28 on the model grid and 0.4839
at source, which is two grids giving two numbers - what the route exists for.

**It is `a56` rather than `a55` because `a55` carried a regression this package found.**
`0.8.0a55` made the engine's IoU matrix index the object numbers *present* rather than
`1..max`, and the engine's own agreement overlay still mapped a row back with `row + 1` - so
an agreement figure over a label map with a gap coloured the wrong objects. What caught it
is `test-instance-drawing.R`, which compares `overlay_instance_agreement()`'s output with
this package's own pixel for pixel and carries a fixture named `gapped`, whose comment says
that taking `seq_len(max(labels))` instead of the values present *changes nothing* - true
here, and untrue there from that release until `a56`.

So this package held the correct copy of that rule the whole time: `matched_objects()` has
always taken `sort(unique(...))` of each side. That is the second time the engine was the
wrong copy and the first time in code rather than prose, and the pair is what reported it.

The field-prose ledger was regenerated for the new pin and the diff is **two lines**, both
the recorded engine version: no field's description moved, so no `@param` needed re-reading.

### 2026-10-29 - the review's R half: two guards that described more than they held

The review agent's first audit produced nine findings and three of them are R's.
`maju116/rplatypus#248` and `#249` are here; `#247` waits on the engine release that carries
its fix. The whole audit is in the workbench's `REVIEWER_FINDINGS.md`, and each finding was
reproduced independently before it was filed.

#### Fixed

- **Every callback default is compared with the engine's now**, which `#248` found nobody
  doing. `test-component-defaults.R` opens with *"Every default this package writes down is
  one the engine also writes down"* and selected `^(loss|metric)_`, so the callback
  constructors were outside it - **twelve of them**, not the eight the finding counted, and
  they send their values unconditionally, so an engine that changed a default would be
  silently overruled for every R user who did not pass the argument.

  There was no drift: all twelve agree today, which is the only reason this is a widened
  guard rather than a bug. Three mutations, three caught, and the comparison is driven by
  the engine's **callbacks union** - the `oneOf` of a model's `callbacks` field - rather than
  by a list written down here. A callback cannot be found by the suffix the loss and metric
  loop uses, because its schema key is `EarlyStopping` with no family in it, and the tag
  alone collides: `dice` is both a loss and a metric.

  The test asserts both directions - a callback the engine gained and this package has not
  fails too - and counts how many defaults it actually compared, because a run in which
  every default happened to be `NULL` would skip every comparison and report green.

- **No runnable example reaches the engine, over every help page**, which is what §3F's row
  has claimed and what `#249` found it was not. The test it named looped over a literal
  `c("mask_volume", "instance_sizes", "mask_coverage")` and searched each one's own body, so
  a new export with a runnable example reaching `shim()` passed it, and so did a helper one
  level down.

  `test-runnable-examples.R` parses all **72** `man/*.Rd`, drops the `\dontrun{}` blocks -
  the one thing CRAN does not run - collects the exported names used in what is left, and
  follows each one's **call graph** through the namespace. Measured: 0 pages reach the bridge,
  0 failed to parse, and **29 reach it when `\dontrun` is kept**, which is the control that
  the scan is not vacuous.

  Three mutations, three caught, including a runnable example planted into `mask_volume.Rd`
  that calls a function which forwards. That is the case the three-name loop could not see,
  and §4's reason it matters: `R CMD check` runs every example not in `\dontrun{}`, this
  machine has the engine, so the check is green here and CRAN would be the first to fail.

  The three-name loop stays, because *those* pages are runnable on purpose, which is a
  stronger statement than the general property.

### 2026-10-28 - a split nobody labelled, and the one shape that can say so (engine `0.8.0a53`)

**The pin moves to `0.8.0a53`, one move for two releases.** `0.8.0a52` made an unlabelled
classification test split reachable - a CSV of `key, images`, which is the ordinary shape of
a prediction set - and this package needed a representation for it. `a53` is a defect an R
user meets through `predict(fit, split = "train")` and whose fix arrives by the pin moving
and by nothing else, so the ratchet carries both rather than moving twice.
`maju116/rplatypus#245`, `maju116/pyplatypus#320` and `#321`.

#### Fixed

- **`predict()`'s long form said *none of the findings* where the truth was *nobody
  said***. For a label that is a set the frame carries one row per image per class, and
  `label` was `classes %in% as.character(unlist(row$labels))` - which is `FALSE` for every
  class both when the image carries none of them and when nothing labelled it at all. Both
  states reduce to `character(0)` on the way in, so the comparison cannot tell them apart.

  The comment above that branch is what made it a defect rather than a gap: it argues for
  long form over a wide frame and a list column precisely because long form is *"the only
  shape in which 'this image has none of the findings' is four rows of FALSE rather than an
  empty cell that could also mean unread"*. That property only holds while `FALSE` means
  *measured and absent*. `label` is `NA` now when the engine said nothing, read from the
  `NULL` rather than from the emptiness, and the column stays logical so `tapply()` and
  `table()` go on working.

  One test holds both halves, because neither means anything alone: an unlabelled split is
  `NA` throughout, and a film carrying no finding at all stays `FALSE` twice. Three
  mutations, three caught - including the one that makes *every* row `NA`, which is the
  same defect with the sign reversed.

  The route a single label takes was already right and already documented: `rows_to_frame()`
  maps an absent cell to `NA`, and the comment there said *"`label` is NA on a split that
  carries no labelling, which is what a test set often is"* - a sentence describing a state
  this package could not reach until `0.8.0a52`, and true now rather than aspirational.

#### Changed

- **`class_balance()`'s `split` argument says what an unlabelled split does.** The engine
  refuses one by name since `0.8.0a52`, because counted anyway it reports every class at
  zero and reads as a finding about the dataset. `?class_balance` named `"test"` as a split
  to count and said nothing about this, which is the prose going stale in the direction of
  the work having been done one package over. A receipt test asserts the refusal arrives
  here, with the same call on a labelled split as its control.

### 2026-10-28 - a label that is a set, from R (engine `0.8.0a51`)

**The pin moves to `0.8.0a51`, one move for two releases.** `0.8.0a50` shipped `labels_from`
and this package needed it; `a51` fixed two defects this package needed nothing from, so the
ratchet carries it along rather than moving twice. `maju116/rplatypus#241`.

#### Added

- **`classification_data(labels_from = )`**: one CSV column per class, in class order, each
  cell `0` or `1` - the layout for a label that is a **set** rather than one of a list of
  alternatives. A chest film with four findings is four independent questions.

  It is a naming rather than a switch, for the reason `regions` and `classes_from` are on the
  mask side: the *target* changes and not only the activation, so there was nothing a
  `multilabel = TRUE` could have meant on a `label` column that structurally cannot say an
  image has two findings.

  **Position is the pairing**, so the CSV's headers may be called whatever the dataset calls
  them and the model still learns the classes in the order `classes` names them. Four
  refusals are duplicated here rather than forwarded, for the reason the `subdirs` one is -
  the sentence is the engine's own and this way no interpreter starts to deliver it:
  `nested_dirs`, which cannot express a set at all; fewer than two columns; `strict_labels`,
  which has nothing to choose between when the columns *are* the classes; and a column count
  that disagrees with `classes`. Each has a control asserting the same call is accepted
  without the thing being refused.

- **`predict()` answers in a different shape on that route, because the answer is a
  different kind of thing**: one row per image *per class*, with `key`, `class`, and `label`
  and `predicted` as logicals.

  The alternatives were weighed against what a reader does with it rather than chosen. A
  wide frame needs two columns per class and names them by pasting, which is how a class
  called `Mass_label` becomes ambiguous. A list column holds the sets and nothing in base R
  aggregates it. Long form joins by `key`, summarises per class with one `tapply`, and is
  the only shape in which *this image has none of the findings* is a row of `FALSE` rather
  than an empty cell that could also mean unread.

  `type = "probability"` needs no branch and got none: the `p_<class>` keys are in both
  shapes. There is no `probability` column in the frame, and that is the engine's decision
  rather than an omission here - that column is the chosen class's own number, and with
  independent questions nothing was chosen.

#### Fixed

- **Two pieces of prose the field-prose ledger asked about**, which is the third time that
  mechanism has paid for itself and the second time what it found was not the field it
  named. The engine rewrote three descriptions in `0.8.0a50`; re-reading R's own prose for
  each turned up that `?classification_data`'s **title** said *the one label each of them
  carries*, which `labels_from` makes false, and that `?losses` described `gamma` as
  discounting *the pixels already classified well* when focal loss applies to a whole image
  as well. `strict_labels` was the third, and R's prose for it was written in this change,
  so it was already right.

  What the ledger asks for is the re-reading, not the regenerated digest: a ledger
  regenerated without reading is a rubber stamp, and its own failure message says so.

#### Documentation

- **The configuration guide gains `### When the label is a set: labels_from` on both
  sides**, with the YAML block validated by a test in each suite and the code block beside
  it. Measured rather than assumed: both suites pin only `##` headings, by `^## (.+)$`, so a
  subsection moves neither list and the two halves needed no merge ordering - which is what
  the issue had predicted they would.

### 2026-10-28 - nothing is inferred from silence (engine `0.8.0a49`, the pin does not move)

**No engine change and no pin move.** `platypus_spec()` accepts a plain list of fields in
`data` as well as one of the four constructors, and that route could describe **one task out
of four**. `maju116/rplatypus#239`.

#### Fixed

- **A bare `data` list named a task nobody had chosen, and a stated `task` was refused for
  disagreeing with it.** `task_of()` answered `"semantic_segmentation"` for any object with
  no task attribute, and `segmentation_data()` carried none - so the constructor and a plain
  list were the same object to the inference, which therefore always had an answer. Measured
  with the one that works as the control:

  ```
                                         before                       after
  bare list + bare model, task stated    REFUSED, all three tasks     the stated task
  bare list + classifier()               REFUSED as "mixing" tasks    classification
  bare list + yolo3()                    REFUSED as "mixing" tasks    object_detection
  bare list + bare model, nothing said   semantic_segmentation        unchanged
  segmentation_data() + u_net()          semantic_segmentation        unchanged
  ```

  The second and third rows are the half the issue did not report: a model that names its
  task unambiguously was overruled by a data block that had named nothing, and the refusal
  said the specification *mixes* two tasks when only one of them had been named at all.

  **Every constructor tags itself now**, including `segmentation_data()` and the four
  U-shaped model constructors, which both used to lean on that default. So an absent tag
  means *this object says nothing* rather than *this object says segmentation*, and the
  inference is taken over the objects that spoke. What a stated `task` is trusted for is
  precisely the absence of evidence - **not** the presence of the argument: with
  `segmentation_data()` and `u_net()`, a stated `"object_detection"` is still two intentions
  in one specification and still refused, and there is a test on that pair.

  One state the bare route can now reach and a constructor cannot: a model admissible for
  two tasks - a U-shaped one with `weights` and no `separation`, which pyplatypus `0.8.0a28`
  permits because the sidecar records what the channels predict - beside a data block that
  says nothing. That is refused naming the choice rather than guessed at, because a guess
  here is the fallback `agreed_task()`'s own comments argue against.

  The refusal's wording also learnt the word for a side that said nothing; it used to print
  the inferred task unconditionally, which is now `NULL`.

#### Documentation

- **`?platypus_spec` describes the bare-list route**, which existed, worked for one task and
  was documented nowhere - `@param data` named the four constructors and a YAML path, and a
  plain list is neither. That is why it went unnoticed since detection shipped. The page says
  what names the task on that route and why a constructor is still the better one: it refuses
  a wrong field here rather than across the bridge, and the fields it refuses are most of
  what it is for.

### 2026-10-28 - one label per image, from R (engine `0.8.0a49`)

**The pin moves to `0.8.0a49`, and this is the first release this package could not take by
moving the pin alone.** `platypus_spec()` sends a YAML file or a bare `data` list straight
to the engine's validator, so a pin at `0.8.0a49` with no constructors would have accepted
`task: classification` from a file and refused it from `classification_data()` - one
configuration with two answers, which is the divergence recorded for `regions` in
`0.8.0a28`. So the pin and the surface arrive together, and a test holds the two paths to
the same specification.

`classification_data()` and `classifier()` are the two new constructors.
`classification_data()` is as much the fields it has not got as the two it adds: `colormap`,
`labels`, `regions`, `classes_from`, `channels_from` and `target_spacing` all describe a
mask or a grid, and a label is neither. `classifier()` is **the one model constructor in
this package not named after an architecture** - a classifier has nothing after the pooling
but a dense layer, so the contracting path is the architecture and `encoder` is the whole
answer.

**Four metrics of their own, and the default is measured rather than chosen.**
`metric_auc()`, `metric_accuracy()`, `metric_balanced_accuracy()` and `metric_f1()` share no
name with the mask metrics. `auc` is the engine's default because at a 3% prevalence a
calibrated model never crosses the threshold: everything read off the hard prediction sees
the same all-negative answer, so accuracy spans 0.0100 across models whose AUC spans 0.4631
and is not even monotone in their quality. `class_balance()` is the function that makes that
prevalence visible before a run rather than after it, and it prints the engine's own remark
instead of a copy of its threshold.

**`predict()` answers per image and is joinable.** `type = "class"` gives a row per image
with `key`, `label`, `predicted` and `probability`; `type = "probability"` gives a matrix of
images by classes with the keys as row names. Named rather than ordered, which is the lesson
`predict(space = "source")` cost on the semantic side: a prediction handed back as a bare
sequence has to be paired with whatever else the caller holds by position.

**What is refused, by name, is as much of this as what is returned.** `space` and the
`cases`/`each` pair describe a grid and a split of masks too large to hold at once, and
neither means anything for one label per image. `evaluate(at = )` is refused for the same
reason. `evaluate_cases()` is refused for a different one: a case here is one image whose
score is 0 or 1, so a split's worst case is 0 for any model that gets a single image wrong -
a number that carries nothing while reading like one that does.

**Two defects found by doing this rather than by any test.** The shim dropped the
`check_masks` option for a detection specification by comparing the task against
`"detection"`, where the value is `"object_detection"` - so the branch never fired, the
option reached an engine that has no such argument, and the `TypeError` was reported as
*this engine predates `check_masks`* about an engine that is current. And `predict()`'s
`decode` guard sat below the task branches, so a detection fit - the one branch that returns
before reaching it - accepted `decode` and silently ignored it. Both are fixed here, because
classification is the second task in the first position and would have inherited both.

`?metrics` also gains the prose it never had: it was `A list of metrics, see [metrics].`
against seven hundred characters in the engine, and the sentence it was missing is a
mechanism - a callback watching `val_<metric>` is refused when nothing in the list will
produce it.

### 2026-10-26 - every object's shape, not just the whole mask's (engine `0.8.0a46`)

**The pin moves to `0.8.0a46`, and what it brings is a measurement the engine could not make
per object.** `ellipse_measure()` fits an ellipse to a *whole* mask, which is what a fetal
head circumference needs and not what a field of nuclei needs. The engine now has
`instance_shapes()`: one row per object out of one label map, beside the rows
`instance_sizes()` already gives, with the semi-axes largest first and - for an image -
`eccentricity`, which is the number shape analysis reports.

**`instance_shapes()` is on this side too, and it forwards** - the way `ellipse_measure()`
does and unlike `instance_sizes()`, which stays R's own arithmetic. That split is not a style
choice: a count times a product needs no Python and a reader can verify it by eye, while an
eigendecomposition per object cannot be reimplemented here without becoming a second
implementation. The visible consequence is that this page's example is wrapped in
`\dontrun{}` and `instance_sizes()`'s is not, because `R CMD check` runs examples and CRAN
has no interpreter.

It is per object **in one pass**, which is the whole reason it exists rather than being a
line in the documentation: calling `ellipse_measure()` on `labels == k` once per object
rescans the whole array every time, and on a 512 by 512 map of 1939 objects that is 1989 ms
against 143.

**One thing to know before calling it through the bridge, because it is the trap and not a
detail.** `eccentricity` is unitless and it is **not** spacing-free: it describes whichever
space it was computed in, so on anisotropic voxels the grid and the millimetres disagree
completely, in both directions.

    a circle of 80 px at spacing (2, 1)       grid 0.0000    mm 0.8660
    an 80 by 40 px ellipse at spacing (1, 2)  grid 0.8667    mm 0.0685

The second row is physically almost a circle and the grid calls it strongly elongated. The
engine says which space a row is in through the key names - `major_px` and `minor_px` without
a spacing, `major_mm` and `minor_mm` with one - so pass your voxel size and read the `_mm`
keys unless you mean the grid. `platypus_device()` is unaffected and so is everything else:
this release adds a function and changes none.

A volume gets three axes and no eccentricity, because an ellipsoid has no single one.

### 2026-10-26 - what an image reader is allowed to decode, and Python 3.11 (engine `0.8.0a44`)

**A file is now read as a picture only if its contents are PNG, JPEG, TIFF, BMP or GIF.**
Nothing about how you name your files changes, and that is the point: the engine's reader
identified a file by its *contents* and was handed nothing but a path, so a file carrying any
other format - under any extension - went to whichever decoder its bytes asked for. One of
those decoders hands the file to Ghostscript. A dataset of ordinary medical images is
unaffected; a path holding something else is refused by name now, with a message saying that
the extension was not what decided.

`segmentation_data()`, `instance_data()` and `detection_data()` all reach that reader, and so
does anything that asks for a shape without reading pixels. Volumes, DICOM and DICOM series
never went through it and are untouched.

**This package now needs Python 3.11 or newer**, and `SystemRequirements` says so. Python
3.10 reached end of life on 2026-10-01. For almost everybody this changes nothing: the
package declares what it needs through `reticulate` and `uv` provisions the interpreter, so
it simply provisions a newer one.

**The exception is worth knowing before it happens.** If you point `RETICULATE_PYTHON` at an
interpreter of your own - the route this package warns about when the `pyplatypus` it finds
there is not the pinned one, naming both versions - and that interpreter is 3.10, the engine
can no longer be installed into it, and what you will see is a resolution failure from `uv`
rather than anything this package wrote. The fix is a 3.11 interpreter, or letting
`py_require()` choose one. `platypus_device()` is what reports the environment you ended up
with.

Why the engine moved: its pillow floor was `>= 10.0` while the decoder fixes it needs arrived
in pillow 13, and pillow 13 requires Python 3.11 - so the floor could not be raised without
dropping 3.10. Measured rather than assumed, nothing in the dependency tree moves forward
with it: thirteen locked entries differ and every one is the removal of an old-Python branch.

A Python 3.10 user of the engine directly is served `0.8.0a43` by any installer rather than
an error, which is the migration path and asks nothing of them. This package pins `0.8.0a44`.

### 2026-10-26 - a detection epoch stops weighting batches alike (engine `0.8.0a42`)

**The numbers `plot(fit)` draws for a detection run change, and nothing you wrote changes
with them.** The engine averaged each epoch over batches, and for a detector that is not an
average over examples: every component of the YOLO loss is divided inside the loss - three
of them by a grid's object count and the fourth by the cells it supervises. A frame holding
thirty blood cells therefore counted the same as a frame holding two.

An epoch is now pooled by what the loss divided by. `maju116/rplatypus#218`.

What this means for a run you already have:

- **`fit$history`'s loss columns are on a new definition** for detection. On BCCD the
  reported `val_loss` moves by up to 0.33 over 150 epochs, and not as a constant offset - it
  changes sign over the course of a run. Comparing a recorded detection loss against a new
  run compares two definitions.
- **No score changes.** `evaluate()` and `evaluate_cases()` on a detector report average
  precision through their own path, which this does not touch, and the published
  `bccd-yolo3` weights are unchanged with them.
- **Semantic and instance runs are untouched.** Their epoch was repaired in `0.8.0a40` and
  the arithmetic there was a different one.

**It was measured before it was changed**, on 150 instrumented epochs of the engine's own
BCCD example: both poolings pick the same epoch, and that is reported as too close to call
rather than as no effect - the gap between them varies across the best epochs by 1.05 times
the margin separating the winner from the runner-up. The change is made because weighting a
per-object quantity by batches is wrong, not because an epoch visibly moved.


### 2026-10-25 - a fifth set of published weights, measured in millimetres (engine `0.8.0a41`)

**`available_weights()` lists `hc18-unet`.** A U-Net for the fetal skull in 2D ultrasound,
trained on HC18 and published for measuring **head circumference in millimetres** rather than
for an overlap score. Nothing in this package changed but the pin: the registry lives in the
engine, so a new published name arrives in R through it.

```r
available_weights()[["hc18-unet"]]
```

    median absolute error     2.44 mm   against the sonographer's measurement, 199 images
    mean                      3.84 mm   quoted beside the median because they disagree
    worst                    48.07 mm
    against the truth mask    3.41 mm   the model's own contribution, not the drawing
    Dice                       0.9494   and the description says not to choose on it

**Read that last line rather than the Dice.** On this run the Dice and the millimetres order
the same cases differently - Spearman 0.153 - and **85 of the 144 cases scoring 0.95 or better
are still wrong by more than 2 mm**. A ragged boundary barely moves an integral over a region
and a mask that is systematically fat or thin moves it linearly, which are the two errors Dice
is respectively most and least able to see, and they are the wrong way round for anybody
measuring a length. These are the first published weights in this family where the score a
reader reaches for first is the wrong one.

**They are CC BY 4.0 rather than MIT**, because HC18 is - the second set in the registry that
is not MIT, after `fives-unet`, and attribution travels with them. The sidecar carries the
citation and `weights_licence`.

Measuring with them from R is `ellipse_measure()`, which arrived in `0.8.0a39`:

```r
ellipse_measure(mask, spacing = c(px, px))
```

Predict on the **source** grid and measure there. The pixel size is a property of the file, so
a prediction resized to the model's input shape has pixels of a size nobody recorded.

### 2026-10-25 - batch_size leaves the reported score (engine `0.8.0a40`)

**`evaluate()`'s figure no longer depends on `batch_size`.** The engine divided an
epoch's totals by the number of batches, so the examples of a short last batch counted more
than the others and a split's reported score moved with a training setting. Measured on 199
validation cases: 2.3e-04 at `batch_size` 4 and 3.5e-03 at 32, and the size of the gap is not
even predictable from the setting, because it depends on which cases land in the short batch.

It is a repair rather than a change of definition, which is why the numbers move at the
fourth decimal rather than being restated: the per-batch value was already the mean over the
examples in that batch, so a mean of means was reaching for the mean over examples and
mis-weighting one batch of it.

**The larger half is for tiled runs.** `evaluate()` now pools a case's tiles by adding their
overlap counts before scoring, the way `summarise_cases()` already did - so the table's figure
is the mean over images rather than the mean over tiles. On the retinal-vessel runs that is
worth **+0.033 to +0.049** of Dice, and it is why the table in `vignette("retinal-vessels")`
needed no editing: every number in it was computed from the per-case route already, and this
brings the one-row table into agreement with it.

**The figure is now exactly the mean of `evaluate_cases()`'s own rows**, which is
what anybody comparing the two expected and did not get.

Nothing here needs editing in a script. One consequence worth knowing: `best_model()` ranks
on this table, so where two models sat within the shift of each other the winner can change -
on the eleven-loss comparison the winner is unchanged and its margin grows from +0.0006 to
+0.0033.

**And a defect this did not fix, filed rather than folded in:** the detection trainer divides
by batches too, but every component of the YOLO loss is normalised by the number of *objects*
in the batch, so averaging over batches weights a frame of thirty cells like a frame of two
platelets. That is a different repair and it has its own issue, `#218`. No published detection
number comes through it - the AP table is scored per image.

`#196`.


### 2026-10-25 - a circumference in millimetres, and where the line between the halves falls (engine `0.8.0a39`)

**[ellipse_measure()] is new**: the ellipse a segmented structure implies, as `major`, `minor`
and `circumference`. It is what a sonographer writes down, and no overlap score stands in for
it - two masks with the same Dice can be eight times apart in millimetres depending on whether
they are wrong in a ring all the way round or wrong in a ragged edge.

`class` is an argument rather than an assumption, and it is the whole reason this is not a
straight forward: the engine reads a foreground as anything above zero, which is right for its
own `argmax` masks and silently wrong for this package's, where `which.max` writes 1 for
background. Read that way the measured ellipse becomes the whole frame - 459.8 mm against
158.8 on the example in `?ellipse_measure` - so `mask == class` happens here, before anything
crosses.

**And a decision worth more than the function: [mask_volume()] and [instance_sizes()] stay in
R.** The engine's `0.8.0a39` gained both, so forwarding them was the obvious move; it was
written, measured and reverted.

It is faster - 0.035 s against 0.341 s on a 512 x 512 x 300 label map, because
`sum(mask == class)` builds a logical vector of 78 million elements first - and what settled
it was not speed. The engine's first call downloads about 5 GB, so a user holding a mask and a
spacing would pay a torch install for a count times a product. `R CMD check` also runs
examples and CRAN has no Python, so forwarding would have put `mask_volume()`'s page into
`\dontrun{}`, on arithmetic a reader can verify by eye.

So the rule drawn, and both halves of this entry are on opposite sides of it: **a measurement
that is arithmetic stays here; a measurement that needs a library crosses.** The ellipse wants
connected components, hole filling and an eigendecomposition - reimplementing those would be a
second implementation rather than a second copy of two lines.

`tests/testthat/test-measure-pair.R` holds both: R's answers against the engine's own on the
same arrays, with a positive control, and a check that the functions with runnable examples do
not reach the bridge - asked of their bodies, because calling them on a machine that has the
engine proves nothing, which is exactly how the reverted version passed its gates.

One new condition kind travels with the pin: `platypus_measure_error`, for a spacing that does
not fit the array it was given. `?platypus_conditions` lists it, and nothing here noticed it
was needed - `test-conditions.R` failed the moment the engine defined the kind, and named it.

`maju116/pyplatypus#270`.


### 2026-10-25 - two things a session can settle once, instead of every time

**The PyTorch build can be chosen once.** `options(rplatypus.torch = "pascal")` in
`~/.Rprofile`, or `PLATYPUS_TORCH=pascal` in `~/.Renviron` for runs that never load one -
`Rscript`, a scheduler, CI. Both are read when the package loads, which is the last moment
anything can change what the environment will be.

Until now the only way was to call [platypus_use_torch()] at the start of every session,
because `py_require()` is session state. On a card older than Turing, forgetting it costs
about ten times the training time **without costing an error** - the run completes, the
numbers are right, and the card sits idle. That is the kind of bill that goes unnoticed.

The option wins over the variable, so a session can override what a machine was configured
with; `"default"` turns the setting off for one session without editing the file it came
from; and a value neither recognises is reported at load and ignored, because a bad line
in a startup file should not make the package unloadable.

**An engine that is not the pinned one now says so.** The pin is what keeps an R release
from breaking when the engine moves underneath it, and on one route it was never in force:
a `RETICULATE_PYTHON` pointing at somebody's own environment brings whatever `pyplatypus`
is in it, and nothing compared the two. The failure arrived as a validator refusing a
configuration field by name, which tells a reader nothing about their interpreter.

A warning rather than a refusal, naming both versions: the only way to reach this state is
to have gone out of one's way, and refusing would also break somebody deliberately testing
an engine they built. `PLATYPUS_ENGINE_PATH` is exempt - that route asks for a source tree
with no version at all.

`maju116/rplatypus#211`, `#214`. No engine release: both are about what an R session
settles before Python starts.


### 2026-10-24 - the device report becomes the engine's, and names a backend that is not CUDA (engine `0.8.0a38`)

`platypus_device()` behaves as it did, and the answer now comes from the engine rather
than from this package. The report used to be computed in `inst/python/platypus_shim.py` -
a file of Python shipped by **this** package - so a Python user could not reach any of it,
which is backwards: the engine owns the decisions and this package reads them.

What stays here is the advice. The line telling you to call `platypus_use_torch("pascal")`
is about R's session model and would mean nothing to somebody who installed the engine
with pip; their version of that sentence belongs with the engine.

**An accelerator that is not CUDA is now named.** Until the engine's `0.8.0a38` it asked
about CUDA alone, so an Apple Silicon Mac - every Mac sold since 2020 - reported `cpu`
while a working `mps` backend sat in the same installation. `platypus_device()` prints the
backend only when it is not CUDA, because every published set of weights was trained on a
CUDA card and a score from another backend is not directly comparable with the registry's:
the unremarkable case is not worth a line, and that one is.

`maju116/pyplatypus#265` and `#266`.


### 2026-10-24 - a weight average fed per step (engine `0.8.0a37`)

`callback_ema()` keeps an exponential moving average of the weights, updated after **every
optimiser step**. That is what makes its `decay` mean what the literature means: 0.999 is
0.999 per step, so over 60 epochs of 200 batches it is 12,000 updates and a half-life of
about 700 steps. A per-epoch version would have been the same name with values that do not
transfer, which is why the engine gained a fourth callback hook rather than an
approximation.

It is [callback_swa()]'s sibling and a run takes **one of them**: both replace the model
when training ends, so the engine refuses the pair rather than applying them in whichever
order the list happened to have. `swa` folds the tail uniformly from a declared start;
`ema` weights recent steps more and needs no start at all.

Unlike `swa` it needs no pass over the training data afterwards. A uniform average of
weights carries batch-normalisation statistics belonging to no epoch and has to have them
recomputed; an exponential average of the buffers alongside the weights carries its own.

`maju116/rplatypus#203`, engine half `maju116/pyplatypus#264`.


### 2026-10-24 - the worst case becomes something a callback can watch (engine `0.8.0a36`)

`training_history()` carries **`val_<metric>_worst`**: the lowest any single case scored,
for the metrics whose counts pool into one score. `monitor = "val_dice_worst"` works, and
so does a `when` condition on it.

This package has told every reader to look at that number since it had a `summary()`
method - *a model averaging 0.86 that scores 0.11 on some patient has a failure mode, and
the mean is where it hides* - and then every callback it offered watched a mean. Stopping,
checkpointing and cutting the learning rate can all act on the distribution now.

**Validation only.** The training data is shuffled between epochs, so a case has no
identity in that pass; `"train_dice_worst"` is refused rather than quietly reported as
something else.

It costs **5.6% of an epoch**, measured on the engine's side: the counts are computed in
the validation pass that already happened rather than in a second one.

`maju116/rplatypus#205`, engine half `maju116/pyplatypus#263`.


### 2026-10-24 - the quiet failure of segmentation becomes a number (engine `0.8.0a35`)

Every epoch now reports **`foreground`** for both passes - the share of the prediction that
is not background. Nothing is compared against the truth, so it is not a measure of
quality: it answers whether the model is still producing a segmentation at all.

It arrives whether or not you ask for it, and that is the point. A model that collapses to
predicting background everywhere is invisible in the numbers it already produced - with
`include_background = TRUE` the Dice is a mean over class channels and the background
channel is nearly perfect, so a collapsed model reports around 0.5 while its loss falls.
A collapse you have to opt into noticing is one you will not notice.

`callback_terminate_on_collapse()` ends the run once that share has stayed at or below
`floor` for `patience` epochs. A floor rather than a test for zero, because 0.01%
foreground against a target that is 14% foreground has collapsed in every sense that
matters; and a patience, because an early epoch legitimately predicts almost nothing. It
can watch `train_foreground` instead, which answers a different question.

`evaluate()` carries the column, `callback_model_checkpoint()`'s `when` can take a
condition on it, and any callback's `monitor` can watch it.

`maju116/rplatypus#206`, engine half `maju116/pyplatypus#262`.


### 2026-10-24 - when a callback may act, and on what evidence (engine `0.8.0a34`)

Three things that answer one question, which is why they arrive together rather than as
three unrelated arguments.

`callback_early_stopping()` takes a **warm-up**: `start` as a fraction of the run or
`start_epoch` as an epoch, one of the two and never both. `patience` could not express it,
because it is in force for the whole run - a model needing fifteen epochs before its
validation curve means anything forced `patience > 15` permanently, paying that slack at
the end where the point was to cut quickly. It delays **the stopping and nothing else**: an
epoch inside the warm-up can still be the best one, and `restore_best` still returns to it.

`callback_swa()` takes `start_epoch` as the exclusive alternative to its fraction - the
same concept, so the same two words.

`callback_model_checkpoint()` takes **`when`**, a named list of thresholds that must all
hold before anything is written: `list(val_dice = 0.9, val_loss = 0.2)`. **The direction is
derived, not configured** - anything ending in `loss` has to be below its threshold and
everything else above it, the rule `monitor` already uses - so there is no argument to get
backwards. The names are checked against what the model reports when the specification is
built. It is an extra gate beside `save_best_only`, not a replacement, and a run whose
conditions never hold writes nothing and says so when it ends.

`callback_stop_after(hours = )` is a **wall-clock budget**. An epoch cap cannot express it:
how long an epoch takes is a property of the data and the shape. It is checked at the end
of an epoch, so the real limit is the budget plus one epoch, and the run's stop reason
names the clock - a run that ran out of time does not read as one that converged.

`maju116/rplatypus#199`, `#201` and `#207`; engine half `maju116/pyplatypus#261`.


### 2026-10-24 - two more learning-rate schedules, and one pairing that never worked (engine `0.8.0a33`)

`callback_linear_annealing()` is `callback_cosine_annealing()` with a straight line.
`callback_step_decay()` multiplies the rate by `factor` at fixed points, which is how
published recipes are written - *divide by ten at epochs 30 and 60*.

`callback_step_decay()` takes `every` **or** `milestones`, never both and never neither,
and says so from R before the call reaches the engine. Two arguments rather than one that
accepts either, because `30` and `c(30)` are different schedules and one argument holding
either would be read as whichever was typed.

**And a pairing this package has implied for as long as it has had a cosine does not
work.** A schedule recomputes the rate from the optimiser's initial value at the end of
every epoch, so it erases whatever `callback_reduce_lr_on_plateau()` cut. Measured on six
epochs of a loss that never improves, the rate with both configured follows the cosine
exactly - 0.0976, 0.0905, 0.0794 from 0.1 - where the plateau alone reaches 1e-6. The
engine refuses the pair now, by name, and so two schedules at once are refused as well.

A schedule beside `callback_swa()` is still fine, and no longer a matter of luck: the
engine fixes the order so `swa`'s constant tail rate wins whatever position the callbacks
were written in.

`maju116/rplatypus#200`, engine half `maju116/pyplatypus#260`.


### 2026-10-24 - a comparison across shapes stops being rigged (engine `0.8.0a32`)

`evaluate()` and `evaluate_cases()` take `at`. Unset is what they have always done - each
model scored on the grid it reads at. `at = "source"` puts every prediction back onto the
grid of the file it came from and scores it against the truth **as stored**, so rows from
models of different shapes answer one question and `load_shape` reads `source`.

This is the answer to a warning this package has printed since the engine's `0.8.0a30` and
to a paragraph in `vignette("retinal-vessels")` that said there was no option for it. There
was not: the measurement behind that section rescored its arms with a script that lived
outside both packages. Measured there, scoring each model on its own grid reported a
resized model at **+0.0187 where the honest figure was +0.0033** - 5.7 times - and the bias
runs the other way on clDice, because upsampling smooths a prediction.

**The grid is the files' own and you cannot name another.** A grid you name resamples the
*truth*, so the thing both models are judged against would itself be an interpolation
somebody chose. Only predictions move.

What it costs is what `predict(space = "source")` already documents: interpolation softens
a boundary, and where reading cropped anatomy away the mask comes back padded with
background - *not examined* rather than *nothing there*. For a comparison that is correct
rather than unfair, but a 0 arriving that way is a result and not a fault. The loss is not
reported on that grid, because a loss belongs to the objective a model trained with on the
grid it trained on.

A detection fit refuses `at` by name rather than ignoring it: boxes are in the source
image's coordinates already, so there is no grid to choose. The refusal is R's own and
needs no engine, which is how its test runs on a machine with no Python.

`maju116/rplatypus#187`, engine half `maju116/pyplatypus#259`. The pooling question that
came out of building it is `maju116/rplatypus#196`.


### 2026-10-22 - what CRAN's review of `0.2.0` asked for, forward-ported

`0.2.1` answered the review on its own branch, from the commit the submitted tarball was
built from, because sending `main` would have replied to two documentation comments with
ten new exported functions. The same two fixes belong here as well, or `0.3.0` collects the
same review.

`Description` writes `'PyTorch'` and `'Python'` in single quotes, as the policy asks of
software names in `Title` and `Description`. `R` stays unquoted: the cookbook the review
links does not address it, and its own Title Case example is *Web Application Framework for
R*.

`colormaps.Rd` gained the `\value` tag it never had. It documents four exported objects
rather than functions, so it carried `\format` alone; the tag is written in the roxygen
source and states structure and meaning, not just class.

**Worth keeping because it is a property of the review rather than of this release, and
the first version of this paragraph understated it.** `R CMD check --as-cran` with the
manual, on R 4.5.3, does not flag a missing `\value` - `checking Rd contents` says OK with
the tag absent - and neither does `tools:::checkRdContents()`. That was written as a fact
about this machine. **It is a fact about both sides:** CRAN's own automated pretest did not
flag it either. Measured on the two logs, which are byte-comparable because the only
difference between the submissions is this tag and two quoted names:

    rplatypus 0.2.0, the version sent back    Windows 1 NOTE, Debian 1 NOTE
    rplatypus 0.2.1, with the tag             Windows 1 NOTE, Debian 1 NOTE
    mentions of `value` or `colormaps`        0 in all four logs

So the two submissions are indistinguishable to every check that runs, and the difference
between them is exactly what the reviewer asked for. **A clean pretest says nothing about
whether the review will pass** - a human read the `.Rd` files. The instrument that does ask
the question is a check of our own: a page with `\usage` must have `\value`.

### 2026-10-22 - `platypus_fact()`, and a platypus fact when the package is attached

**The pin does not move and the engine needs no release**: this is the first thing in the
package that has nothing to do with segmentation. The family is named after the animal,
and `platypus_fact()` says something true about it. One fact is also printed when the
package is attached in an interactive session; `options(rplatypus.facts = FALSE)`, or
`PLATYPUS_FACTS=0` in `~/.Renviron`, stops that.

Three things about it are deliberate, and each one is here because of what it prevents.

**Choosing a fact does not touch the random number stream.** `sample()` advances
`.Random.seed`, so a fact picked at attach time changes what the user's own `set.seed(1)`
then produces - measured, `runif(1)` goes from 0.2655087 to 0.3721239 - and in a package
offering seeded splits and `deterministic = TRUE` that is the worst available place for it.
`suppressPackageStartupMessages()` is not a defence: the arguments are evaluated before the
condition is signalled, so suppressing the message keeps the side effect and removes the
evidence. The seed is saved and put back instead, and the test for it carries the naive
implementation as its positive control.

**Interactive sessions only**, so a fact never lands in an `R CMD check` log, a CI run, a
knitr render or anybody's reverse-dependency check. And `.onAttach` rather than `.onLoad`,
which is where this package's other startup work lives: `.onLoad` also runs for
`rplatypus::fun()`, which would print a platypus fact into the middle of a script that
never called `library()`.

**Every fact carries the source it was read from, and the numbering is stable.** Four of
the twenty-five exist to correct a popular claim rather than to state one - the platypus
does have a stomach, it does not grind food with gravel, "platypi" is not a plural and
there is no accepted word for a baby platypus - which is the only form this could take in a
package whose argument is that numbers should be measured rather than felt. A test holds
every entry to having a source. The numbers are published the moment somebody quotes one,
so facts are appended and never reordered, and a ledger of each fact's opening in
`tests/testthat/test-facts.R` fails if one moves.

`tools/reference-groups.yml` gains a group, *The animal*, last in the order. The matching
line went into `pyplatypus/tests/test_reference_groups.py` at the same time: the shared
order is an agreement about where a group goes rather than a list both sides fill, so the
engine carries the title with no contents, as this package does for *Records*.

### 2026-10-16 - `classes_from`: one binary mask file per class

Needs pyplatypus **0.8.0a28**, and the pin moves with this. `maju116/rplatypus#180`, whose
engine half is `maju116/pyplatypus#91` - an issue open since 2022, and this is the half the
author's decision of 2026-10-12 deferred rather than dropped.

#### Added

- **`segmentation_data(classes_from = )`**, the fourth way of saying what a mask's classes
  are and the only one that can express an overlap that was **drawn independently**: a
  vessel crossing an organ, or two annotators' masks of the same structure. One pattern per
  class, in class order, matched against a sample's mask files.

  It is `regions`' sibling rather than its replacement, and the difference is the file on
  disk. `regions` derives overlapping channels from the values of one label map, which is
  how BraTS stores its ground truth; this reads channels that were separate files to begin
  with, because no single voxel value can hold two things drawn independently. Everything
  the two share is everything after the target: no background entry, a sigmoid per channel
  rather than one softmax across them, a voxel that may be in several classes at once, and
  a prediction `save_masks()` refuses - `save_class_masks()` and `save_class_volumes()`
  have written per-class files since `0.8.0a23` and needed nothing for this.

- **The exclusivity refusal is four-way**, and that is the reason this is a code change
  rather than a pin bump. `segmentation_data()` enumerates its parameters, so the field
  would otherwise be an `unused argument` here; and a bare `data` list or a YAML file
  through `platypus_spec()` reaches the engine's validator either way, so a constructor
  that refused what YAML accepts would leave the two R paths disagreeing about the same
  configuration. Measured on `regions` in `rplatypus#152` and not re-guessed here.

- **The two pattern refusals say *class* where a class is what they are about** - at least
  two patterns, and distinct ones. `channels_from` has the same two for images, and the
  engine answers both through one matcher with a noun; a copied message would have been the
  likely slip, so a test holds each to its own wording.

#### Fixed

- **A model that leaves `separation` to its weights is no longer read as semantic.**
  `0.8.0a28` lets an instance model omit the field when `weights` names a file whose
  description records what it was trained to predict; this package reads a model's task
  from that field, so a silent model was read as semantic and refused beside
  `instance_data()` as two tasks in one specification - which made the engine's own
  headline example, written as an R snippet, impossible to write in R. A model now
  contributes the tasks it is *admissible* for and `platypus_spec()` intersects them with
  the data's one task. `rplatypus#181`, and it is `maju116/pyplatypus#236`'s R half, which
  that issue said did not exist.

  An intersection rather than a fallback, because a fallback swallows the case a wrong
  pairing is about: `u_net()` beside `detection_data()` says nothing about detection and
  is still refused. And a model that forgot `separation` and names no weights is still
  semantic and still refused beside instance data - the condition for being admissible is
  the engine's own, `weights` being set, which is exactly where the engine permits the
  omission.

  **Found by the field-prose ledger**, which reported the engine's `separation`
  description rewritten. Re-reading R's `@param` against the new text is the only thing
  that step is for, and this time it turned up a mechanism rather than a sentence.

#### Documented

- `?segmentation_data` gains the field, and the configuration vignette gains a subsection
  under *Overlapping classes instead of one per voxel* rather than a section of its own -
  the section list is pinned by a test in each package's suite. That subsection replaces
  the paragraph which said `classes_from` was **deliberately not here**, true of every
  release until this one.

### 2026-10-16 - the pin moves again, and a sentence on `?metrics` was true of no release

Needs pyplatypus **0.8.0a27**, and the pin moves with this. Nothing in this package gains a
function: the engine fixed a defect in the release it shipped `metric_surface_dice()` in,
and what this package owes is one corrected sentence and the test that would have caught it.

#### Fixed

- **`?metrics` said a callback watching `val_surface_dice` on a tiled run "would wait
  forever".** It would not. Until pyplatypus `0.8.0a27` the engine *accepted* that pairing
  and the run stopped with an error at the end of the first epoch - the epoch paid for and
  nothing to show - because its specification layer decided which metrics a callback may
  watch from a list of names that `surface_dice` had never been added to, while its trainer
  decided what an epoch reports by asking the metric itself. One question, two answers,
  `cldice` in both and `surface_dice` in one. The engine now asks the metric in both places
  (`pyplatypus#239`), so the pairing is refused when the configuration is read, which is
  what the page should have said and now does.

  **A test holds it from this side**, which is the part worth having: the claim is about a
  configuration this package *sends*, so it is this package's to check rather than only the
  engine's. It offers the engine both whole-mask metrics with a callback watching each, and
  carries two controls - untiled, the same callback is accepted, so the refusal is about the
  tiling; tiled with `metric_dice()`, it is accepted, so it is about the metric. Without
  both, a test like this passes on an engine that refuses the configuration for a reason of
  its own.

### 2026-10-16 - how far wrong the boundary is, and a loss that weights the rare class

Needs pyplatypus **0.8.0a26**, and the pin moves with this.

#### Added

- **`metric_surface_dice(tau = )`**, normalised surface Dice (Nikolov et al., 2018). The
  three overlap metrics ask how much of the mask coincides and `metric_cldice()` asks
  whether the structure does; none of them asks **how far wrong the boundary is**, which is
  the question a contour somebody has to approve is actually judged by. `?loss_boundary`
  reports a model at Dice 0.9525 whose volumes run 5% small and 17% wrong per case, and no
  overlap column says that - a displaced boundary and a correct one of the same area score
  alike. It is also what `loss_boundary()` optimises, so until now that loss was being judged
  by the metric it exists to improve on.

  `tau` is **required**, because no default would be honest: a tolerance belongs to the
  structure and the dataset, and conventionally it is the inter-observer variability for
  what is being drawn. It is in millimetres where `target_spacing` puts the cases on a
  common grid and in voxels where it does not, which makes this the one metric here that
  reads the voxel spacing. Like clDice it is a property of a whole mask, so on a tiled run
  it is reported per case by `evaluate_cases()` and is absent from the epoch history.

  `include_background` is `FALSE`, and for a measured reason rather than the usual one: a
  background boundary is the foreground's **plus the edge of the picture**, and that edge
  agrees between any two masks whatever happened inside them. On four random pairs at
  `tau = 2` the background scored 0.6110 to 0.7030 against the foreground's 0.5583 to
  0.6266 - higher every time, which is agreement on the field of view.

- **`loss_generalized_dice()`**, Dice with each class weighted by the inverse square of how
  much of the picture it occupies. **The argument usually made for it is not the argument
  for it here, and the help page says so.** It is introduced in the literature as a fix for
  Dice being dominated by the background; `loss_dice()` in this package is a mean over the
  class channels, so a 1% lesion already carries the same weight as the 99% around it.
  Measured on a 1% target, with one prediction finding the lesion and leaking an equal false
  positive and one missing it entirely:

  | loss | finds it | misses it | prefers finding by |
  |---|---|---|---|
  | `loss_dice()` | 0.1658 | 0.4731 | 0.3073 |
  | `loss_cce()` | 0.1600 | 0.1600 | nothing at all |
  | `loss_cce_dice()` | 0.1629 | 0.3166 | 0.1536 |
  | `loss_generalized_dice()` | 0.3278 | 0.9511 | 0.6233 |

  So it adds weight **beyond** an equal share - 1 to 9801 on that target - and the objective
  genuinely dominated is the per-pixel half of `loss_cce_dice()`. It is admissible as a
  model's own `loss` at both segmentation tasks and as `loss_boundary(region = )`, which is
  the combination worth knowing about since both features are motivated by the same picture;
  `separation_flows(loss = )` refuses it by name, because that target is a vector field.

#### Changed

- **`?loss_boundary` said "the nine region losses" and there are ten.** The count is gone
  rather than corrected: a number in prose with nothing holding it is the failure §3C exists
  to prevent, so the page states the rule - every loss except the three that score numbers
  and `boundary` itself - and a test holds that rule against the engine's own union for
  `BoundaryLoss.region`. The same shape as the family page that twice failed to name a
  member of its family.

- **`?metrics` describes the `include_background` split rather than one exception to it.**
  It said the default differs "for clDice alone", and the test holding that said the same in
  its own name; both would have gone on passing with a fifth metric in the package. The
  partition is asserted now - every metric is in one of the two groups, and a new one has to
  be put in a group before the suite passes.

- The pin moves to **0.8.0a26**, which also carries the measured answers to two things that
  were **not** built: cbDice, whose own gate now has a measurement pointing the other way,
  and the DIoU/CIoU/EIoU family. Both are answered on their issues rather than added as
  names.

### 2026-10-15 - the instance surface has a document that runs it

Needs pyplatypus **0.8.0a25**, which is already the pin.

#### Added

- **`vignette("instances")`**, the fifth worked document and the one the instance surface did
  not have. `instance_data()`, `separation_rim()`, the four `decode_*`,
  `predict(decode = )`, `evaluate()` with an average precision, `overlay_instances()`,
  `overlay_instance_agreement()` and `instance_sizes()` all shipped with tests and a
  configuration section, and **nothing joined them end to end**. §4's entry is the argument:
  a feature is not shipped until something has used it the way a user reaches it.

  It is not a second Data Science Bowl vignette. The subject is the difference between the
  two readings of one dataset, so it opens with the published weights decoded two ways -
  **245 objects by `nearest_seed` against 180 by `connected_components` on the same
  picture**, one forward pass, sixty-five touching nuclei run together - and puts
  `dsbowl-unet`'s mask beside the object map rather than describing it.

  Then it trains forty epochs beside the borrowed file in **one specification**, so
  `evaluate()` returns six rows and the comparison is a table rather than a paragraph. It
  ends where the measurement does: a count and a size distribution, in pixels, with the
  reason there are no micrometres - this dataset records no scale, and `instance_sizes()`
  takes a `spacing` precisely so that a document with one can say millilitres, as
  `vignette("volumes")` does.

  **Two things in it were not planned and are the best of it.** The borrowed weights
  reproduce the Hub card's numbers exactly - 0.5445, 0.5390, 0.4822 - so the document
  controls itself. And the forty-epoch run lands about one run-to-run spread behind on
  foreground Dice while being four to five of them behind on average precision: the extra
  eighty epochs bought a **sharper rim rather than a better mask**, which `foreground_dice`
  cannot see because the rim is a third class whose quality only appears after decoding.
  That is a finding about time inside one recipe, and it sits beside rather than against the
  milestone's finding about recipes. Both gaps are computed by the document, not typed into
  it, so re-knitting cannot leave them stale.

#### Fixed

- **Two vignettes were drawing into the same figure file, and one of them was this one.**
  `knitr` names a figure after its chunk and every vignette here shares one `fig.path`, so an
  unprefixed `history` chunk wrote `figures/history-1.png` - which is
  `vignette("data-science-bowl")`'s training curve. Its picture became an instance model's,
  silently: the file was still there and still a plot. Found by listing the built tarball,
  recovered with `git checkout` because the original was committed, and now held by a test
  that reads every shipped vignette and fails when two claim one path. The test demands no
  collision rather than a naming convention, because the first document to use a name breaks
  nothing.

### 2026-10-15 - a fourth set of published weights, and a score that needs its decoding

Needs pyplatypus **0.8.0a25**, which is what the pin moves to here.

#### Added

- **`weights = "dsbowl-instances"` works**, and it is the first published name whose score is
  not one number. A U-Net trained to tell touching nuclei apart on BBBC038v1 - interior, rim
  and background - measured on the same 134 held-out images `dsbowl-unet` reports:

  | decoding | instance AP | objects found |
  |---|---|---|
  | `decode_nearest_seed()` | 0.5445 | 5,378 of 5,999 |
  | `decode_watershed()` | 0.5390 | 5,378 of 5,999 |
  | `decode_connected_components()` | 0.4822 | 4,914 of 5,999 |

  Foreground Dice 0.9118, the mask all three rows share.

  **This side needed the pin and nothing else**, which is the cheapest kind of change here and
  worth naming as its own shape: `available_weights()` reads the registry out of the engine, so
  the fourth name arrives in that data frame the moment the pin moves. No R code was written
  for it.

  What was written is the receipt. The description is what an R user reads before trusting a
  number, and 0.0623 separates the best row from the worst against a run-to-run spread of
  0.009 - so a score quoted without its decoding is not a property of the weights. A test
  holds that description to its own arithmetic: every score in it has to name a decoding, the
  gap it claims for the separation signal has to be the gap between the rows it quotes, and
  the perfect-mask figure beside it has to be the larger of the two. Checked against the
  arithmetic rather than against the four decimals, because the measurements live in the Hub
  repository and nothing on this side can confirm 0.5445.

  The entry's own claim is the instance milestone's finding rather than a recommendation: the
  separation signal is worth +0.0623 here, a perfect semantic mask is worth +0.2398, and a
  perfect mask through connected components caps *any* model at 0.7655. The mask is the limit
  on this data. The weights are published so that the measurement can be argued with by
  somebody who did not take it.

#### Changed

- **The field-prose ledger records the new engine**, and the diff is the reason this is a line
  rather than a silent regeneration: `tests/testthat/fixtures/field-prose.yml` moved its
  `engine:` line and **not one of its 104 digests**. No configuration field's description
  changed in `0.8.0a25`, so no `@param` on this side needed re-reading. Regenerating without
  looking at that diff is how the ledger would become a rubber stamp.

### 2026-10-15 - the two instance axes can be asked about

Needs pyplatypus **0.8.0a24**, which is already the pin.

#### Added

- **`available_separations()` and `available_decodings()`**, which completes the family.
  Eight of the ten listings the engine publishes were here and these two were not, so every
  axis of a specification could be asked about except the two that are only on the instance
  task - the newest ones, where a reader is least likely to know the names already.

  Found by comparing the two public surfaces name by name rather than by reading either, and
  it is the reference group's own description that makes it a defect rather than a wish: the
  group these two sit in says it holds "the listings that ask the engine what those names
  are, rather than asking you to remember them", with `separations` and `decodings` listed in
  it and no listing for either.

  Each carries the column it is opened for: `needs` on a decoding, the separation it
  requires - empty for `connected_components`, which is why that one is always available -
  and `head_channels` on a separation, how wide a head that target makes. Both come from the
  engine's own rows rather than being named on this side, so a listing that grows a field
  arrives here with no R change; a test holds the other six listings to exactly three
  columns, because a bug in that would add a column everywhere rather than drop one here.

#### Changed

- **A test called "every decoding the engine offers has a constructor" now asks the
  engine.** It compared a list written beside it, so the engine could have grown a fifth
  decoding with nothing failing - the same shape as the warning this morning, a declaration
  beside a mechanism that does not do it. There is one for separations now too.

### 2026-10-15 - the wrap past the end of the palette is reported

Needs pyplatypus **0.8.0a24**.

#### Changed

- **`overlay_instances()` warns when a picture needs more colours than `colours` has.** It
  names how many it needs, how many there are, and how many objects lost the guarantee.

  Both packages were silent here until now and the silence was a gap rather than a decision:
  the engine's own colouring helper said in its docstring that `overlay_instances` reported
  it, and nothing in either package emitted anything. Filed from this side while `#154` was
  being written, fixed in the engine as `maju116/pyplatypus#231`, and followed here the same
  day it was released - a warning on one side and silence on the other would be exactly the
  divergence `#154` exists to prevent.

  The wrap is worth a word because it is the one case this figure answers its own question
  wrongly. Its subject is *where does one object end*; every other colour repeat is
  deliberate, and a wrap is the one that repeats **between neighbours** - provably, since a
  slot is only past the end of the palette once every colour before it was taken by a
  neighbour, so the fold lands on a colour a neighbour already holds.

  **The two messages are compared word for word**, in the `engine` job. That is a stronger
  pair than the palette or the pixels: a reader who meets this warning in R and then in
  Python has to be told the same thing, and the pin is what makes comparing prose safe - one
  exact engine, so a rewording on either side fails here instead of drifting. Measured: of
  five mutations, changing one phrase of the message is caught by that test and by nothing
  else.

### 2026-10-15 - instances come back into R

#### Added

- **`predict()` returns the objects.** It refused an instance fit until now, and the refusal
  was right for as long as the bridge had no call that returned a label map. A **named list**
  of integer maps, one per image, objects numbered from 1 and 0 for background.

  Named rather than ordered, and that is the part worth stating: the engine's own list is
  unnamed, and anything pairing two sequences by position is one dropped batch away from
  naming the wrong picture - the mistake `predict_stream()` exists on the semantic side to
  avoid. The names are read from the same two objects the engine pairs internally, and a test
  asserts they are the keys `evaluate_cases()` reports.

  A list rather than an array for the reason the detection one is a list: images differ in
  size and so does the number of objects.

- **`decode = ` picks which decoding turns the channels into objects**, by the name in the
  model's `decode` list. Unset takes the model's first, which is the engine's default rather
  than one restated here - and an unknown name is refused by the engine, naming the ones the
  model does ask for. Refused outright on a fit that decodes nothing.

- **`instance_sizes()`** is one row per object: `voxels`, and with `spacing` either
  `area_mm2` or `volume_ml`. The question `#103` opens with is *how many nuclei, and how big
  is each one*, which the published weights' card cannot answer.

  The unit is in the **column's name** rather than in the documentation, because a column
  whose unit lives elsewhere ends up in a paper as a bare number. Without `spacing` there is
  no such column at all, rather than a count pretending to be a measurement. Millilitres for
  a volume, as [mask_volume()] reports them, and a test holds the two to the same arithmetic.

- **`flow_to_colours()`** draws a two-channel vector field: hue is the direction, value is
  the length. A convention rather than a decision - which is why it is not in
  `drawing_style()` - and it is what makes a `separation_flows()` model debuggable, because a
  field that is right everywhere except reversed looks obviously reversed here and identical
  in any loss.

  Pixel-identical to the engine's on random fields, which is the only thing that can hold a
  convention.

#### Fixed

- **`type = "probability"` is refused on an instance fit, by name.** An instance model's
  channels are not all probabilities: the class channels are and a flow field's components
  are **raw**, because a softmax across a flow component and a class returns a number that
  means nothing. The engine refuses to conflate the two and so does this - the value is
  `type = "channels"`, which says what it gives.

- **`space` is refused on an instance fit, with the reason rather than "unsupported".**
  Resampling a label map interpolates between object numbers, so object 3 beside object 5
  comes back with a rim of object 4. A refusal saying only that it is not supported would
  read as a gap somebody might fill.

#### Measured

- **A one-row flow field had no dimensions.** `field[1, , ]` on a `2 x 1 x w` array drops to
  a vector, so the picture came back with no `dim` at all - and a tiled model hands back
  exactly that shape at the edge of an image. Found because the comparison against the engine
  ran three shapes rather than one; with only the first it would have shipped.

### 2026-10-15 - drawing instances

#### Added

- **`overlay_instances()`** draws an instance label map over its image, with one colour per
  object chosen so that **no two touching objects share one**. The rule is adjacency rather
  than identity: a colour repeats across the picture and never between neighbours, because
  nobody reads object 214 by its colour and everybody needs to see where one object ends.

  That is an exact graph colouring - Welsh-Powell, greedy in order of descending degree -
  and it is affordable rather than clever. Measured in the engine over all 670 Data Science
  Bowl cases, 524 of which hold touching objects: the hardest needs **three** of the eight
  slots in `class_colours`, while the cheap alternative of colouring by object number modulo
  the palette paints **550 of 5436 adjacent pairs in one colour, 10.12%** - one touching pair
  in ten drawn as a single object, in a figure whose whole subject is whether two objects are
  two.

  Eight-connected, so two objects meeting at a corner get different colours. A label-maker
  goes the other way and joins only along edges, because there the risk is merging two
  objects into one; here the risk is *drawing* two as one, which is the opposite direction.

- **`overlay_instance_agreement()`** is found, missed and invented **objects**.
  `overlay_agreement()` answers the same three-way question about pixels, and on an instance
  result that is the wrong unit: a merged pair and a split object are both nearly perfect
  pixelwise and both wrong, which is what an average precision will not tell anybody. Matched
  whole object against whole object at one IoU threshold, strictly greater, and **below 0.5
  is refused** for the reason the metric refuses it.

#### Measured

- **The matching needs no greedy pass, and that is provable rather than convenient.** The
  engine matches greedily on descending IoU; this package matches every pair above the
  threshold, which is equivalent above 0.5: if two disjoint true objects both exceeded 0.5
  against one prediction, each intersection would exceed half of it - the union is at least
  the prediction - and two disjoint intersections cannot together exceed it. So the matching
  is one to one whatever order it is taken in, which is also why the metric refuses a lower
  threshold.

  Written as the equivalent rather than as a copy because `argsort` is not stable: two pairs
  at the same IoU leave the engine in an order neither package controls, and a pixel-for-pixel
  test would then fail for something that is not a divergence.

#### Fixed

- **Nothing held the two packages to the same colouring, and the shared constant could not.**
  `#154`'s subject: the palette is mirrored and `test-drawing-style.R` holds it, so the two
  would keep agreeing about *which eight colours* while disagreeing about which object gets
  which. `tests/testthat/test-instance-drawing.R` draws the same pictures both ways and
  compares them **pixel for pixel** - five label maps including three objects each touching
  the other two, and five ways an instance result goes wrong - which is the only thing that
  can hold a rule rather than a constant.

  Six mutations, each caught: four-connected instead of eight, colour by object number instead
  of by adjacency, ascending instead of descending degree, `>=` instead of `>` at the
  threshold, and two ways of getting the outline wrong. The outline pair needed a **new
  picture**: against the first one both mutations passed, because every object in it was three
  pixels across and had no interior to lose. §4's "a check calibrated loosely enough admits
  the failure it was written to prevent", found by mutating rather than by reading.

- **`flow_to_colours()` is still deferred, and the stated reason has expired.** `#154` defers
  it because "R cannot configure `flows` until `pyplatypus#160`" - which shipped in
  `0.8.0a20`, and `separation_flows()` has been exported here since. The reason that holds now
  is a different one: `predict()` refuses an instance fit, so **there is no way to get a flow
  field into R to draw**. It belongs with `#103`, where the prediction comes back.

### 2026-10-14 - `regions` from R: overlapping classes

#### Added

- **`segmentation_data(regions = )`**, the third way of saying what a mask's classes are and
  the only one that lets a voxel belong to more than one. A list of `list(name = , of = )`,
  where `of` holds the label-map values making up that region:

  ```r
  segmentation_data(
    "train/", "valid/",
    regions = list(list(name = "whole tumour", of = c(1, 2, 4)),
                   list(name = "enhancing", of = 4))
  )
  ```

  That is the BraTS shape, and the second entry shows that a single value is ordinary rather
  than an edge case. The engine has had the field since `0.8.0a14`; **R forwarding it was a
  code change rather than a pin bump**, which is worth saying because the first guess was the
  opposite: `segmentation_data()` enumerates its parameters, so `regions` was an
  `unused argument` while a bare `data` list and a YAML file both reached the engine's own
  validator and were accepted. The constructor refusing what YAML took is the asymmetry this
  closes. `pyplatypus#91`, `#152`.

  Two things `?segmentation_data` now says that the field name does not. There is **no
  background entry**, so `n_class` is not the number it would be for that many `labels`. And
  each channel is an **independent binary question** - a sigmoid per channel rather than one
  softmax across them - so a voxel may be in several regions at once, which is the point.

- **The configuration vignette has a section on overlapping classes**, *Overlapping classes
  instead of one per voxel*, between the augmentation section and the instance one - because
  `regions` is still `semantic_segmentation` and what changes is what a channel means rather
  than what the task is. The section list is pinned by a test here and by the same list in the
  engine's suite, so it landed in both repositories together: `pyplatypus#229` first, because
  this side compares itself against that list.

  Two things in it are R's own: a region is a `list(name = , of = )` and the last one shows
  that `of = 4` is ordinary rather than an edge case, and `inspect_masks()` **names** the
  region that matched nothing instead of giving its position. Both the YAML block and the R
  chunk are validated - checked by breaking each, which fails the test that reads it rather
  than passing quietly.

- **`inspect_masks()` names regions rather than numbering them.** The engine reports classes
  by position, and with `regions` a position is the one thing a reader cannot resolve:
  `missing_classes: 1` means the second region, and counting entries in a configuration file
  to find out which is the step nobody takes. With `colormap` or `labels` the number *is* the
  class, so it stays a number - naming it would invent something the specification did not
  say, and a test holds that.

  It matters most for the one failure `regions` invites: `of = 3` against a label map holding
  `4` is a channel of zeros, so the model trains to predict nothing and scores a Dice of 0 for
  that region while every other number in the run looks ordinary.

  The positions are still attached as the `present` and `missing` attributes, so anything
  reading them keeps working. The mapping is derived in R from the specification R owns
  rather than asked of the engine - which would mean a release and a pin move for a label -
  and what holds the two together is a test comparing R's name against the engine's own
  refusal sentence. An off-by-one in that mapping fails it, which is the one mistake whose
  output otherwise looks entirely ordinary.

- **The exclusivity check is three-way and names what was given.** One of `colormap`,
  `labels` and `regions`, in one message, matching the engine's own sentence - and the
  message now says which arguments it found rather than only that one was expected.

- **`save_class_masks()` writes an overlapping prediction, one file per class.** Needs
  **pyplatypus 0.8.0a23**, which is what the pin moves to here, and where the writer lives; this side forwards to it rather than
  keeping a second copy of the rules, because the filenames are part of what somebody's next
  script reads. `<name><suffix>_<class>.png`, black and white, and a class name becomes a
  filename by replacing anything a path cannot hold with `_` - so `whole tumour` is
  `whole_tumour`. Two class names that become the **same** filename are refused rather than
  written: one file would hold the second class, the first would be silently gone, and the
  number of returned paths would still be right.

  The argument is `classes` and not `names`, which is §3A applied before the surface
  existed: `names` in this family is the **files** - `save_masks()` and `save_volumes()` both
  use it that way - and a sibling writer where the same word means the classes instead would
  accept a call copied from one to the other whenever the counts happened to match. The
  engine's own function calls them `classes` too, for the same reason.

#### Fixed

- **`save_masks()` and `save_volumes()` refuse an overlapping prediction instead of silently
  reducing it.** Both took `which.max` over the channel axis, which for sigmoid channels
  writes one of the classes a voxel is in and leaves nothing in the file to say so. They now
  count how many channels are hot at the most ambitious voxel and refuse with that number,
  each pointing at its own per-class writer.

  `#152` named `save_masks()` and there turned out to be **three** reduction sites, not one:
  `save_volumes()` has two, a 4-dimensional array inside a list and a 5-dimensional stack.
  Found by asking what a BraTS user would actually run, which is §4's *a feature is not
  shipped until something has used it the way a user reaches it* applied to a refusal.

  Detected **from the array** rather than from the specification, which is the same test the
  engine applies in `onehot_to_colours` - so both halves refuse the same arrays, and a caller
  holding only a prediction can answer the question. A softmax prediction never trips it,
  since its channels sum to one and at most one can reach half; that control is a test rather
  than a sentence, because without it every ordinary run would start refusing.

- **`save_class_volumes()` is the same thing for volumes, and it is the case `regions` was
  built for.** BraTS names three overlapping regions and stores them as volumes, so a writer
  that only handled pictures would have left the motivating dataset with a refusal and no
  route to disk. One NIfTI per class, each carrying the geometry of the scan it was predicted
  from - which is the whole reason this is not `save_class_masks()` with another extension.

  It needs no engine release: it goes through the same volume writer `save_volumes()` uses,
  so the affine, the integer labels and the grid check are those rather than a second copy.
  What *is* a second copy is the rule turning a class name into a filename, because the
  volume path never reaches the engine's `class_filename` - so a test holds R's rule to the
  engine's over the names that are actually awkward, rather than a comment claiming they
  agree.

- **`predict(type = "class")` refused rather than computed when the classes overlap**, and
  `"class"` is the default, so this is the first call an R user makes on such a fit. There is
  no one class per pixel to return: the channels are independent binary questions, they do
  not compete, and an `argmax` across them names one of the classes a pixel is in. The
  refusal says to ask for `type = "probability"` and names what writes it.

  Read off the specification the fit carries, which is a lever this package owns - the shape
  cannot answer it, because sigmoid channels and a softmax's channels are the same array.

- **A single `of` value would have crossed over as a number rather than a list.** reticulate
  turns a length-1 integer vector into a Python scalar, and the schema wants an array, so
  `of = 4` had to be built with `as.list()`. Measured both ways before the code was written,
  and the engine refuses the scalar - so this would have been a refusal nobody could read
  rather than a silent wrong answer, on the most ordinary region there is.

  **Still in `#152`, deliberately not here**, and written as a paragraph rather than a
  heading because `R CMD check` reads every `###` in this file as a version and says so:
  `save_masks()` refusing an overlapping prediction and the per-class writer that replaces
  it, `inspect_masks()` naming regions rather than numbering them, and the guide section.
  Each is independently worth having, which is why none waits for the others.

## [0.2.0] - submitted to CRAN on 2026-10-14

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
