# Turning the engine's complaints into R conditions.
#
# The audience is someone who knows their data and their question, and does not know or
# care that any of this is Python. A traceback tells them nothing; "models[1]$loss: no
# such loss 'focaal', did you mean 'focal'?" tells them everything.
#
# pyplatypus reports its problems as plain data for exactly this reason, and the shim
# hands that data over intact rather than letting reticulate flatten it into a string.

#' Turn the engine's problem report into an R condition and raise it
#'
#' @param failure The list returned by the shim when `ok` is `FALSE`.
#' @param call The call to blame, for the traceback.
#' @keywords internal
#' @noRd
abort_engine <- function(failure, call = sys.call(-1)) {
  problems <- failure$problems %||% list()

  lines <- vapply(problems, function(p) {
    where <- p$where %||% "(top level)"
    text <- paste0("  * ", r_path(where), ": ", p$problem %||% "invalid")
    # `got` earns its place when it is the offending value - `2.0`, `'focaal'`. When the
    # problem is with a whole model, the offending value is the whole model, and echoing
    # a truncated dump of it back at the reader helps nobody.
    if (!is.null(p$got) && nchar(p$got) <= 60) {
      text <- paste0(text, " (got ", p$got, ")")
    }
    text
  }, character(1))

  headline <- if (length(problems) == 1L) {
    "The specification has a problem:"
  } else if (length(problems) > 1L) {
    paste0("The specification has ", length(problems), " problems:")
  } else {
    failure$message %||% "The engine rejected the specification."
  }

  message <- if (length(lines)) paste(c(headline, lines), collapse = "\n") else headline

  stop(structure(
    class = condition_classes(failure$kind),
    list(message = message, call = call,
         problems = problems_frame(problems), source = failure$source)
  ))
}

#' The class vector for one engine `kind`
#'
#' Separate from `abort_engine()` so it can be asked a question without raising anything,
#' which is what `tests/testthat/test-conditions.R` does for every kind the engine has.
#'
#' Two things it fixes, both found by writing the documentation rather than by reading it.
#' The engine's base class reports `kind = "platypus_error"`, so pasting the prefix on gave
#' `platypus_platypus_error` - a class name in nobody's documentation and nobody's
#' `tryCatch()`. And a failure with no `kind` at all produced `platypus_error` twice in one
#' vector: harmless to `inherits()`, and still a class vector that says the same thing twice.
#'
#' @param kind The engine's `kind`, or `NULL` when the shim sent none.
#' @return Character: the specific class, then `platypus_error`, `error`, `condition`.
#' @keywords internal
#' @noRd
condition_classes <- function(kind) {
  kind <- kind %||% "error"
  specific <- if (startsWith(kind, "platypus_")) kind else paste0("platypus_", kind)
  unique(c(specific, "platypus_error", "error", "condition"))
}

#' Rewrite a Python path so it reads like the R that produced it
#'
#' `models[0].loss` is where pydantic found the problem, but the user wrote
#' `models = list(u_net(...))`, so `models[1]$loss` is where they should look. Zero-based
#' indices in an R error message are a small cruelty.
#' @keywords internal
#' @noRd
r_path <- function(where) {
  if (!is.character(where) || !nzchar(where)) return("(top level)")
  bumped <- gsub("\\[([0-9]+)\\]", "\u0001\\1\u0002", where)
  repeat {
    m <- regmatches(bumped, regexpr("\u0001[0-9]+\u0002", bumped))
    if (!length(m) || !nzchar(m)) break
    n <- as.integer(gsub("[\u0001\u0002]", "", m))
    bumped <- sub("\u0001[0-9]+\u0002", paste0("[[", n + 1L, "]]"), bumped)
  }
  gsub("\\.", "$", bumped)
}

#' The problems as a data frame, for anyone who wants to work with them
#' @keywords internal
#' @noRd
problems_frame <- function(problems) {
  if (!length(problems)) {
    return(data.frame(where = character(), problem = character(),
                      got = character(), stringsAsFactors = FALSE))
  }
  data.frame(
    where = vapply(problems, function(p) r_path(p$where %||% ""), character(1)),
    problem = vapply(problems, function(p) p$problem %||% NA_character_, character(1)),
    got = vapply(problems, function(p) p$got %||% NA_character_, character(1)),
    stringsAsFactors = FALSE
  )
}

`%||%` <- function(x, y) if (is.null(x)) y else x


