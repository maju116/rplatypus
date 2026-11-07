# Reading what a run wrote down about itself.
#
# The engine writes `<output_dir>/<model>/run.json` when - and only when - `output_dir` was
# asked for, and `pyplatypus/runs.py` says why it is the specification plus what the run
# derived rather than a summary: a summary is for reading, a specification is for running
# again. For a detector whose anchors were fitted rather than named, the record is the only
# place those anchors exist outside a weights sidecar somebody has to remember to export.
#
# **This reads it without starting Python**, which is the whole argument for it living here
# rather than going through the shim like everything else in this package. A record is an
# interchange format; a first call to the engine downloads around 5 GB, and spending that to
# parse a text file would make the format worth less than the file. The cost is a second
# implementation of a one-line reader, and the test holds R's expectations to a record the
# engine actually wrote rather than to this file's idea of one.
#
# `jsonlite` is a Suggests, asked for at call time the way `ggplot2` is in R/plot.R. Nothing
# else here needs it, and a hard dependency for one function that many users never call is
# the wrong trade.

#' Read what a run wrote down about itself
#'
#' `platypus_fit()` leaves a record beside the weights when the specification named an
#' `output_dir`: the whole specification, whatever the run worked out for itself, the
#' epoch-by-epoch history, and the version of the engine that produced it. This reads one
#' back.
#'
#' Named to match `read_record()` in the engine, and `read_images()` and `read_masks()` here.
#'
#' @section Why you would want it:
#' The specification in the record is a thing you can run again, not a description of a run.
#' And for a detector whose anchors were **fitted** rather than named, `derived$anchors` is
#' the only copy outside a weights sidecar - so a record is how a result stays reproducible
#' after the session that produced it has gone.
#'
#' @section It does not start Python:
#' Deliberately. Everything else in this package asks the engine; this reads a text file,
#' and a first call to the engine provisions an environment of several gigabytes. A record
#' you cannot read without the thing that wrote it is worth less than one you can, so this
#' needs only `jsonlite`, and works on a machine that has never had Python.
#'
#' @param path The `run.json` to read, or the directory holding it - so both
#'   `read_record("out/my_model")` and `read_record("out/my_model/run.json")` work.
#' @return A `platypus_record`: a list with `written`, `pyplatypus`, `model`,
#'   `specification`, `derived`, `history`, and the two run-level facts that sit beside the
#'   history - `weights_epoch` and `stop_reason`. Everything is plain R data, because a
#'   record describes what happened rather than being a live thing - except `history`, which
#'   comes back as a data frame with one row per epoch.
#'
#'   `weights_epoch` is the epoch the model's final weights came from, and it is `NULL` when
#'   they are not any one epoch's: an average left by [callback_ema()] or [callback_swa()],
#'   or a run that selected nothing and so ended on its last epoch, which `nrow(history)`
#'   already tells you. It is the same figure a score table reports as `best_epoch`, because
#'   both read the one place the engine records it.
#'
#'   Both keys arrived with engine `0.8.0a74`, and **a record written by an older engine
#'   carries neither** - which matters because `record$weights_epoch` is `NULL` in that case
#'   too. Measured rather than assumed: `jsonlite` gives `NULL` for a JSON `null` *and* for
#'   a key that is not there, and the two are told apart by
#'   `"weights_epoch" %in% names(record)`. So `is.null()` answers *no single epoch* and *an
#'   older engine* identically, and only the name test distinguishes them.
#'
#'   That frame is **not** quite what [training_history()] returns, and the difference is
#'   worth knowing before you `rbind()` them: a record belongs to one model, whose name is
#'   the top-level `model` field, so the frame has no `model` column. `training_history()`
#'   spans every model in the fit and needs one. Every other column is the same.
#' @seealso [training_history()] for the same numbers from a fit in the current session,
#'   and [export_weights()], whose sidecar answers a different question - what the weights
#'   are for, rather than what the run was.
#' @export
#' @examples
#' \dontrun{
#' spec <- platypus_spec(
#'   data = segmentation_data("train", "valid", colormap = binary_colormap),
#'   models = list(u_net("vessels", input_shape = c(256, 256))),
#'   output_dir = "runs"
#' )
#' fit <- platypus_fit(spec)
#'
#' record <- read_record("runs/vessels")
#' record$pyplatypus          # the engine that produced it
#' head(record$history)       # one row per epoch
#' record$specification       # enough to run it again
#' }
read_record <- function(path) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Reading a run record needs the 'jsonlite' package. Install it with ",
         "install.packages(\"jsonlite\").", call. = FALSE)
  }
  if (length(path) != 1L || !is.character(path) || is.na(path)) {
    stop("`path` is one file or directory name.", call. = FALSE)
  }

  file <- if (dir.exists(path)) file.path(path, "run.json") else path
  if (!file.exists(file)) {
    # Said in terms of what the caller did, rather than letting jsonlite report a connection
    # it could not open: the ordinary way to get here is a run whose specification never
    # named `output_dir`, in which case nothing was written and no file is missing.
    stop("No run record at ", file, ".\n",
         "A record is written only when the specification named an `output_dir`.",
         call. = FALSE)
  }

  record <- jsonlite::fromJSON(file, simplifyVector = FALSE)
  record$history <- rows_to_frame(record$history %||% list())
  structure(record, class = c("platypus_record", "list"))
}

#' @export
print.platypus_record <- function(x, ...) {
  cat("platypus run record\n")
  cat("  model       :", x$model %||% "(unnamed)", "\n")
  cat("  written     :", x$written %||% "(unrecorded)", "\n")
  cat("  engine      : pyplatypus", x$pyplatypus %||% "(unrecorded)", "\n")
  cat("  epochs      :", nrow(x$history), "\n")
  # Named rather than inferred: the epoch the weights came from is not the last epoch and
  # not the best row of the history - `pyplatypus#398` is the defect where it was read off
  # the history, and `pyplatypus#417` is why it is in the record at all.
  #
  # `%in% names()` and NOT `is.null()`, which is the measured part: jsonlite gives NULL for
  # a JSON null and for an absent key alike, so `is.null()` reads a run that selected no
  # epoch exactly like a record written before engine 0.8.0a74. Those are different facts -
  # one is an answer and the other is a record that cannot answer - and a print method that
  # showed nothing in both cases would be hiding the one a reader can act on.
  if ("weights_epoch" %in% names(x)) {
    cat("  weights from:",
        if (is.null(x$weights_epoch)) "no single epoch" else paste("epoch", x$weights_epoch),
        "\n")
  }
  if ("stop_reason" %in% names(x)) {
    cat("  stopped     :", x$stop_reason %||% "(ran to the last epoch)", "\n")
  }
  derived <- names(x$derived %||% list())
  # Named rather than counted: "2 derived" says nothing, and for a detector the one that
  # matters is `anchors`, which exists nowhere else.
  cat("  derived     :", if (length(derived)) paste(derived, collapse = ", ") else "nothing",
      "\n")
  cat("  specification: ", length(x$specification %||% list()), " top-level fields\n",
      sep = "")
  invisible(x)
}
