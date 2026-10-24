# Losses, metrics, optimisers and callbacks.
#
# Named the way the old platypus and the R keras package name things - `loss_dice()`,
# `metric_iou()`, `optimizer_adam()` - because R has one namespace per package and a
# `dice()` that is a loss cannot coexist with a `dice()` that is a metric. The prefixes
# also make the whole family discoverable by typing `loss_` and waiting.
#
# Integers are coerced here rather than left to pydantic. R numbers are doubles, so a
# plain `4` arrives in Python as `4.0`; relying on coercion works until someone writes
# `blocks = 4.5` and gets a puzzling message from a library they never invoked.

int1 <- function(x) if (is.null(x)) NULL else as.integer(x)

#' Loss functions
#'
#' The objective the model is trained against. Every one of these works unchanged on
#' volumes as well as images.
#'
#' There is one documented separately because it needs a page of its own: [loss_boundary()]
#' adds the signed distance to the truth's boundary on top of any of these, which removes
#' the systematic volume bias at some cost in per-case accuracy.
#'
#' **Three of these score numbers rather than classes** - `loss_mse()`, `loss_l1()` and
#' `loss_smooth_l1()` - and they are not alternatives to the others. A class target has
#' nothing for them to measure and a continuous one has nothing for an overlap to measure,
#' so they belong in exactly one place: the `loss` of [separation_flows()], where the target
#' is a vector field. Measured against the pinned engine rather than assumed: giving one as
#' **any** segmentation model's own `loss` is refused by name - semantic or instance - and
#' giving a class loss to [separation_flows()] is refused by name the other way round.
#'
#' **One of these weights the classes rather than treating them alike** -
#' `loss_generalized_dice()`, by the inverse square of how much of the picture each class
#' occupies - and the argument usually made for it is not the argument for it here. It is
#' introduced in the literature as a fix for Dice being dominated by the background, and
#' `loss_dice()` in this package is a mean over the class channels: a lesion in 1% of the
#' frame already carries the same weight as the 99% around it. Measured on a 1% target, with
#' one prediction that finds the lesion and leaks a false positive of equal size and one that
#' misses it and gets the background perfect:
#'
#' | loss | finds it | misses it | prefers finding by |
#' |---|---|---|---|
#' | `loss_dice()` | 0.1658 | 0.4731 | 0.3073 |
#' | `loss_cce()` | 0.1600 | 0.1600 | nothing at all |
#' | `loss_cce_dice()` | 0.1629 | 0.3166 | 0.1536 |
#' | `loss_generalized_dice()` | 0.3278 | 0.9511 | 0.6233 |
#'
#' So what it adds is weight **beyond** an equal share - on that target the classes come out
#' weighted 1 to 9801 - and the objective that is genuinely dominated is the per-pixel half
#' of `loss_cce_dice()`: to cross-entropy a false positive and a missed lesion of the same
#' size are the same number of wrong pixels, which is the indifference in that row. Two
#' things follow. With every class the same size this is **exactly `loss_dice()` pooled over
#' the classes**, so on a balanced problem it costs nothing and buys nothing. And it is not a
#' third `loss_tversky()`: Tversky moves the balance between false positives and false
#' negatives by a number you choose, `loss_focal_tversky()` reweights the hard pixels, and
#' this reweights classes by how much of the image they occupy, computed from each batch
#' rather than set by hand - so a batch holding no lesion at all is scored on flat weights,
#' which is an argument for a larger `batch_size` on a sparse dataset rather than against the
#' loss.
#'
#' This page said *an instance model's own* until the pin moved to `0.8.0a22`, and it was
#' true rather than wrong: the refusal lived on the instance class alone, and a semantic
#' model accepted `loss_mse()` and trained with it, reporting a validation loss of 0.0014
#' for a mask that was half missing where `loss_cce()` reaches a Dice of 1.0000. The default
#' `where = "foreground"` is what made it look as though it had worked - it evaluates the
#' objective only inside the labelled objects and leaves the background unconstrained. The
#' engine refuses it at either task now (`pyplatypus#223`).
#'
#' @param smooth Added to numerator and denominator to keep an empty class finite.
#' @param gamma For focal losses, how hard to discount the pixels already classified well.
#' @param alpha For Tversky, the weight on false negatives; raising it buys recall.
#'   Note that `alpha = 0.5` is Dice exactly only when `smooth = 0`.
#' @param label_smoothing For cross-entropy, train towards `1 - label_smoothing` instead of
#'   towards 1, so the model is not pushed to be certain. Worth having where the labels
#'   themselves are uncertain, which on a hand-drawn boundary they are.
#' @param cce_weight For `loss_cce_dice()`, how much of the total the cross-entropy half
#'   provides. At 0 or 1 it is one of the two alone, which is worth knowing before tuning it
#'   as though it were a third thing.
#' @param ce_ratio For `loss_combo()`, how its cross-entropy half is tilted between
#'   punishing missed foreground (towards 1) and false alarms (towards 0), while `alpha`
#'   sets how much of the total each half provides.
#' @param per_image For `loss_lovasz()`, sort the errors of each image separately rather
#'   than over the whole batch. The harsher reading, and on mostly empty images the noisier
#'   one.
#' @param where For the three regression losses, where the target means anything and so
#'   where the error is averaged. A flow field is defined on the objects and undefined off
#'   them - there is no direction towards a centre for a pixel in no object - so the builder
#'   writes zero on the background, and `"everywhere"` would spend most of the objective
#'   learning that zero. The foreground is 13.97% of a Data Science Bowl image, so
#'   `"everywhere"` gives 86% of the gradient to a constant; `"foreground"` is the default
#'   for that reason rather than by taste.
#' @param beta For `loss_smooth_l1()`, where the quadratic part ends and the linear one
#'   begins, **in the target's own units**. A flow field is scaled to roughly `[-1, 1]`, so
#'   the default of 1 makes the whole range quadratic - which is `loss_mse()` with extra
#'   steps. Lower it to get any of the robustness this loss is for.
#' @return A loss specification, to be passed to a model constructor.
#' @name losses
#' @seealso [separation_flows()], whose `loss` is the one place the regression losses belong
#' @examples
#' loss_focal(gamma = 2)
#' loss_tversky(alpha = 0.7)
#' loss_smooth_l1(beta = 0.1, where = "foreground")
NULL

#' @rdname losses
#' @export
loss_iou <- function(smooth = 1) list(name = "iou", smooth = smooth)

#' @rdname losses
#' @export
loss_dice <- function(smooth = 1) list(name = "dice", smooth = smooth)

