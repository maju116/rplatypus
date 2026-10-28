# Model constructors.
#
# Four architectures from one builder, because they differ in three decisions - whether
# the convolution block is residual, whether skips are concatenated or added, and whether
# the skip paths are nested - and every other switch composes with all of them.
#
# The old package expressed this as three independent flags, so it also built the
# combinations nobody named and nobody tested. Here you ask for one architecture by name.

#' Segmentation models
#'
#' Four members of the U-shaped family. They take the same arguments and differ only in
#' what happens between the contracting and expanding paths: `u_net` concatenates its skip
#' connections, `linknet` adds them, `res_u_net` makes each block residual, and
#' `u_net_plus_plus` fills in the nested skip pathways.
#'
#' `input_shape` is the tile the model sees: two numbers for images, three for volumes.
#' Its length is what makes a model 2D or 3D - there is no separate switch. Every spatial
#' dimension must divide by `2^blocks`, or the decoder cannot line up with the encoder,
#' and that is checked when the specification is built rather than part-way through
#' training.
#'
#' @section Where the defaults live:
#'
#' Every argument below except `name` and `input_shape` is `NULL` unless you set it, and a
#' `NULL` is left out of the request entirely - so the engine's own default applies. The
#' defaults are therefore written down once, in `pyplatypus`, rather than here as well:
#'
#' \preformatted{
#' channels 3        blocks 4          filters 16      block_width 2
#' dropout 0         batch_normalization TRUE          separable_conv FALSE
#' spatial_dropout TRUE                upsample FALSE  deep_supervision FALSE
#' activation "relu"                   initialiser "he_normal"
#' loss cce          metrics iou       optimizer adam  callbacks none
#' epochs 10         batch_size 8      fit TRUE
#' }
#'
#' The second reason matters more than tidiness. A value sent is indistinguishable from a
#' value chosen, so defaults travelling from here would silence the engine's own knowledge:
#' `weights` naming a published file records its architecture, `blocks` and `filters`, and
#' those are adopted **only** where the specification stayed silent. Sending `blocks = 4`
#' because that is what R happened to say would override a file that knows better.
#'
#' @param name Unique within a specification. It names this model's outputs, its rows in
#'   every score table, and the directory its run record is written to - so two models
#'   called the same thing would overwrite one record and report it as two, which is why
#'   the engine refuses a repeat rather than disambiguating it.
#' @param input_shape Tile size: `c(height, width)`, or `c(depth, height, width)`.
#' @param channels Input channels. 3 for colour, 1 for greyscale. Derived from
#'   `channels_from` when [segmentation_data()] names one file per channel.
#' @param n_class **Removed.** The number of classes comes from the data - `colormap` or
#'   `labels` in [segmentation_data()] - and a model that also declared it could only ever
#'   disagree with its own data. Passing it is an error that says so.
#' @param blocks How many times the resolution is halved. Taken from the weights file when
#'   `weights` is given and this is not.
#' @param filters Filters in the first block; doubled at each level. Taken from the weights
#'   file when `weights` is given and this is not.
#' @param block_width Convolutions per block. Two is the usual U-Net block; one trains
#'   faster and holds less, three rarely pays for itself. It composes with every
#'   architecture, including the residual blocks of `res_u_net()`, where it is the number of
#'   convolutions inside the residual rather than beside it.
#' @param dropout Drop this fraction of activations in every block during training, 0 to
#'   switch it off. The first thing to reach for when the training loss keeps falling and
#'   the validation loss does not.
#' @param batch_normalization Normalise each batch's activations between convolutions,
#'   which is what lets a deeper network train at all at a useful learning rate. On by
#'   default; the reason to turn it off is a batch so small that its statistics are noise,
#'   which is the case a 3D run with `batch_size = 1` lands in.
#' @param separable_conv Depthwise-separable convolutions. Far fewer parameters, a little
#'   slower to converge.
#' @param spatial_dropout Drop whole feature maps rather than individual activations. On an
#'   image the neighbouring pixels of a dropped activation carry almost the same
#'   information, so ordinary dropout removes less than it appears to; dropping a channel
#'   removes a feature. Does nothing unless `dropout` is above 0, which sets the rate.
#' @param upsample Interpolate and convolve instead of using a transposed convolution.
#' @param deep_supervision Train every decoder depth, not only the last. `u_net_plus_plus`
#'   only, since it is the one with intermediate outputs to supervise.
#' @param activation One of `"relu"`, `"leaky_relu"`, `"elu"`, `"selu"`, `"gelu"`,
#'   `"silu"`, `"tanh"`.
#' @param initialiser One of `"he_normal"`, `"he_uniform"`, `"glorot_normal"`,
#'   `"glorot_uniform"`.
#' @param loss The objective trained against, see [losses] and [available_losses()]. It is
#'   what a score table's `loss` column is comparable within and not across: a
#'   Focal-Tversky of 0.05 is not better than a cross-entropy of 0.14, it is a different
#'   question, which is why the table carries the loss's name beside the number. Unset uses
#'   the engine's default.
#' @param metrics A list of metrics, see [metrics]. These are reported beside the loss and
#'   are **computed on the mask rather than on the objective**, which is what makes them
#'   comparable between models: a Focal-Tversky of 0.05 and a CCE-Dice of 0.14 are not the
#'   same question, and their Dice is.
#'
#'   A callback watching `val_<metric>` is refused when nothing in this list will produce
#'   it - when the configuration is read, rather than at the end of the first epoch with
#'   the epoch already paid for. Which is also why a tiled run refuses a callback watching
#'   `val_cldice` or `val_surface_dice`: those are properties of a whole mask, reported per
#'   case rather than per epoch, so the choice to tile and the choice of what to stop on
#'   are settled together.
#'
#'   For a classifier the list is a different family - see [classification_metrics], where
#'   none of these names appears and the default is measured rather than chosen.
#' @param optimizer An optimiser, see [optimizers].
#' @param callbacks A list of callbacks, see [callbacks].
#' @param augmentation A list of [augmentation_step()] steps, applied to training data only.
#' @param epochs,batch_size Training length and batch size.
#' @param splits Cut each image into a grid of tiles instead of shrinking it: one number
#'   per spatial dimension, so `c(2, 3)` gives six tiles. Use it to segment a large image
#'   without throwing away resolution; predictions are reassembled to the original size.
#' @param weights A checkpoint to start from, or to use as-is with `fit = FALSE`.
#' @param fit Set `FALSE` to load `weights` and skip training.
#' @param encoder A pretrained-architecture backbone to use as the contracting path
#'   instead of the built-in encoder, named as timm names it: `"resnet34"`,
#'   `"efficientnet_b0"`, `"mobilenetv3_large_100"`, `"densenet121"`, `"vgg16"` and the
#'   other convolutional families. Naming one builds that architecture; it does not load
#'   anything. **2D only** - ImageNet is images, so a backbone with a 3D `input_shape` is
#'   refused while the specification is read. The patch-based families (`convnext_*`,
#'   `swin_*`) are refused too: their features start at a quarter of the input, and the
#'   half-resolution level a U-shaped decoder recovers fine detail from does not exist.
#'   `blocks` then says how many of the backbone's stages to use.
#' @param pretrained Load the backbone's ImageNet weights. Separate from `encoder` on
#'   purpose, so naming an architecture never reaches the network on a machine that has
#'   none. Measured on three datasets, transfer does not beat the built-in encoder here -
#'   see [encoders] for the table and what it is actually good for.
#' @param freeze_encoder Hold the transferred layers still for this many epochs, then
#'   train them. **Use this rather than `encoder_learning_rate` alone**: it was the better
#'   of the two on all three datasets measured. A number at or above `epochs` keeps them
#'   fixed for the whole run.
#' @param encoder_learning_rate A separate, smaller rate for the layers that arrived
#'   pretrained. The full-resolution stage in front of them is platypus's own and starts
#'   random, so it keeps the optimiser's rate. Giving this instead of `freeze_encoder`
#'   measured worse everywhere, and on one dataset worse than no backbone at all.
#' @param separation What the network predicts so that touching objects can be told apart -
#'   [separation_rim()] or [separation_flows()]. Giving it is what makes this an **instance**
#'   model: it has no counterpart on a semantic one, so a model carrying it can only mean
#'   instances, which is how a specification knows its task without anybody typing it. The
#'   data has to be [instance_data()] to match. The head's width follows from the signal and
#'   the number of classes and is derived rather than stated.
#'
#'   **It may be left out when `weights` names a file that records it**, since pyplatypus
#'   `0.8.0a28`: a published sidecar says what the channels were trained to predict, and
#'   `"dsbowl-instances"` is a rim of width 2 - a training decision rather than a shape, and
#'   nothing a reader can guess from a model card. So
#'   `u_net("objects", input_shape = c(256, 256), weights = "dsbowl-instances")` beside
#'   [instance_data()] is an instance model, and the engine prints what it adopted.
#'
#'   Left out with **no** `weights` it is still semantic, and still refused beside
#'   [instance_data()] as two tasks in one specification - which is the pair that would
#'   otherwise be silent: the same layout and the same architecture, differing only in
#'   whether a signal is predicted at all. `maju116/rplatypus#181`.
#' @param decode A **list** of [decodings] turning those channels into objects, e.g.
#'   `list(decode_nearest_seed(), decode_connected_components())`. A list rather than one,
#'   because several decodings share a single forward pass: a second costs seconds where a
#'   second training run costs an hour, so [evaluate()] returns a row per model *and*
#'   decoding. Unset, the engine uses the signal's own decoding plus
#'   `decode_connected_components()`, which ignores the signal and is therefore the row the
#'   others have to be read against. Only meaningful with `separation`.
#' @return A model specification, to be passed to [platypus_spec()].
#' @name models
#' @examples
#' u_net("unet", input_shape = c(256, 256), blocks = 4, filters = 16)
#'
#' # A large image, tiled rather than shrunk
#' u_net("hd", input_shape = c(256, 256), splits = c(4, 6))
NULL