#' When something is wrong: the conditions this package raises
#'
#' Every failure that comes back from the engine is raised as a **classed condition**, so a
#' script can tell one kind of problem from another instead of matching on the message.
#' Until now that was true and undocumented, which made it true and useless.
#'
#' @section What the class vector looks like:
#' Three or four entries, outermost first:
#'
#' ```
#' platypus_config_error    the specific kind
#' platypus_error           every failure from this package, which is the one to catch
#' error                    an ordinary R error
#' condition
#' ```
#'
#' So `tryCatch(..., platypus_error = )` catches everything this package raises and nothing
#' else, and a specific class narrows it. `platypus_error` appears once even when the engine
#' sends no kind at all.
#'
#' @section What to catch:
#' **`platypus_error`**, unless there is a reason not to. The specific kinds come from the
#' engine, so the list below belongs to the version this package pins, and a later engine may
#' add one. Catching the base class is the thing that keeps working.
#'
#' Two are worth naming on purpose:
#'
#' \describe{
#'   \item{`platypus_config_error`}{A specification that does not describe a runnable
#'     experiment. This one carries **data**: `conditionCall()` aside, the condition has a
#'     `problems` data frame with one row per problem - `where`, `problem` and, when it is
#'     short enough to be useful, `got` - and a `source` naming the YAML file if it came from
#'     one. The engine reports every problem it found rather than the first, so the frame is
#'     what makes "three things are wrong" readable.}
#'   \item{`platypus_training_stopped`}{Not a defect. A callback ended the run early, which
#'     is what it was asked to do, and anything scoring the result afterwards should treat it
#'     as a finished run rather than a failure.}
#' }
#'
#' @section The kinds the pinned engine can send:
#' One class per kind, prefixed. `tests/testthat/test-conditions.R` holds this list to what
#' the engine actually defines, so a kind added upstream fails here rather than arriving
#' undocumented.
#'
#' ```
#' platypus_config_error            a specification that cannot be run
#' platypus_engine_error            the engine could not do what the specification asked
#' platypus_model_error             the architecture could not be built as described
#' platypus_data_error              the dataset on disk is not what the specification says
#' platypus_image_error             an image could not be read, or is not the shape claimed
#' platypus_mask_error              a mask does not match its colormap
#' platypus_channel_error           one channel per file, and the files do not agree
#' platypus_volume_error            a volume, its orientation or its spacing
#' platypus_measure_error          a measurement whose spacing does not fit the array
#' platypus_dicom_error             a DICOM file or series
#' platypus_augmentation_error      a transform that cannot do what was asked of it
#' platypus_detection_error         detection metrics
#' platypus_detection_data_error    annotations, boxes or classes
#' platypus_instance_error          a separation target, or decoding one into objects
#' platypus_instance_data_error     the per-object mask files a case has, or has not
#' platypus_weights_error           weights that do not belong to this model
#' platypus_training_stopped        a callback ended the run early
#' platypus_unknown_case            a case or model name that is not in this run
#' ```
#'
#' `platypus_unknown_case` is the one with no class behind it in the engine: the R bridge
#' raises it itself, because asking for a case that does not exist is a question the bridge
#' can answer without troubling Python.
#'
#' @section Why R has more of these than Python does:
#' The engine exports three exception classes - `PlatypusError`, `ConfigError`,
#' `WeightsError` - and raises the other twelve internally, so a Python caller catches
#' `PlatypusError` and inspects it. R derives its class from the `kind` the engine sends with
#' every failure, so all of them arrive as catchable names. That is a wider surface on this
#' side, and deliberately so: R has no exception hierarchy to lean on, and `inherits()` is
#' cheaper than parsing a message.
#'
#' @seealso [platypus_status()], for when the problem is that the engine never started.
#' @name platypus_conditions
#' @examples
#' # A specification with two problems, caught and read as data rather than as text.
#' \dontrun{
#' spec <- platypus_spec(
#'   data = segmentation_data("train", "valid", colormap = binary_colormap),
#'   models = list(u_net("m", input_shape = c(64, 64), loss = "focaal"))
#' )
#'
#' tryCatch(
#'   platypus_fit(spec),
#'   platypus_config_error = function(e) {
#'     print(e$problems)        # one row per problem: where, problem, got
#'     invisible(NULL)
#'   },
#'   platypus_error = function(e) {
#'     message("something else went wrong: ", conditionMessage(e))
#'   }
#' )
#' }
NULL