#' @rdname losses
#' @export
loss_generalized_dice <- function(smooth = 1) {
  list(name = "generalized_dice", smooth = smooth)
}

#' @rdname losses
#' @export
loss_cce <- function(label_smoothing = 0) {
  list(name = "cce", label_smoothing = label_smoothing)
}

#' @rdname losses
#' @export
loss_cce_dice <- function(cce_weight = 0.5, smooth = 1) {
  list(name = "cce_dice", cce_weight = cce_weight, smooth = smooth)
}

#' @rdname losses
#' @export
loss_focal <- function(gamma = 2, alpha = NULL) {
  list(name = "focal", gamma = gamma, alpha = alpha)
}

#' @rdname losses
#' @export
loss_tversky <- function(alpha = 0.5, smooth = 1) {
  list(name = "tversky", alpha = alpha, smooth = smooth)
}

#' @rdname losses
#' @export
loss_focal_tversky <- function(alpha = 0.5, gamma = 1, smooth = 1) {
  list(name = "focal_tversky", alpha = alpha, gamma = gamma, smooth = smooth)
}

#' @rdname losses
#' @export
loss_combo <- function(alpha = 0.5, ce_ratio = 0.5) {
  list(name = "combo", alpha = alpha, ce_ratio = ce_ratio)
}

# The three below are the objective for a continuous target, which in R means the vector
# channels of `separation_flows()` and nothing else. `where` is carried rather than
# defaulted here, because an R-side default would be a value the engine could not tell from
# one the user chose - §3D.4 - and the engine's own default stands on a measurement.

#' @rdname losses
#' @export
loss_mse <- function(where = NULL) {
  compact(list(name = "mse", where = where))
}

#' @rdname losses
#' @export
loss_l1 <- function(where = NULL) {
  compact(list(name = "l1", where = where))
}

#' @rdname losses
#' @export
loss_smooth_l1 <- function(beta = NULL, where = NULL) {
  compact(list(name = "smooth_l1", beta = beta, where = where))
}

#' A loss that knows how far a wrong voxel is from the truth
#'
#' Dice and IoU count a voxel the same wherever it sits, which is why a model can reach 0.88
#' on Dice while its volumes run a fifth too large: the overshoot is all at the boundary, and
#' for a small lesion the boundary is most of the object. This adds `mean(phi * p)`, where
#' `phi` is the signed distance to the truth's boundary - negative inside, positive outside -
#' so a voxel predicted far outside the truth costs in proportion to how far.
#'
#' @details
#' **What it buys and what it costs, measured.** Three seeds, 60 epochs, lesions with
#' ambiguous edges, against Dice alone:
#'
#' | loss | Dice | volume bias | volume \|error\| |
#' |---|---|---|---|
#' | `loss_dice()` | 0.9525 ±0.0027 | -5.18% ±3.11% | 16.90% ±0.90% |
#' | `loss_boundary()` | 0.9411 ±0.0093 | -0.06% ±4.15% | 22.17% ±2.88% |
#'
#' It trades **accuracy per case** for **being unbiased over a series**. "Is there a lesion"
#' wants the overlap; "has it grown since March" wants a volume that is not systematically
#' wrong, and no single number answers both - which is the same point [mask_volume()] makes
#' about reporting millilitres beside an overlap score. The bias improvement is suggestive on
#' three seeds, since the baseline's own bias wanders ±3.11%; the costs are established.
#'
#' **It costs time too.** The signed distance transform runs once per sample, in the loader's
#' workers: 5.3 ms for a 256x256 image, 23.4 ms for a 64x64x32 volume and 709.8 ms at 128^3.
#' On large volumes give [platypus_fit()] workers, or the transform becomes the training.
#'
#' @param region The overlap term this is added to - any other loss. Unset uses the engine's
#'   default, which is Dice. `loss_focal()` here is what this feature was originally asked
#'   for: focal combined with a distance metric. `loss_generalized_dice()` here is the
#'   combination worth knowing about, because the two features are motivated by the same
#'   picture: this loss exists for a lesion in a thousandth of a frame, and a surface term
#'   exists for an object whose boundary is most of it.
#' @param alpha How much of the objective is the region term, `1 - alpha` the surface term.
#'   Unset uses the engine's default of 0.9.
#'
#'   **Not 0.5, and that was measured.** At 0.5 the surface term owns half the objective
#'   while the prediction is still random, which is where it is unstable: three seeds gave a
#'   volume error spread of ±28.28% against the baseline's ±3.11%, with every number worse.
#'   Left unset here on purpose - the number is a measurement and belongs in the one place
#'   the measurement lives, so that an engine that learns better cannot be contradicted from
#'   this side.
#' @return A loss specification, to be passed to a model constructor.
#' @seealso [losses] for the losses that can be the region term - every one of them
#'   except the three that score numbers and this one, held to the engine's own union by
#'   a test rather than counted here - and [mask_volume()] for reading a volume in
#'   millilitres rather than voxels.
#' @export
#' @examples
#' loss_boundary()
#' loss_boundary(region = loss_focal(gamma = 2))
#' loss_boundary(region = loss_dice(), alpha = 0.95)
loss_boundary <- function(region = NULL, alpha = NULL) {
  bad_alpha <- !is.numeric(alpha) || length(alpha) != 1L || is.na(alpha) ||
    alpha <= 0 || alpha >= 1
  if (!is.null(alpha) && bad_alpha) {
    stop("`alpha` is one number strictly between 0 and 1. At 1 the surface term is absent ",
         "and the name is a lie; at 0 nothing measures how much of the object was found.",
         call. = FALSE)
  }
  if (!is.null(region) && identical(region$name, "boundary")) {
    stop("`region` is an overlap loss, not another `loss_boundary()`. Two surface terms ",
         "with no region term holding either of them down is the one combination that ",
         "cannot work.", call. = FALSE)
  }
  list(name = "boundary", region = region, alpha = alpha)
}

#' @rdname losses
#' @export
loss_lovasz <- function(per_image = FALSE) list(name = "lovasz", per_image = per_image)