# One builder, four names. The signatures are spelled out in the wrappers rather than
# funnelled through `...` so that typing `u_net(` in an editor offers every knob - the
# difference between a package someone explores and one they have to read about first.
segmentation_model <- function(architecture, name, input_shape, channels, n_class,
                               blocks, filters, block_width, dropout,
                               batch_normalization, separable_conv, spatial_dropout,
                               upsample, deep_supervision, activation, initialiser,
                               loss, metrics, optimizer, callbacks, augmentation,
                               epochs, batch_size, splits, weights, fit,
                               encoder, pretrained, freeze_encoder,
                               encoder_learning_rate, separation, decode) {
  if (!is.null(n_class)) {
    stop("`n_class` is not a model setting: the number of classes comes from the data, ",
         "from `colormap` or `labels` in segmentation_data(). It was removed because a ",
         "model that also declared it could only ever disagree with its own data.",
         call. = FALSE)
  }
  # Everything optional arrives as NULL and `compact()` drops it before the request is
  # built, so the engine's own default applies. Two reasons, and the second is the one
  # that bites: a value repeated here is a second place for one fact to live and the two
  # can drift silently - and a default *sent* is indistinguishable from a choice, so an
  # engine that could fill `blocks` and `filters` from a weights file would never get the
  # chance. That is what `output_dir` taught, with a record written into every working
  # directory because R sent a default nobody asked for.
  built <- compact(list(
    name = name,
    architecture = architecture,
    input_shape = as.integer(input_shape),
    channels = int1(channels),
    blocks = int1(blocks),
    filters = int1(filters),
    block_width = int1(block_width),
    dropout = dropout,
    batch_normalization = batch_normalization,
    separable_conv = separable_conv,
    spatial_dropout = spatial_dropout,
    upsample = upsample,
    deep_supervision = deep_supervision,
    activation = activation,
    initialiser = initialiser,
    loss = loss,
    metrics = metrics,
    optimizer = optimizer,
    callbacks = callbacks,
    augmentation = augmentation,
    epochs = int1(epochs),
    batch_size = int1(batch_size),
    splits = if (is.null(splits)) NULL else as.integer(splits),
    weights = weights,
    fit = fit,
    encoder = encoder,
    pretrained = pretrained,
    freeze_encoder = if (is.null(freeze_encoder)) NULL else int1(freeze_encoder),
    encoder_learning_rate = encoder_learning_rate,
    separation = separation,
    decode = decode
  ))

  # The model names its own task, and `separation` is how. It is required on an instance
  # model in the engine and has no counterpart on a semantic one, so a model carrying it
  # can only mean instances and a model without it can only mean semantic - which is why
  # `task` stays read off the constructors rather than typed. `decode` alone is not enough
  # to tag on: it is optional, and a model that decoded without predicting a signal would
  # be a specification with no way to produce one.
  if (is.null(separation)) return(built)
  structure(built, task = "instance_segmentation")
}


