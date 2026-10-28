# One label for a whole image, which is the engine's fourth task and the first one here
# whose answer is not a picture. Everything in this file exists because of that difference:
# there is no mask to name classes with, no grid for an answer to live on, and no spatial
# quantity for a metric to average.

#' Images and the label each of them carries, which may be a set
#'
#' The data block for `task = "classification"`. This title said *the one label each of them
#' carries* until `labels_from` arrived, and the field-prose ledger is what asked: the
#' engine rewrote its own one-line description of this block to name all three labellings,
#' and re-reading R's prose for it turned up a heading that had become false rather than a
#' sentence that had.
#'
#' What this constructor is *for* is as much
#' the fields it has not got as the two it adds: `colormap`, `labels`, `regions`,
#' `classes_from`, `channels_from` and `target_spacing` all describe a mask or a grid, and
#' a label is neither.
#'
#' **Where the labelling is written follows from `mode` rather than being said twice.** In
#' `"nested_dirs"` mode the directories under `train` are the classes, with the images
#' inside them - the layout nearly every image dataset ships in. In `"config_file"` mode
#' the CSV's `label` column holds the class name.
#'
#' **And `labels_from` is the third way, for a label that is a set rather than one of a
#' list of alternatives** - a chest film with four findings is four independent questions.
#' It is a naming rather than a switch, for the reason `regions` and `classes_from` are on
#' the mask side: the *target* changes and not only the activation, so there is nothing a
#' `multilabel = TRUE` could have meant on a `label` column that structurally cannot say an
#' image has two findings.
#'
#' @param train Path to the training data: a directory of class directories in
#'   `"nested_dirs"` mode, or a CSV in `"config_file"` mode.
#' @param validation Path to the validation data, or `FALSE` to train without one.
#' @param classes The class names, in class order. **Position is the class index the model
#'   learns**, which is why it is written rather than read off the directory listing: taken
#'   from the filesystem the order would be alphabetical - reproducible, and unrelated to
#'   anything - so a model trained where index 1 meant `"benign"` and used where it means
#'   `"malignant"` reports plausible probabilities and nothing downstream can tell.
#'
#'   In `"nested_dirs"` mode these are the directory names. At least two, where
#'   [detection_data()] allows one: a detector with one class answers *where are the cells*,
#'   which is a question, and a classifier with one class answers *is this a cell* with the
#'   only answer it has.
#'
#'   There is no background entry. An image is one of these, and a picture of nothing in
#'   particular is a class somebody has to name.
#' @param labels_from One CSV column per class, in class order, each cell `0` or `1` - the
#'   layout for a label that is a **set**. Position in this list is paired with `classes`,
#'   so the headers may be called whatever the dataset calls them and the model still learns
#'   the classes in the order you named; stated rather than read off the header row for
#'   `channels_from`'s reason, that sorting is reproducible and clinically meaningless.
#'
#'   `"config_file"` mode only, and that is a refusal rather than a gap: an image cannot sit
#'   in two directories without being two files, so `nested_dirs` cannot express a set of
#'   labels at all. `strict_labels` has nothing to choose between here - the columns *are*
#'   the classes - and is refused rather than ignored.
#'
#'   A cell that is not `0`, `1`, `0.0` or `1.0` is refused by name, and the case that is
#'   written for is `-1`: the datasets shaped this way write `-1` for *uncertain* and leave
#'   the cell empty for *not mentioned*, both of which have a defensible mapping to 0 or to
#'   1, which is exactly why the reader must not pick one for you. An image with none of the
#'   findings is an ordinary labelled row, written as a line of zeros.
#'
#'   **There is no threshold, and `metric_accuracy()` is refused.** Each class decides for
#'   itself at a probability of 0.5, and a threshold is a number about your data rather than
#'   one this format should invent. Accuracy is refused outright rather than redefined:
#'   measured on 4000 images with findings at 10%, 5%, 3% and 2%, a model answering no to
#'   everything scores 0.8137 on exact match and 0.9507 per class, **above a model holding
#'   half the available signal** - so neither reading can be what a `monitor` watches. Use
#'   [metric_balanced_accuracy()], [metric_f1()] or [metric_auc()].
#' @param test Path to a held-out set, scored but never trained on.
#' @param split A [split()] block, to cut a validation and test set out of the training
#'   data. For this task the cut is **stratified** by the engine, so every class reaches
#'   every side - a random 70/15/15 of 100 images at a 3% prevalence leaves some part with
#'   none of the rare class 91% of the time, and a per-class metric cannot average over a
#'   class its pass never held.
#' @param mode `"nested_dirs"` or `"config_file"`.
#' @param strict_labels Refuse an image whose label is not in `classes`. `FALSE` skips it
#'   instead, which is how to train on two of a dataset's three classes without moving any
#'   files. It matters more here than it does for a box: a skipped object leaves the rest of
#'   its image in the training set, while a skipped image leaves nothing, so the same
#'   setting quietly changes how much data there is.
#'
#'   Refused beside `labels_from`, where the state it chooses between cannot arise: the
#'   columns are the classes, so there is no cell that could hold a class nobody named.
#' @param window How values in real units reach the model, for DICOM and NIfTI - see
#'   [segmentation_data()], which documents the named windows. Ignored for ordinary
#'   pictures.
#' @param subdirs Refused, and named rather than dropped because every sibling data
#'   constructor has it. For segmentation and detection a sample is a directory with the
#'   image in one subdirectory and what labels it in the other; a classification sample is
#'   one image whose label is the directory it sits in, so there is no second subdirectory.
#' @param column_sep For `config_file`, what separates several paths in one cell.
#' @param shuffle Shuffle the training data between epochs.
#' @return A data specification, to be passed to [platypus_spec()].
#' @seealso [classifier()], [class_balance()], [available_metrics()]
#' @export
#' @examples
#' classification_data("train/", "valid/", classes = c("benign", "malignant"))
classification_data <- function(train, validation = NULL, classes, labels_from = NULL,
                                test = NULL,
                                split = NULL,
                                mode = c("nested_dirs", "config_file"),
                                strict_labels = TRUE, window = NULL,
                                subdirs = NULL, column_sep = ";", shuffle = TRUE) {
  # Which of these the caller actually named: a field is sent only when somebody chose it,
  # because a default sent from here is indistinguishable from a value the user set, and an
  # R-side default silences a schema that knows better. §3D's rule, and the same `gave`
  # list every other data constructor keeps.
  explicit_mode <- !missing(mode)
  gave <- list(
    strict_labels = !missing(strict_labels),
    column_sep = !missing(column_sep),
    shuffle = !missing(shuffle)
  )
  mode <- match.arg(mode)

  if (inherits(train, "platypus_split")) {
    stop("a `split_dataset()` carries image and mask paths, and a classification sample ",
         "has no mask. Use `split` instead, which divides the samples themselves - and ",
         "for this task the engine stratifies that cut, so every class reaches every ",
         "side.", call. = FALSE)
  }
  check_split(validation, split, test)

  # Refused here rather than across the bridge for the reason every duplicated refusal in
  # this package has: the message is the same and this way no interpreter starts to deliver
  # it. The sentence carries the layout, because that is what somebody writing `subdirs`
  # was trying to describe.
  if (!is.null(subdirs)) {
    stop("`subdirs` names the two subdirectories of a sample directory, and a ",
         "classification sample is a single image. In `nested_dirs` mode the directories ",
         "under `train` are the classes - one per class, images inside - and in ",
         "`config_file` mode the CSV's `label` column holds the name. Remove `subdirs`.",
         call. = FALSE)
  }

  # The three `labels_from` refusals, local for the reason the `subdirs` one above is: the
  # sentence is the engine's own, and this way no interpreter starts in order to deliver it.
  # All three are duplicated rather than forwarded because `platypus_spec()` sends a bare
  # list or a YAML file straight to the validator, so the two routes have to agree.
  if (!is.null(labels_from)) {
    labels_from <- as.character(labels_from)
    if (identical(mode, "nested_dirs")) {
      stop("`labels_from` reads one column per class, which is `config_file` mode. An ",
           "image cannot sit in two directories without being two files, so `nested_dirs` ",
           "cannot express a set of labels at all - give `mode = \"config_file\"` and a ",
           "CSV with one column per class.", call. = FALSE)
    }
    if (length(labels_from) < 2L) {
      stop("`labels_from` needs one column per class, so at least two. With a single class ",
           "there is nothing for the set to be, and a `label` column already names one of ",
           "a list of alternatives.", call. = FALSE)
    }
    if (gave$strict_labels) {
      stop("`strict_labels` has nothing to choose between beside `labels_from`: the ",
           "columns *are* the classes, paired by position, so there is no cell that could ",
           "hold a class nobody named. Remove it.", call. = FALSE)
    }
  }

  # The same three checks `detection_data()` makes of its own `classes`, and for the same
  # reasons: the two paths into the engine have to agree, and `platypus_spec()` sends a
  # bare list or a YAML file straight to the validator.
  if (missing(classes) || !length(classes)) {
    stop("`classes` must name the classes, in class order - position is the class index ",
         "the model learns. See `?classification_data`.", call. = FALSE)
  }
  classes <- as.character(classes)
  if (anyNA(classes) || any(!nzchar(classes))) {
    stop("every entry in `classes` must be a non-empty name.", call. = FALSE)
  }
  if (anyDuplicated(classes)) {
    stop("`classes` must be distinct - two classes sharing a name are one class with the ",
         "wrong index, and in `nested_dirs` mode they cannot even be two directories.",
         call. = FALSE)
  }
  if (length(classes) < 2L) {
    stop("`classes` needs at least two entries. One class answers *is this a cell* with ",
         "the only answer it has - a detector with one class is a question, and a ",
         "classifier with one class is not.", call. = FALSE)
  }

  # Checked after `classes` rather than with the three above, because the comparison needs
  # both lists and a message about a mismatch has to be able to name each count.
  if (!is.null(labels_from) && length(labels_from) != length(classes)) {
    stop("`labels_from` names ", length(labels_from), " column(s) and `classes` names ",
         length(classes), ". They are paired by position - one column per class, in class ",
         "order - so the two lists have to be the same length.", call. = FALSE)
  }

  structure(
    list(
      train_path = train,
      # FALSE is not a path. It travels as the engine's own `validation` flag with
      # `validation_path` absent, since sending both is the contradiction the engine
      # refuses.
      validation_path = if (isFALSE(validation)) NULL else validation,
      validation = if (isFALSE(validation)) FALSE else NULL,
      test_path = test,
      # Not compacted: `group_by = NULL` is the whole point of that field - "divide by
      # file, and I know it" - so an absent value and a NULL value are different things.
      split = split_block(split),
      mode = if (explicit_mode || !identical(mode, "nested_dirs")) mode else NULL,
      classes = classes,
      labels_from = labels_from,
      strict_labels = if (gave$strict_labels) strict_labels else NULL,
      # Aligned under the `if` it continues: the chain reads as one decision.
      window = if (is.null(window)) NULL
               else if (is.character(window)) window  # nolint: indentation_linter.
               else as.numeric(window),
      column_sep = if (gave$column_sep) column_sep else NULL,
      shuffle = if (gave$shuffle) shuffle else NULL
    ),
    class = c("platypus_classification_data", "list"),
    # The tag is the whole mechanism: `task_of()` reads it, `agreed_task()` checks it
    # against the models, and nothing else in a specification has to say the word.
    task = "classification"
  )
}