#' Metrics
#'
#' What gets reported. Unlike the losses these are computed on the hard prediction - the
#' mask you will actually be handed - because a metric taken on probabilities reads higher
#' than the model deserves.
#'
#' **Three of these ask the same question and two ask different ones.** `metric_iou()`,
#' `metric_dice()` and `metric_tversky()` all ask how much of the mask coincides and differ
#' in how they weigh the ways of being wrong. `metric_cldice()` asks whether the *structure*
#' coincides, and `metric_surface_dice()` asks **how far wrong the boundary is** - which is
#' the question a contour somebody has to approve is actually judged by, and the one nothing
#' here reported until the pin moved to `0.8.0a26`.
#'
#' For something thin and connected clDice is the question worth asking, and it and Dice
#' disagree in a way worth knowing. Measured on a nine-pixel vessel: one drawn two pixels
#' thin scores Dice 0.875, and the same vessel severed in the middle scores 0.947 - **Dice
#' prefers the severed one**. clDice gives them 1.000 and 0.943.
#'
#' Its limit, also measured: at one pixel wide a displacement of one pixel leaves no overlap
#' at all, and every overlap-based metric reads 0, this one included.
#'
#' `metric_surface_dice()` is the other kind of disagreement. [loss_boundary()]'s own page
#' reports a model at Dice 0.9525 whose volumes run 5% small and 17% wrong per case, and no
#' overlap column says that: a displaced boundary and a correct one of the same area score
#' alike. This is normalised surface Dice (Nikolov et al., 2018), symmetric on purpose - the
#' truth's surface near the prediction is the boundary's recall, the prediction's surface
#' near the truth is its precision - and it is the one metric here that reads the voxel
#' spacing, so `tau` is in millimetres when `target_spacing` has put the data on a common
#' grid and in voxels when it has not. It is also what `loss_boundary()` optimises, so until
#' now that loss was being judged by the metric it exists to improve on.
#'
#' Like clDice it is a property of a whole mask rather than of a batch of counts, so on a
#' tiled run (`splits`) it is reported **per case** by [evaluate_cases()] and is absent from
#' the epoch history - a per-batch average of per-tile boundaries would be a number about
#' nothing. A callback asking to watch `val_surface_dice` on such a run is refused when the
#' configuration is read, the way one watching `val_cldice` is - so the choice to tile and
#' the choice of what to stop on are settled together, before anything is trained.
#'
#' `include_background` defaults to `FALSE` for those two and `TRUE` for the three overlap
#' metrics, and each has its own measured reason. The background's skeleton lies inside the
#' background by construction, so that class scores 1 for clDice whatever the model did -
#' averaging it in moved 0.7865 to 0.8933 on a three-pixel vessel. The background's
#' *boundary* is the foreground's boundary plus the edge of the picture, and that edge agrees
#' between any two masks whatever happened in them: measured on four random pairs at
#' `tau = 2`, the background scored 0.6110 to 0.7030 against the foreground's 0.5583 to
#' 0.6266 - higher every time. That is agreement on the field of view rather than on the
#' object.
#'
#' @param smooth Smoothing. Zero is allowed and is the honest choice for a reported
#'   number: with smoothing, a class absent from an image scores a perfect 1.
#' @param include_background Average over the background class as well. In medical images
#'   the background is usually most of the picture, so leaving it in can turn a model that
#'   found nothing into one that looks respectable. Papers report foreground only. It
#'   defaults to `TRUE` for the three overlap metrics and `FALSE` for `metric_cldice()` and
#'   `metric_surface_dice()`, where the background class does not merely flatter a model but
#'   measures something that is not the question - its skeleton and its boundary are both
#'   artefacts of the frame rather than of what was found. The paragraphs above give both
#'   measurements.
#' @param alpha For Tversky, the weight on false negatives.
#' @param tau For `metric_surface_dice()`, the tolerance a boundary is allowed to be wrong
#'   by, and it is **required because no default would be honest**. A tolerance belongs to
#'   the structure and the dataset rather than to a package: conventionally it is the
#'   inter-observer variability for that structure - the distance two people drawing the same
#'   boundary differ by - and published values exist per organ and per challenge. Take one
#'   from the protocol you are comparing against. In millimetres where `target_spacing` puts
#'   every case on a common grid, and in voxels where it does not, which is the same pair of
#'   answers the signed distance map in [loss_boundary()] gives and for the same reason: a
#'   0.5 mm and a 2.5 mm acquisition are not comparable in voxels at all.
#' @param iterations For clDice, how many times the skeleton is peeled. It has to reach the
#'   half-width of the thickest structure, or its core is never reduced to a centreline and
#'   the score is refused rather than reported - an empty skeleton otherwise reads as a
#'   perfect 1.
#' @return A metric specification.
#' @name metrics
#' @examples
#' metric_dice(include_background = FALSE)
#'
#' # Vessels, airways, neurons, cracks: thin and connected, where Dice asks the wrong thing.
#' metric_cldice()
#'
#' # How far wrong the boundary is, rather than how much of the area coincides. 1.5 mm
#' # because that is this structure's inter-observer variability, not because of anything
#' # here.
#' metric_surface_dice(tau = 1.5)
NULL

#' @rdname metrics
#' @export
metric_iou <- function(smooth = 1, include_background = TRUE) {
  list(name = "iou", smooth = smooth, include_background = include_background)
}

#' @rdname metrics
#' @export
metric_dice <- function(smooth = 1, include_background = TRUE) {
  list(name = "dice", smooth = smooth, include_background = include_background)
}

#' @rdname metrics
#' @export
metric_tversky <- function(alpha = 0.5, smooth = 1, include_background = TRUE) {
  list(name = "tversky", alpha = alpha, smooth = smooth,
       include_background = include_background)
}

#' @rdname metrics
#' @export
metric_cldice <- function(iterations = 5, smooth = 1, include_background = FALSE) {
  list(name = "cldice", iterations = iterations, smooth = smooth,
       include_background = include_background)
}

#' @rdname metrics
#' @export
metric_surface_dice <- function(tau, smooth = 1, include_background = FALSE) {
  if (!is.numeric(tau) || length(tau) != 1L || is.na(tau) || tau <= 0) {
    stop("`tau` is one positive number: the distance a boundary may be wrong by, in the ",
         "units `target_spacing` puts the data in. There is no default because a tolerance ",
         "belongs to the structure being drawn - see ?metrics.", call. = FALSE)
  }
  list(name = "surface_dice", tau = tau, smooth = smooth,
       include_background = include_background)
}