#' @rdname models
#' @export
u_net <- function(name, input_shape, channels = NULL, n_class = NULL,
                  blocks = NULL, filters = NULL, block_width = NULL,
                  dropout = NULL, batch_normalization = NULL,
                  separable_conv = NULL, spatial_dropout = NULL,
                  upsample = NULL, deep_supervision = NULL,
                  activation = NULL, initialiser = NULL, loss = NULL,
                  metrics = NULL, optimizer = NULL, callbacks = NULL,
                  augmentation = NULL, epochs = NULL, batch_size = NULL,
                  splits = NULL, weights = NULL, fit = NULL,
                  encoder = NULL, pretrained = NULL, freeze_encoder = NULL,
                  encoder_learning_rate = NULL,
                  separation = NULL, decode = NULL) {
  segmentation_model(
    architecture = "u_net",
    name = name,
    input_shape = input_shape,
    channels = channels,
    n_class = n_class,
    blocks = blocks,
    filters = filters,
    block_width = block_width,
    dropout = dropout,
    batch_normalization = batch_normalization,
    separable_conv = separable_conv,
    spatial_dropout = spatial_dropout,
    upsample = upsample,
    deep_supervision = deep_supervision,
    activation = activation,
    initialiser = initialiser,
    loss = loss,
    metrics = metrics,
    optimizer = optimizer,
    callbacks = callbacks,
    augmentation = augmentation,
    epochs = epochs,
    batch_size = batch_size,
    splits = splits,
    weights = weights,
    fit = fit,
    encoder = encoder,
    pretrained = pretrained,
    freeze_encoder = freeze_encoder,
    encoder_learning_rate = encoder_learning_rate,
    separation = separation,
    decode = decode
  )
}