#' A contracting path, pooled, with one dense layer on top
#'
#' The model block for `task = "classification"`, and **the one model constructor in this
#' package that is not named after an architecture.** `u_net()`, `linknet()`,
#' `res_u_net()` and `u_net_plus_plus()` choose between four decoders that read the same
#' features; a classifier has nothing after the pooling but a dense layer, so the
#' contracting path *is* the architecture and `encoder` is the whole answer. The engine has
#' no `architecture` field here for that reason, and the name follows its own
#' `build_classifier`.
#'
#' `n_class` is not an argument, for the reason it is not one on [u_net()] either: the
#' number of classes comes from `classes` in [classification_data()], and a model that also
#' declared it could only ever disagree with its own data.
#'
#' @param name A name for the model, used in the score table and in file names.
#' @param input_shape The size every image is read at, `c(height, width)`. Unlike a
#'   segmentation model nothing has to divide by `2^blocks` - there is no decoder to line
#'   up with - but every side must still be at least `2^blocks`, or the deepest level has
#'   nothing left to pool.
#' @param channels Input channels: 3 for colour, 1 for greyscale.
#' @param blocks How many times the resolution is halved before the features are pooled, so
#'   how much context the answer is made from. Ignored, and refused, when `encoder` names a
#'   backbone - the backbone's own depth is then the only one there is.
#' @param filters Filters in the first block, doubled at every level, so this and `blocks`
#'   set how wide the pooled feature vector is: `filters * 2^blocks`. Ignored, and refused,
#'   with `encoder`.
#' @param block_width Convolutions per block, at every level. Raising it adds depth without
#'   adding levels, which is the lever to reach for when the objects are small enough that
#'   halving the resolution again would lose them - a crop of one cell is exactly that
#'   case. Ignored, and refused, with `encoder`.
#' @param pooling How the feature map becomes one vector per image. `"avg"` averages
#'   evidence over the whole frame, which is what every classification head since the
#'   networks that replaced the flattened dense layer does; `"max"` takes the strongest
#'   response anywhere, which is the one to reach for when the thing being looked for is
#'   small and somewhere in the picture rather than the picture itself.
#' @param head_dropout Drop this fraction of the pooled vector before the dense layer.
#'   Separate from `dropout`, which sits between convolutions and reaches nothing at all
#'   when the contracting path is a pretrained backbone with its own regularisation - this
#'   is then the only one left.
#' @param dropout,batch_normalization,separable_conv,spatial_dropout Regularisation and
#'   shape of the contracting path, as in [u_net()].
#' @param activation,initialiser The non-linearity between convolutions, and how the
#'   weights start.
#' @param loss The objective. Fewer are admissible here than anywhere else in this package,
#'   and the two that are - [loss_cce()] and [loss_focal()] - are the ones that score each
#'   answer on its own rather than scoring an overlap. `available_losses("classification")`
#'   lists them and the engine's refusal names them.
#' @param metrics What to report beside the loss. `metric_auc()` is the engine's default and
#'   that is a measurement rather than a preference: at a 3% prevalence a calibrated model
#'   never crosses the threshold, so accuracy, balanced accuracy and F1 all report a real
#'   signal and a collapse as the same number. See [metric_auc()].
#' @param optimizer,callbacks,augmentation,epochs,batch_size,weights,fit As in [u_net()].
#'   A callback watching `val_<metric>` is refused when nothing in `metrics` will produce
#'   it, and there is no `foreground` to watch - a classification epoch has no background
#'   class and reports no such share.
#' @param encoder A pretrained backbone instead of our own contracting path, by name - see
#'   [encoders] for the table and what it is actually good for. With this, `blocks`,
#'   `filters` and `block_width` are refused.
#' @param pretrained,freeze_encoder,encoder_learning_rate How the backbone arrives and how
#'   it is trained, as in [u_net()].
#' @return A model specification, to be passed to [platypus_spec()].
#' @seealso [classification_data()], [metric_auc()]
#' @export
#' @examples
#' classifier("cnn", input_shape = c(128, 128), blocks = 3, filters = 16)
#'
#' # A pretrained backbone instead of ours, with its early levels held still
#' classifier("resnet", input_shape = c(224, 224), encoder = "resnet34",
#'            pretrained = TRUE, freeze_encoder = 2)
classifier <- function(name, input_shape, channels = NULL,
                       blocks = NULL, filters = NULL, block_width = NULL,
                       pooling = NULL, head_dropout = NULL,
                       dropout = NULL, batch_normalization = NULL,
                       separable_conv = NULL, spatial_dropout = NULL,
                       activation = NULL, initialiser = NULL,
                       loss = NULL, metrics = NULL, optimizer = NULL,
                       callbacks = NULL, augmentation = NULL,
                       epochs = NULL, batch_size = NULL, weights = NULL, fit = NULL,
                       encoder = NULL, pretrained = NULL, freeze_encoder = NULL,
                       encoder_learning_rate = NULL) {
  # Everything optional arrives as NULL and `compact()` drops it before the request is
  # built, so the engine's own default applies. A value repeated here is a second place for
  # one fact to live, and a default *sent* is indistinguishable from a choice - which is
  # what would stop a published weights file from filling `blocks` and `filters` in.
  built <- compact(list(
    name = name,
    input_shape = as.integer(input_shape),
    channels = int1(channels),
    blocks = int1(blocks),
    filters = int1(filters),
    block_width = int1(block_width),
    pooling = pooling,
    head_dropout = head_dropout,
    dropout = dropout,
    batch_normalization = batch_normalization,
    separable_conv = separable_conv,
    spatial_dropout = spatial_dropout,
    activation = activation,
    initialiser = initialiser,
    loss = loss,
    metrics = metrics,
    optimizer = optimizer,
    callbacks = callbacks,
    augmentation = augmentation,
    epochs = int1(epochs),
    batch_size = int1(batch_size),
    weights = weights,
    fit = fit,
    encoder = encoder,
    pretrained = pretrained,
    freeze_encoder = if (is.null(freeze_encoder)) NULL else int1(freeze_encoder),
    encoder_learning_rate = encoder_learning_rate
  ))

  # A classifier is admissible for exactly one task, and it says so rather than being
  # inferred from a field it carries. Every other model here is read off `separation` or
  # `architecture`; this one has neither, and a model with no `architecture` at all is
  # already unlike anything the segmentation branch can produce.
  structure(built, task = "classification")
}