#' Optimisers
#'
#' How the weights are updated. `optimizer_adam()` unless there is a reason not to: it adapts
#' the step per parameter, so it usually trains without anything tuned except
#' `learning_rate`. `optimizer_sgd()` with `momentum` is the recipe most of the
#' classification literature's best numbers were produced with, in exchange for depending on
#' a tuned rate and usually a schedule - see [callbacks] for those.
#'
#' **No run in this project has compared them on segmentation**, so this page says what each
#' one does differently rather than which is better. [available_optimizers()] lists them with
#' the arguments each accepts.
#'
#' The rest are here because a configuration should be able to name what torch offers.
#' `optimizer_adamw()` is Adam with weight decay applied to the weights rather than through
#' the gradient, which is why its decay defaults to 0.01 rather than 0 - choosing it and
#' leaving the decay at zero leaves nothing to choose. `optimizer_adagrad()` accumulates
#' every squared gradient it has seen, so its step only ever shrinks and a long run can stop
#' learning; `optimizer_adadelta()` is the same idea with a window instead of a sum.
#' `optimizer_adamax()` tracks the largest gradient rather than the average of their squares,
#' which is steadier where a few batches carry very large ones. `optimizer_rmsprop()` is
#' Adam's denominator without its momentum, and `optimizer_nadam()` is Adam with the
#' look-ahead that SGD calls `nesterov`.
#'
#' Every argument left unset is decided by the engine, which is where the defaults live.
#'
#' @param learning_rate How big a step to take. The one setting worth trying first when a run
#'   will not learn: too high and the loss moves without improving, too low and it improves
#'   too slowly to tell from not improving at all. Each parameter group decays from its own
#'   rate, so an `encoder_learning_rate` is not flattened by a schedule.
#' @param weight_decay Pull the weights towards zero at every step, which is L2
#'   regularisation. Off by default because it interacts with the loss and is not free: on a
#'   small dataset it can cost more than the overfitting it prevents. In `optimizer_adamw()`
#'   it is applied to the weights directly rather than through the gradient, which is the
#'   whole difference between the two.
#' @param beta_1 Decay for the running average of the gradient. Lower reacts to the last few
#'   batches, higher smooths over more of them; 0.9 is the usual value and rarely worth
#'   moving.
#' @param beta_2 Decay for the running average of the squared gradient, which is what scales
#'   each parameter's step. Below about 0.99 training gets noticeably noisier. In
#'   `optimizer_adamax()` it decays the largest gradient seen instead.
#' @param eps Added to the denominator so a parameter whose gradient has been zero for a
#'   while does not take an enormous step. A guard, not a knob.
#' @param amsgrad Keep the largest squared-gradient average seen so far rather than the
#'   current one, so the step size never grows back. It fixes a convergence case in Adam's
#'   proof and usually changes nothing in practice; worth trying if a run plateaus and then
#'   gets worse.
#' @param momentum Carry a fraction of the previous step into this one. 0 is plain gradient
#'   descent; 0.9 is the usual choice and is what makes SGD competitive with the adaptive
#'   methods.
#' @param nesterov Look ahead to where momentum is about to carry the weights before
#'   measuring the gradient. Needs `momentum` above 0, and giving it without momentum is
#'   refused rather than ignored.
#' @param alpha For `optimizer_rmsprop()`, the decay for its running average of the squared
#'   gradient - the same work `beta_2` does in the Adam family, under that family's name.
#' @param rho For `optimizer_adadelta()`, how long a window of squared gradients to remember.
#'   Adadelta exists to avoid Adagrad's ever-shrinking step and this is the parameter that
#'   does it.
#' @param lr_decay For `optimizer_adagrad()`, shrink the rate further as training goes on, on
#'   top of the shrinking Adagrad already does by accumulating every squared gradient it has
#'   seen.
#' @return An optimiser specification.
#' @seealso [available_optimizers()] for the same list with its arguments, and [callbacks()]
#'   for moving the rate during a run.
#' @name optimizers
#' @examples
#' optimizer_adam(learning_rate = 1e-4)
#' optimizer_sgd(learning_rate = 0.01, momentum = 0.9, nesterov = TRUE)
NULL

#' @rdname optimizers
#' @export
optimizer_adam <- function(learning_rate = 1e-3, beta_1 = 0.9, beta_2 = 0.999,
                           eps = 1e-8, weight_decay = 0, amsgrad = FALSE) {
  list(name = "adam", learning_rate = learning_rate, beta_1 = beta_1, beta_2 = beta_2,
       eps = eps, weight_decay = weight_decay, amsgrad = amsgrad)
}

#' @rdname optimizers
#' @export
optimizer_adamw <- function(learning_rate = 1e-3, beta_1 = 0.9, beta_2 = 0.999,
                            eps = 1e-8, weight_decay = 1e-2) {
  list(name = "adamw", learning_rate = learning_rate, beta_1 = beta_1, beta_2 = beta_2,
       eps = eps, weight_decay = weight_decay)
}

#' @rdname optimizers
#' @export
optimizer_sgd <- function(learning_rate = 1e-3, momentum = 0, nesterov = FALSE,
                          weight_decay = 0) {
  list(name = "sgd", learning_rate = learning_rate, momentum = momentum,
       nesterov = nesterov, weight_decay = weight_decay)
}

#' @rdname optimizers
#' @export
optimizer_rmsprop <- function(learning_rate = 1e-3, alpha = 0.99, momentum = 0,
                              eps = 1e-8, weight_decay = 0) {
  list(name = "rmsprop", learning_rate = learning_rate, alpha = alpha,
       momentum = momentum, eps = eps, weight_decay = weight_decay)
}

#' @rdname optimizers
#' @export
optimizer_adagrad <- function(learning_rate = 1e-3, lr_decay = 0, eps = 1e-10,
                              weight_decay = 0) {
  list(name = "adagrad", learning_rate = learning_rate, lr_decay = lr_decay,
       eps = eps, weight_decay = weight_decay)
}

#' @rdname optimizers
#' @export
optimizer_adadelta <- function(learning_rate = 1e-3, rho = 0.9, eps = 1e-6,
                               weight_decay = 0) {
  list(name = "adadelta", learning_rate = learning_rate, rho = rho, eps = eps,
       weight_decay = weight_decay)
}

#' @rdname optimizers
#' @export
optimizer_adamax <- function(learning_rate = 1e-3, beta_1 = 0.9, beta_2 = 0.999,
                             eps = 1e-8, weight_decay = 0) {
  list(name = "adamax", learning_rate = learning_rate, beta_1 = beta_1,
       beta_2 = beta_2, eps = eps, weight_decay = weight_decay)
}

#' @rdname optimizers
#' @export
optimizer_nadam <- function(learning_rate = 1e-3, beta_1 = 0.9, beta_2 = 0.999,
                            eps = 1e-8, weight_decay = 0) {
  list(name = "nadam", learning_rate = learning_rate, beta_1 = beta_1,
       beta_2 = beta_2, eps = eps, weight_decay = weight_decay)
}