#' @rdname models
#' @export
u_net_plus_plus <- function(name, input_shape, channels = NULL, n_class = NULL,
                            blocks = NULL, filters = NULL, block_width = NULL,
                            dropout = NULL, batch_normalization = NULL,
                            separable_conv = NULL, spatial_dropout = NULL,
                            upsample = NULL, deep_supervision = NULL,
                            activation = NULL, initialiser = NULL, loss = NULL,
                            metrics = NULL, optimizer = NULL, callbacks = NULL,
                            augmentation = NULL, epochs = NULL, batch_size = NULL,
                            splits = NULL, weights = NULL, fit = NULL,
                            encoder = NULL, pretrained = NULL, freeze_encoder = NULL,
                            encoder_learning_rate = NULL,
                            separation = NULL, decode = NULL) {
  segmentation_model(
    architecture = "u_net_plus_plus",
    name = name,
    input_shape = input_shape,
    channels = channels,
    n_class = n_class,
    blocks = blocks,
    filters = filters,
    block_width = block_width,
    dropout = dropout,
    batch_normalization = batch_normalization,
    separable_conv = separable_conv,
    spatial_dropout = spatial_dropout,
    upsample = upsample,
    deep_supervision = deep_supervision,
    activation = activation,
    initialiser = initialiser,
    loss = loss,
    metrics = metrics,
    optimizer = optimizer,
    callbacks = callbacks,
    augmentation = augmentation,
    epochs = epochs,
    batch_size = batch_size,
    splits = splits,
    weights = weights,
    fit = fit,
    encoder = encoder,
    pretrained = pretrained,
    freeze_encoder = freeze_encoder,
    encoder_learning_rate = encoder_learning_rate,
    separation = separation,
    decode = decode
  )
}