#' How many images each class has, before anything is trained
#'
#' The number every decision about this task's metrics turned on, and the person who most
#' needs it is the one who has just written a specification and not yet run anything. A
#' prevalence a reader does not know is one they will discover from a score that looks fine.
#'
#' The sentence under the table is the **engine's own**, printed rather than reproduced:
#' the threshold it fires below is the engine's number, and a copy of it here would be a
#' second place for one fact to live.
#'
#' @param spec A [platypus_spec()] describing a classification task.
#' @param split Which split to count: `"train"`, `"validation"` or `"test"`.
#' @return A data frame of one row per class, in class order, with columns `class`, `n` and
#'   `share`, of class `platypus_class_balance` so that printing it adds the engine's own
#'   remark about how lopsided the split is. The engine's sentence is carried on the
#'   `remark` attribute.
#' @seealso [classification_data()], [split()]
#' @export
#' @examples
#' \dontrun{
#' spec <- platypus_spec(
#'   data = classification_data("train/", "valid/", classes = c("benign", "malignant")),
#'   models = list(classifier("cnn", input_shape = c(128, 128)))
#' )
#' class_balance(spec)
#' }
class_balance <- function(spec, split = "train") {
  if (!inherits(spec, "platypus_spec")) {
    stop("`spec` must be a platypus_spec, from `platypus_spec()`.", call. = FALSE)
  }
  found <- shim()$class_balance(spec$py, split = split)
  if (!isTRUE(found$ok)) abort_engine(found)
  counts <- unlist(found$counts)
  rows <- data.frame(
    class = names(counts),
    n = as.integer(counts),
    share = as.numeric(counts) / sum(as.integer(counts)),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
  structure(rows, class = c("platypus_class_balance", "data.frame"),
            remark = as.character(found$remark))
}

#' @export
print.platypus_class_balance <- function(x, ...) {
  print(as.data.frame(x), row.names = FALSE)
  remark <- attr(x, "remark", exact = TRUE)
  if (length(remark) && nzchar(remark)) cat("\n", remark, "\n", sep = "")
  invisible(x)
}