#' Callbacks
#'
#' Things that happen between epochs. `monitor` is checked against the metrics the model
#' actually asks for, so a callback watching a number that will never arrive is refused
#' when the specification is built rather than waited on forever.
#'
#' Whether the watched quantity should rise or fall is worked out from its name: anything
#' ending in `loss` is minimised, everything else maximised.
#'
#' @section The one number that is not about quality:
#'
#' Every epoch reports `foreground` as well - for both passes, `train_foreground` and
#' `val_foreground` - which is the share of the prediction that is **not background**.
#' Nothing is compared against the truth, so it is not a measure of how good the model is;
#' it answers whether the model is still producing a segmentation at all.
#'
#' It is reported whether or not you ask for it, and that is the point. A model that
#' collapses to predicting background everywhere is invisible in the numbers it already
#' produced: with `include_background = TRUE` the Dice is a mean over class channels and
#' the background channel is nearly perfect, so a collapsed model reports around 0.5 while
#' its loss falls contentedly. A collapse you have to opt into noticing is one you will not
#' notice.
#'
#' `callback_terminate_on_collapse()` acts on it, `evaluate()` carries it as a column, and
#' `callback_model_checkpoint()`'s `when` can take a condition on it.
#'
#' There is an eleventh, documented separately because it needs a page of its own:
#' [callback_swa()] averages the weights over the last part of the run. It watches
#' nothing and changes how reproducible a run is rather than how well it scores.
#'
#' @section One hand on the learning rate:
#'
#' Three of these compute the rate from the epoch rather than from how the run is going -
#' `callback_cosine_annealing()`, `callback_linear_annealing()` and
#' `callback_step_decay()` - and **at most one of them may be used**, because each
#' recomputes the rate every epoch and two of them would simply overwrite each other.
#'
#' For the same reason a schedule and `callback_reduce_lr_on_plateau()` **cannot be
#' combined**, and the engine refuses the pair. That refusal replaced a sentence claiming
#' the opposite: a schedule recomputes the rate from the optimiser's initial value at the
#' end of every epoch, so it erases whatever the plateau callback cut. Measured on six
#' epochs of a loss that never improves, the rate with both configured follows the cosine
#' exactly - 0.0976, 0.0905, 0.0794 from 0.1 - where the plateau alone reaches 1e-6.
#'
#' A schedule beside [callback_swa()] is fine and the order is no longer luck: `swa` pins
#' its constant rate after averaging begins, whatever position the callbacks sit in.
#'
#' @section Cosine annealing:
#'
#' `callback_cosine_annealing()` decays the learning rate from its initial value to `min_lr`
#' along a cosine. It watches nothing: it is a function of how far through the run you are
#' rather than of how the run is going, which is the difference from
#' `callback_reduce_lr_on_plateau()` - and a run may legitimately want both.
#'
#' Each parameter group decays from its **own** initial rate, so an `encoder_learning_rate`
#' set on a model is not flattened at the first epoch. That would have been invisible: the
#' history records one `learning_rate`, the first group's.
#'
#' `epochs` unset means the model's own `epochs`, which is what you want - a cosine that
#' ends where the run ends.
#'
#' @param monitor What to watch: `"val_loss"`, `"train_loss"`, `"val_"` followed by a
#'   metric name such as `"val_dice"`, or `"val_foreground"` and `"train_foreground"` -
#'   the share of the prediction that is not background, which every epoch reports whether
#'   or not it was asked for.
#' @param patience Epochs to wait before acting. For
#'   `callback_terminate_on_collapse()` that is epochs in a row below the floor, and it is
#'   not 1 because an early epoch legitimately predicts almost nothing.
#' @param min_delta Improvement smaller than this does not count.
#' @param restore_best Put the best weights back when training stops, rather than keeping
#'   the last - which are by definition the ones that were not improving. On by default.
#'   Note that `callback_swa()` replaces nothing if a run stops before averaging began.
#' @param path Where to write. For `callback_model_checkpoint()` that is the weights file; for
#'   `callback_csv_logger()` it is one row per epoch appended as the epoch ends - the same
#'   numbers [training_history()] returns, so a run that is interrupted still leaves its
#'   history behind. Re-read against the engine's own text when it changed in `0.8.0a23`,
#'   which is what the field-prose ledger is for: the engine's sentence had named this
#'   package's `training_history()` to a Python reader, and the fix there left R's `@param`
#'   saying three words about two different files.
#'
#'   **The checkpoint's extension decides its format**, since the engine's `0.8.0a31`:
#'   `.safetensors` is written as safetensors and anything else as a torch archive, which
#'   is what `.pt` has always meant. Before that the file was a torch archive whatever it
#'   was called, so a checkpoint named after the files this package publishes was written
#'   in one format and read as another - and reading now goes by the file's contents rather
#'   than by its name, so a checkpoint written by an older engine still loads. A checkpoint
#'   is the run's safety net; [export_weights()] is what writes a file for somebody else to
#'   load, with the sidecar that says what it is for.
#' @param save_best_only Only write when the watched quantity improves, which is the
#'   default. `FALSE` writes every epoch, which is what to use when a run may be
#'   interrupted rather than when the best epoch is what you want to keep.
#' @param factor,min_lr What the rate is multiplied by, and the floor it stops at.
#'   `factor` is the cut on a plateau for `callback_reduce_lr_on_plateau()` and the drop
#'   at each step for `callback_step_decay()`, where it must be below 1 - a step schedule
#'   that raises the rate is a different idea and accepting it here would hide a typo.
#'   `min_lr` is the floor for all four.
#' @param epochs For `callback_cosine_annealing()` and `callback_linear_annealing()`, how
#'   many epochs to spread the decay over. Unset means the model's `epochs`, which is what
#'   you want: a curve that ends where the run ends.
#' @param start,start_epoch When the callback may begin to act - **one of the two and
#'   never both**. `start` is a fraction of the run (`0.1` leaves the first tenth alone)
#'   and `start_epoch` is an epoch number. Two arguments rather than one taking either,
#'   because a fraction survives a change to `epochs` and an epoch count does not, and in
#'   a YAML specification `1` and `1.0` are the same value once parsed - so one field
#'   would make "epoch one" and "the whole run" indistinguishable.
#'
#'   For `callback_early_stopping()` this is a **warm-up**: a model that needs fifteen
#'   epochs before its validation curve means anything would otherwise need
#'   `patience > 15` for the whole run, paying that slack at the end as well. It delays
#'   **the stopping and nothing else** - an epoch inside the warm-up can still be the best
#'   one and `restore_best` still returns to it, because those are the best weights the run
#'   has if it ends for another reason.
#'
#'   For `callback_swa()` it is the point averaging begins, which is the same concept and
#'   therefore the same two words.
#' @param when For `callback_model_checkpoint()`, a named list of thresholds that must
#'   **all** hold before anything is written: `list(val_dice = 0.9, val_loss = 0.2)`.
#'   **The direction is derived, not configured** - anything ending in `loss` has to be
#'   below its threshold and everything else above it, the same rule `monitor` uses - so
#'   there is no argument to get backwards. The names are checked against what the model
#'   reports when the specification is built, not at the first epoch.
#'
#'   It is an **extra gate beside `save_best_only`**, not a replacement: with both, a file
#'   is written when the watched number improves *and* every threshold holds. A threshold
#'   is a number about your data and does not transfer between datasets, and a run whose
#'   conditions never hold writes nothing and says so when it ends.
#' @param floor For `callback_terminate_on_collapse()`, the share of foreground below
#'   which a prediction counts as collapsed. A floor rather than a test for zero, because
#'   0.01% foreground against a target that is 14% foreground has collapsed in every sense
#'   that matters. The default sits far below any real target on purpose: this guards
#'   against a failure, not against a model being merely bad, and a floor near a real
#'   foreground share would end runs that were only disappointing.
#' @param hours For `callback_stop_after()`, a wall-clock budget. An epoch cap cannot
#'   express it, because how long an epoch takes is a property of the data and the shape.
#'   Checked at the end of an epoch, so the real limit is this plus one epoch; the run's
#'   stop reason names the clock, so a run that ran out of time does not read as one that
#'   converged.
#' @param every,milestones For `callback_step_decay()`, **one of the two and never both**.
#'   `every = 30` drops every thirty epochs; `milestones = c(30, 60)` drops at those
#'   epochs, 1-based and strictly increasing, which is how a published recipe states it.
#'   Two arguments rather than one that takes either, because `30` and `c(30)` are
#'   different schedules and a single argument holding either would be read as whichever
#'   was typed. A period survives a change to `epochs`; a list of milestones does not.
#' @return A callback specification.
#' @name callbacks
#' @examples
#' callback_early_stopping(monitor = "val_dice", patience = 10)
NULL