#' @rdname models
#' @export
res_u_net <- function(name, input_shape, channels = NULL, n_class = NULL,
                      blocks = NULL, filters = NULL, block_width = NULL,
                      dropout = NULL, batch_normalization = NULL,
                      separable_conv = NULL, spatial_dropout = NULL,
                      upsample = NULL, deep_supervision = NULL,
                      activation = NULL, initialiser = NULL, loss = NULL,
                      metrics = NULL, optimizer = NULL, callbacks = NULL,
                      augmentation = NULL, epochs = NULL, batch_size = NULL,
                      splits = NULL, weights = NULL, fit = NULL,
                      encoder = NULL, pretrained = NULL, freeze_encoder = NULL,
                      encoder_learning_rate = NULL,
                      separation = NULL, decode = NULL) {
  segmentation_model(
    architecture = "res_u_net",
    name = name,
    input_shape = input_shape,
    channels = channels,
    n_class = n_class,
    blocks = blocks,
    filters = filters,
    block_width = block_width,
    dropout = dropout,
    batch_normalization = batch_normalization,
    separable_conv = separable_conv,
    spatial_dropout = spatial_dropout,
    upsample = upsample,
    deep_supervision = deep_supervision,
    activation = activation,
    initialiser = initialiser,
    loss = loss,
    metrics = metrics,
    optimizer = optimizer,
    callbacks = callbacks,
    augmentation = augmentation,
    epochs = epochs,
    batch_size = batch_size,
    splits = splits,
    weights = weights,
    fit = fit,
    encoder = encoder,
    pretrained = pretrained,
    freeze_encoder = freeze_encoder,
    encoder_learning_rate = encoder_learning_rate,
    separation = separation,
    decode = decode
  )
}

#' @rdname models
#' @export
linknet <- function(name, input_shape, channels = NULL, n_class = NULL,
                    blocks = NULL, filters = NULL, block_width = NULL,
                    dropout = NULL, batch_normalization = NULL,
                    separable_conv = NULL, spatial_dropout = NULL,
                    upsample = NULL, deep_supervision = NULL,
                    activation = NULL, initialiser = NULL, loss = NULL,
                    metrics = NULL, optimizer = NULL, callbacks = NULL,
                    augmentation = NULL, epochs = NULL, batch_size = NULL,
                    splits = NULL, weights = NULL, fit = NULL,
                    encoder = NULL, pretrained = NULL, freeze_encoder = NULL,
                    encoder_learning_rate = NULL,
                    separation = NULL, decode = NULL) {
  segmentation_model(
    architecture = "linknet",
    name = name,
    input_shape = input_shape,
    channels = channels,
    n_class = n_class,
    blocks = blocks,
    filters = filters,
    block_width = block_width,
    dropout = dropout,
    batch_normalization = batch_normalization,
    separable_conv = separable_conv,
    spatial_dropout = spatial_dropout,
    upsample = upsample,
    deep_supervision = deep_supervision,
    activation = activation,
    initialiser = initialiser,
    loss = loss,
    metrics = metrics,
    optimizer = optimizer,
    callbacks = callbacks,
    augmentation = augmentation,
    epochs = epochs,
    batch_size = batch_size,
    splits = splits,
    weights = weights,
    fit = fit,
    encoder = encoder,
    pretrained = pretrained,
    freeze_encoder = freeze_encoder,
    encoder_learning_rate = encoder_learning_rate,
    separation = separation,
    decode = decode
  )
}