#' @rdname callbacks
#' @export
callback_early_stopping <- function(monitor = "val_loss", patience = 10,
                                    min_delta = 0, restore_best = TRUE,
                                    start = NULL, start_epoch = NULL) {
  if (!is.null(start) && !is.null(start_epoch)) {
    stop("callback_early_stopping() takes `start` or `start_epoch`, not both: `start` ",
         "is a fraction of the run and `start_epoch` is an epoch number.", call. = FALSE)
  }
  compact(list(name = "early_stopping", monitor = monitor, patience = int1(patience),
               min_delta = min_delta, restore_best = restore_best, start = start,
               start_epoch = if (is.null(start_epoch)) NULL else int1(start_epoch)))
}

#' @rdname callbacks
#' @export
callback_model_checkpoint <- function(path, monitor = "val_loss",
                                      save_best_only = TRUE, when = NULL) {
  named <- !is.null(when) && is.list(when) && !is.null(names(when)) &&
    !anyNA(names(when)) && all(nzchar(names(when)))
  if (!is.null(when) && !named) {
    stop("`when` is a named list of thresholds, as in ",
         "`when = list(val_dice = 0.9, val_loss = 0.2)`: the names say which quantity ",
         "and the values say how good it has to be.", call. = FALSE)
  }
  compact(list(name = "model_checkpoint", path = path, monitor = monitor,
               save_best_only = save_best_only, when = when))
}

#' @rdname callbacks
#' @export
callback_reduce_lr_on_plateau <- function(monitor = "val_loss", factor = 0.1,
                                          patience = 5, min_lr = 0) {
  list(name = "reduce_lr_on_plateau", monitor = monitor, factor = factor,
       patience = int1(patience), min_lr = min_lr)
}

#' Average the weights over the last part of the run
#'
#' Stochastic weight averaging. Past `start`, every epoch's weights are folded into a running
#' average and at the end that average becomes the model - the claim being that a point in
#' the middle of a flat region generalises better than whichever corner the last epoch
#' stopped in.
#'
#' @details
#' **What it is worth is not what a table of scores shows.** Three seeds, 60 epochs, lesions
#' with ambiguous edges:
#'
#' | run | Dice | volume bias | volume \|error\| |
#' |---|---|---|---|
#' | plain | 0.9639 ±0.0100 | +1.71% ±12.18% | 12.60% ±4.19% |
#' | `callback_swa()` | 0.9667 ±0.0087 | +2.08% ±2.15% | 12.38% ±4.31% |
#'
#' Dice does not move and neither does the per-case error - both are inside the seed noise.
#' What moves is **reproducibility**: the plain runs' volume bias was +4.5%, +12.2% and
#' -11.6% across three seeds, and with averaging -0.1%, +4.2% and +2.1%. A spread 5.7 times
#' tighter, improving on all three seeds when paired, by 7.34% at 4.9 standard errors.
#'
#' So read it as *"the same model twice"* rather than *"a better model"* - which is what
#' averaging is for, and the reason it belongs beside [mask_volume()] in any argument about
#' whether a measured volume can be compared across runs.
#'
#' **Batch-normalisation statistics are recomputed afterwards**, by a pass over the training
#' data. They have to be: an averaged weight tensor inherits the statistics of whichever
#' epoch was last rather than averaging them, so without the pass the model is evaluated
#' under the wrong normalisation and scores far worse than it should with nothing to say why.
#' Models here have batch normalisation on by default, so this is nearly every run.
#'
#' @param start,start_epoch When averaging begins - **one of the two and never both**.
#'   `start` is the fraction of the run after which it begins, 0.75 folding the last
#'   quarter, and unset uses the engine's default of 0.75; `start_epoch` says the same
#'   thing as an epoch number. A fraction survives a change to `epochs` and an epoch count
#'   does not, which is why the fraction is the default; an epoch is the one to use when
#'   the point is a property of the optimisation rather than of the run's length. The
#'   final epoch is always folded, so `start = 1` averages one set of weights rather than
#'   none. `callback_early_stopping()` names the same pair with the same two words.
#' @param learning_rate Hold the rate at this value once averaging begins. Unset leaves
#'   whatever the run was doing.
#'
#'   Worth setting, and the reason is the whole mechanism: averaging is only worth something
#'   while the weights are still moving, and a rate that has decayed towards zero produces a
#'   set of nearly identical snapshots whose average is the last one. For the same reason a
#'   run cannot ask for this and [callback_cosine_annealing()] at once - the two undo each
#'   other and the specification refuses the pair.
#' @return A callback specification, to be passed to a model constructor.
#' @seealso [callbacks] for the others, [mask_volume()] for reading a volume in millilitres.
#' @export
#' @examples
#' callback_swa()
#' callback_swa(start = 0.5, learning_rate = 1e-3)
callback_swa <- function(start = NULL, learning_rate = NULL, start_epoch = NULL) {
  if (!is.null(start) && !is.null(start_epoch)) {
    stop("callback_swa() takes `start` or `start_epoch`, not both: `start` is a fraction ",
         "of the run and `start_epoch` is an epoch number.", call. = FALSE)
  }
  if (!is.null(start) && (!is.numeric(start) || length(start) != 1L || is.na(start) ||
                            start <= 0 || start > 1)) {
    stop("`start` is one number above 0 and at most 1 - the fraction of the run after ",
         "which averaging begins.", call. = FALSE)
  }
  if (!is.null(learning_rate) && (!is.numeric(learning_rate) ||
                                    length(learning_rate) != 1L ||
                                    is.na(learning_rate) || learning_rate <= 0)) {
    stop("`learning_rate` is one positive number, the rate held while averaging.",
         call. = FALSE)
  }
  compact(list(name = "swa", start = start, learning_rate = learning_rate,
               start_epoch = if (is.null(start_epoch)) NULL else int1(start_epoch)))
}

#' @rdname callbacks
#' @export
callback_cosine_annealing <- function(min_lr = 0, epochs = NULL) {
  compact(list(name = "cosine_annealing", min_lr = min_lr,
               epochs = if (is.null(epochs)) NULL else int1(epochs)))
}

#' @rdname callbacks
#' @export
callback_linear_annealing <- function(min_lr = 0, epochs = NULL) {
  compact(list(name = "linear_annealing", min_lr = min_lr,
               epochs = if (is.null(epochs)) NULL else int1(epochs)))
}

#' @rdname callbacks
#' @export
callback_step_decay <- function(factor = 0.1, every = NULL, milestones = NULL,
                                min_lr = 0) {
  # Refused here as well as in the engine, because this one is cheap to get wrong and the
  # message is better from the side the call was written on. The engine refuses it too -
  # a YAML specification reaches the validator without passing through this function.
  if (is.null(every) == is.null(milestones)) {
    stop("callback_step_decay() takes one of `every` and `milestones`, never both and ",
         "never neither: `every = 30` drops every thirty epochs, ",
         "`milestones = c(30, 60)` drops at those two.", call. = FALSE)
  }
  compact(list(name = "step_decay", factor = factor,
               every = if (is.null(every)) NULL else int1(every),
               milestones = if (is.null(milestones)) NULL else as.integer(milestones),
               min_lr = min_lr))
}

#' @rdname callbacks
#' @export
callback_csv_logger <- function(path) list(name = "csv_logger", path = path)

#' @rdname callbacks
#' @export
callback_stop_after <- function(hours) {
  if (!is.numeric(hours) || length(hours) != 1L || is.na(hours) || hours <= 0) {
    stop("`hours` is one positive number of hours.", call. = FALSE)
  }
  list(name = "stop_after", hours = hours)
}

#' @rdname callbacks
#' @export
callback_terminate_on_collapse <- function(floor = 1e-4, patience = 3,
                                           monitor = "val_foreground") {
  if (!is.numeric(floor) || length(floor) != 1L || is.na(floor) || floor < 0 || floor >= 1) {
    stop("`floor` is one number in [0, 1): the share of foreground below which the ",
         "prediction counts as collapsed.", call. = FALSE)
  }
  list(name = "terminate_on_collapse", floor = floor, patience = int1(patience),
       monitor = monitor)
}

#' @rdname callbacks
#' @export
callback_terminate_on_nan <- function() list(name = "terminate_on_nan")

#' An augmentation step
#'
#' Names come from the installed 'albumentations', so whatever it offers is available and
#' a misspelling is caught when the specification is built, with a suggestion.
#'
#' @param name The transform, for instance `"HorizontalFlip"`.
#' @param ... Its parameters, for instance `p = 0.5`.
#' @return An augmentation specification.
#' @export
#' @examples
#' augmentation_step("HorizontalFlip", p = 0.5)
augmentation_step <- function(name, ...) {
  list(name = name, params = list(...))
}


#' Which augmentations are available
#'
#' The transforms the installed 'albumentations' offers, and - for volumes - the ones it can
#' actually apply to them.
#'
#' Worth asking rather than guessing. Support for volumes is uneven: most geometric transforms
#' work and several intensity ones raise from inside the library, so `rank = 3` returns a
#' shorter list than `rank = 2`. A transform outside it is refused when the specification is
#' built, by name, rather than failing an hour into training.
#'
#' The number of names at `rank = 2` is a property of the installed 'albumentations'. **The
#' number at `rank = 3` is not, and is deliberately not written down here.** The engine finds
#' that list by offering each transform a probe volume, and some of what it refuses fails for
#' the probe's reasons rather than the library's: a group of transforms want three channels
#' where the probe has one, and another group want a target - reference image, bounding box,
#' metadata of their own - that a probe cannot supply and a specification cannot name either.
#'
#' A third group used to fail on the probe's *size*, which engine 0.8.0a10 fixed by retrying a
#' refusal at a larger probe before believing it. That is also where a long-standing
#' superstition went: the count used to vary between machines and was attributed to them, when
#' the cause was one transform randomising its own parameters, so the same machine gave two
#' answers. Escalating removed it. The count is still not promised, because it belongs to the
#' installed library rather than to this package.
#'
#' The check that decides your run is made when the specification is built, against your own
#' shape and parameters.
#'
#' @param rank 2 for images, 3 for volumes.
#' @param pattern Optional regular expression to filter the names, for browsing: `"Flip"`,
#'   `"3D$"`, `"Elastic|Grid"`.
#' @return A character vector of transform names.
#' @seealso [augmentation_step()], which uses one.
#' @examples
#' \dontrun{
#' available_transforms()                       # everything, for images
#' #> 118 names, with albumentations 2.0.8
#'
#' available_transforms(rank = 3)               # what volumes can take: fewer
#'
#' available_transforms(rank = 3, pattern = "Flip|Crop")
#' #> [1] "AtLeastOneBBoxRandomCrop" "CenterCrop"   "CenterCrop3D"
#' #> [4] "CropAndPad"   "CropNonEmptyMaskIfExists"  "HorizontalFlip"
#' #> [7] "RandomCrop"   "RandomCrop3D"              "RandomCropFromBorders"
#' #> [10] "RandomResizedCrop"  "RandomSizedBBoxSafeCrop"  "RandomSizedCrop"
#' #> [13] "VerticalFlip"
#'
#' # Which ones a volume cannot take, by name rather than by count.
#' head(setdiff(available_transforms(), available_transforms(rank = 3)), 3)
#' #> [1] "AdditiveNoise"      "BBoxSafeRandomCrop" "ChannelDropout"
#' }
#' @export
available_transforms <- function(rank = 2, pattern = NULL) {
  if (!rank %in% c(2, 3)) {
    stop("`rank` is 2 for images or 3 for volumes.", call. = FALSE)
  }
  result <- shim()$transform_names(rank = as.integer(rank))
  if (!isTRUE(result$ok)) abort_engine(result)

  names <- unlist(result$transforms)
  if (!is.null(pattern)) names <- grep(pattern, names, value = TRUE)
  names
}


#' What this package can do, asked of the package
#'
#' Six listings beside [available_transforms()] and [available_weights()]: the losses, the
#' metrics, the architectures, the optimisers, the callbacks and the tasks. Three columns -
#' the name you write in a specification, the arguments you may tune, and what it is for.
#'
#' Worth having because the alternative is leaving R for a website. The number of named
#' components grows with every release, and these are read from the engine's own schema, so a
#' loss added there appears here with nothing in this package edited. Nothing is maintained by
#' hand; a list maintained by hand is a list that will be wrong.
#'
#' `description` is the component's summary line. The rest of what the engine knows about it -
#' including the measurements, where there are any - is on the configuration reference of the
#' engine's own site, which is generated from the same text.
#'
#' @section Detection chooses fewer things, and says so:
#'
#' A detection specification chooses no loss component and no metrics at all. Its objective is
#' fixed, with `box_loss` on the model picking the box term, and every detection run reports
#' the same set - `map_50`, `map_50_95`, `mean_matched_iou` - which comes out of the run rather
#' than going into the specification.
#'
#' So `available_losses("object_detection")` and `available_metrics("object_detection")` raise
#' a condition whose message says that, rather than returning a table with no rows. An empty
#' table reads as "there are none", which is a different and wrong answer.
#'
#' @param task `"semantic_segmentation"`, `"instance_segmentation"` or
#'   `"object_detection"`. Which components a specification may name depends on what it is
#'   asking for, and for losses it genuinely differs: the three regression losses are listed
#'   only at the instance task, which is the only one with a target for them. No count is
#'   written here on purpose - the counts are asserted in the test suite against the pinned
#'   engine, which is where a number nobody can re-measure from a help page belongs. This
#'   parameter listed two tasks until the pin moved to `0.8.0a22`; the third arrived in the
#'   engine's `0.8.0a20`.
#' @return A data frame with `name`, `arguments` and `description`. `arguments` is a single
#'   string per row, comma-separated, because a column of vectors prints as something nobody
#'   can read; `strsplit(x, ", ")` takes it apart.
#'
#'   Two listings carry one column more, and it is the column they are asked for:
#'   `available_decodings()` has `needs`, the separation a decoding requires - empty where it
#'   requires none, which is `connected_components` and is why that one is always available -
#'   and `available_separations()` has `head_channels`, how wide a head that target makes.
#'   Taken from the engine's own rows rather than named on this side, so a listing that grows
#'   a field arrives here without R changing.
#' @seealso [available_transforms()] and [available_weights()], the two that came first,
#'   [separations] and [decodings] for the constructors these two listings name, and
#'   [platypus_spec()], where all of them are written.
#' @examples
#' \dontrun{
#' available_losses()
#' #>            name                    arguments
#' #> 1      boundary               region, alpha
#' #> 2           cce             label_smoothing
#' #> 3      cce_dice          cce_weight, smooth
#' #> ...
#'
#' # Which metrics take an argument at all, and which do not.
#' available_metrics()[, c("name", "arguments")]
#'
#' # The entry point, for somebody who has read nothing yet.
#' available_tasks()
#'
#' # The two instance axes: what a model can predict, and how those channels become objects.
#' available_separations()[, c("name", "head_channels")]
#' available_decodings()[, c("name", "needs")]
#'
#' # Detection says what it has instead of a loss to choose.
#' try(available_losses("object_detection"))
#' }
#' @name available_components
NULL

component_listing <- function(kind, task = NULL) {
  result <- if (is.null(task)) {
    shim()$component_listing(kind)
  } else {
    shim()$component_listing(kind, task = task)
  }
  if (!isTRUE(result$ok)) abort_engine(result)

  # The three every listing has, then whatever that listing adds - `needs` for a decoding,
  # `head_channels` for a separation. Taken from the rows rather than listed here, because a
  # column named on this side is a second place to update and the engine is the one that
  # knows what a listing contains.
  shared <- c("name", "arguments", "description")
  columns <- unique(unlist(lapply(result$rows, names)))
  columns <- c(intersect(shared, columns), setdiff(columns, shared))
  rows <- lapply(result$rows, function(row) {
    data.frame(row[columns], stringsAsFactors = FALSE)
  })
  if (!length(rows)) {
    return(data.frame(
      name = character(), arguments = character(), description = character(),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows)
}

#' @rdname available_components
#' @export
available_losses <- function(task = "semantic_segmentation") {
  component_listing("losses", task)
}

#' @rdname available_components
#' @export
available_metrics <- function(task = "semantic_segmentation") {
  component_listing("metrics", task)
}

#' @rdname available_components
#' @export
available_models <- function(task = "semantic_segmentation") {
  component_listing("models", task)
}

#' @rdname available_components
#' @export
available_optimizers <- function() {
  component_listing("optimizers")
}

#' @rdname available_components
#' @export
available_callbacks <- function() {
  component_listing("callbacks")
}

#' @rdname available_components
#' @export
available_tasks <- function() {
  component_listing("tasks")
}

#' @rdname available_components
#' @export
available_separations <- function() {
  component_listing("separations")
}

#' @rdname available_components
#' @export
available_decodings <- function() {
  component_listing("decodings")
}
