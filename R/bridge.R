# The bridge to the engine.
#
# Everything this package does eventually happens in Python. The point of this file is
# that a user never has to know that: no interpreter to choose, no environment to
# activate, no version to match. reticulate::py_require() declares what is needed and uv
# builds an isolated environment for it on first use.
#
# That isolation is the whole design. The R keras and tensorflow packages of 2020 shared
# one Python installation with whatever else the user had, so an unrelated change on the
# Python side could break an R session. Nothing here touches a Python anyone else uses.

#' The exact engine this version of platypus speaks to
#'
#' Pinned rather than ranged on purpose: pyplatypus is an alpha whose API still moves,
#' and an R package should not break because a Python dependency drifted underneath it.
#' @keywords internal
#' @noRd
pyplatypus_version <- "0.8.0a49"

#' What this session will ask for. Set by [platypus_use_torch()] before the engine starts.
#' @keywords internal
#' @noRd
.platypus_requirement <- local({
  extra <- NULL
  function(set) {
    if (!missing(set)) extra <<- set

    # Development escape hatch. The pin is deliberate - it stops an R release breaking
    # because the engine drifted underneath it - but it also means work on the two sides
    # cannot meet until the Python half is published. Pointing this at a source tree lets
    # them meet during development, and is never used by anyone installing the package.
    local_engine <- Sys.getenv("PLATYPUS_ENGINE_PATH", unset = "")
    if (nzchar(local_engine)) {
      # With the same extras as the published route, below. Without them the development
      # route is not the installed route: it was a bare path until writing the blood-cell
      # vignette, and that vignette could not be precomputed at all because
      # `weights = "bccd-yolo3"` found no huggingface_hub. A development escape hatch that
      # differs from the real path hides exactly the class of problem it should surface,
      # which is the same reason CI builds the vignettes rather than skipping them.
      return(sprintf("%s[%s]", normalizePath(local_engine, mustWork = TRUE),
                     paste(c(extra, c("hub", "encoders")), collapse = ",")))
    }

    # `hub` and `encoders` are always asked for, although both are optional in the Python
    # package. They are optional there because most runs never fetch published weights or
    # name a backbone, and an air-gapped install cannot do the first at all. From R the
    # environment is built by this package, and leaving either out means a documented
    # feature that cannot work for anybody.
    #
    # That was not hypothetical for `hub`: `weights = "dsbowl-unet"` was unusable from R in
    # every release that had it, and nothing in either test suite could see it, because the
    # pin's test surface is the package and never its extras. The only thing that found it
    # was writing the documentation as a user would run it.
    #
    # The cost is measured rather than assumed. `hub` adds huggingface_hub, 0.8 MB.
    # `encoders` adds timm and torchvision, 10.3 MB together - against torch's own 555 MB
    # wheel, and several gigabytes once its CUDA libraries arrive. Under 2% of torch alone,
    # which is not a trade worth making someone opt into.
    #
    # Nothing here reaches the network at import. Installing needs one connection; after
    # that the cache serves everything, and only fetching weights by name needs a network
    # again.
    always <- c("hub", "encoders")
    extras <- paste(c(extra, always), collapse = ",")
    sprintf("pyplatypus[%s]==%s", extras, pyplatypus_version)
  }
})

# Holds the imported module. Populated lazily, so loading this package costs nothing.
.platypus <- new.env(parent = emptyenv())

#' Complain about RETICULATE_PYTHON before it complains about us
#'
#' It overrides py_require() completely, so a stale value turns every function in this
#' package into an unreadable failure somewhere inside reticulate. This was not
#' hypothetical: the author's own machine carried a RETICULATE_PYTHON pointing at an
#' Anaconda deleted years earlier, and it broke the first run of the prototype.
#' @keywords internal
#' @noRd
check_reticulate_python <- function() {
  value <- Sys.getenv("RETICULATE_PYTHON", unset = NA_character_)
  if (is.na(value) || !nzchar(value)) {
    return(invisible(NULL))
  }
  if (!file.exists(value)) {
    packageStartupMessage(
      "platypus: RETICULATE_PYTHON points at '", value, "', which does not exist.\n",
      "  That setting overrides the isolated environment this package manages, so ",
      "nothing here will work\n  until it is removed. Look in ~/.Renviron and ~/.bashrc, ",
      "then restart R."
    )
  } else {
    packageStartupMessage(
      "platypus: RETICULATE_PYTHON is set to '", value, "'.\n",
      "  That Python will be used instead of the isolated environment this package ",
      "manages, so it must\n  have pyplatypus installed. Unset it to let platypus ",
      "handle this itself."
    )
  }
  invisible(NULL)
}

#' Explain a failure to start the engine
#'
#' Separated from the handler so it can be tested without breaking a Python installation.
#'
#' One case deserves its own paragraph. uv caches what an index told it, so for a while
#' after a new pyplatypus is published uv still believes the version this package pins
#' does not exist - and says so in a way that sounds permanent: "no version of
#' pyplatypus==x". Anyone who updates platypus the day a release goes out can meet it, and
#' nothing in the message hints that the fix is local and takes a second.
#' @keywords internal
#' @noRd
engine_start_failure <- function(message) {
  stale_index <- grepl("no version of pyplatypus", message, fixed = TRUE) ||
    grepl("No solution found when resolving", message, fixed = TRUE)

  out <- paste0(
    "platypus could not start its Python engine.\n",
    "  ", message, "\n\n"
  )
  if (stale_index) {
    paste0(
      out,
      "  ", .platypus_requirement(), " does exist. uv is answering from a cached copy of ",
      "the package\n  index, which happens for a while after a release.\n\n",
      "  Clear the index cache - not the whole cache, which would throw away the multi-",
      "gigabyte\n  PyTorch download along with it:\n\n",
      "    rm -rf \"$(uv cache dir)\"/simple-v*\n\n",
      "  `uv cache clean pyplatypus` is not enough: it removes that package's built ",
      "artifacts\n  and leaves the index response that says the version does not exist.\n"
    )
  } else {
    paste0(
      out,
      "  The first call needs to download ", .platypus_requirement(), " and PyTorch, ",
      "which needs a network\n  connection once. After that it is cached and works ",
      "offline. See `?platypus_status`.\n"
    )
  }
}

#' Which PyTorch build this session should ask for, before anything starts Python
#'
#' `py_require()` is session state, so the choice made by [platypus_use_torch()] does not
#' survive a restart - and on a card older than Turing, forgetting it costs about ten
#' times the training time without costing an error. This reads the choice from an option
#' or an environment variable so it can be made once, in `~/.Rprofile` or `~/.Renviron`.
#'
#' The option wins over the variable: a session can override what a machine was configured
#' with, and not the other way round. An unrecognised value is reported and ignored rather
#' than raising, because a bad line in a startup file must not make the package
#' unloadable.
#' @keywords internal
#' @noRd
torch_build_requested <- function() {
  value <- getOption("rplatypus.torch", default = NULL)
  if (is.null(value)) {
    value <- Sys.getenv("PLATYPUS_TORCH", unset = "")
  }
  if (!is.character(value) || length(value) != 1L || !nzchar(value)) {
    return(NULL)
  }
  if (!value %in% c("pascal", "default")) {
    packageStartupMessage(
      "platypus: ignoring a torch build called '", value, "'.\n",
      "  `rplatypus.torch` and PLATYPUS_TORCH take \"pascal\" - the last build against ",
      "CUDA 12, for a\n  GTX 10-series card or older - or \"default\"."
    )
    return(NULL)
  }
  if (identical(value, "default")) NULL else value
}

#' Say so when the engine that answered is not the one this release was built against
#'
#' The pin is the mechanism rather than caution: an R release cannot break because the
#' engine drifted underneath it. On the one route where that does not hold - a
#' `RETICULATE_PYTHON` pointing at somebody's own environment - nothing used to compare
#' the two, so a mismatch arrived as a validator refusing a configuration field by name,
#' which tells a reader nothing about their interpreter.
#'
#' A warning rather than a refusal: the only way to reach this state is to have gone out
#' of one's way, and refusing would also break somebody deliberately testing an engine
#' they built. The message names both versions, which is what makes it actionable.
#'
#' `PLATYPUS_ENGINE_PATH` is exempt: that route asks for a source tree with no version at
#' all, and is this package's own documented way of meeting an unpublished engine.
#' @keywords internal
#' @noRd
check_engine_version <- function() {
  if (nzchar(Sys.getenv("PLATYPUS_ENGINE_PATH", unset = ""))) {
    return(invisible(NULL))
  }
  theirs <- tryCatch(.platypus$engine[["__version__"]], error = function(e) NULL)
  if (is.null(theirs) || identical(theirs, pyplatypus_version)) {
    return(invisible(NULL))
  }
  warning(
    "platypus: this package pins pyplatypus ", pyplatypus_version,
    " and the engine that answered is ", theirs, ".\n",
    "  The pin is what keeps an R release from breaking when the engine moves, and it is ",
    "not in force here.\n  A configuration this package sends may be refused by name, or ",
    "quietly mean something else.\n  RETICULATE_PYTHON is the usual cause; unset it to let ",
    "platypus manage the environment itself.",
    call. = FALSE
  )
  invisible(NULL)
}

.onLoad <- function(libname, pkgname) {
  check_reticulate_python()
  # Before `py_require()`, because the requirement is built from it and nothing after this
  # point can change what the environment will be without a restart.
  requested <- torch_build_requested()
  if (!is.null(requested)) .platypus_requirement(requested)
  reticulate::py_require(.platypus_requirement())

  .platypus$engine <- reticulate::import(
    "pyplatypus",
    delay_load = list(
      # Nothing is downloaded until a function actually needs Python, so library(rplatypus)
      # stays instant and works offline.
      # Fires when something first needs Python, which is the earliest moment the
      # engine's own version can be asked for.
      on_load = function() {
        check_engine_version()
      },
      on_error = function(e) {
        stop(engine_start_failure(conditionMessage(e)), call. = FALSE)
      }
    )
  )
  invisible(NULL)
}

#' The Python engine, imported on first use
#' @keywords internal
#' @noRd
engine <- function() {
  .platypus$engine
}

#' The R-facing shim
#'
#' A small Python module shipped with this package. It exists because exceptions do not
#' survive the crossing usefully - reticulate hands R the message and drops the object -
#' so everything it does returns data instead of raising. See inst/python.
#' @keywords internal
#' @noRd
shim <- function() {
  if (is.null(.platypus$shim)) {
    .platypus$shim <- reticulate::import_from_path(
      "platypus_shim",
      path = system.file("python", package = "rplatypus", mustWork = TRUE)
    )
  }
  .platypus$shim
}

#' Is the engine ready?
#'
#' Reports whether the Python side has been started, and what it is. Calling this does
#' not start it - use it to check before a long run, or when something is wrong.
#'
#' @section Updating this package:
#'
#' **Nothing to do.** Each release of this package pins one exact engine version, that
#' pin is what gets declared when the package loads, and the environment is resolved from
#' it on first use. Install a newer `rplatypus` and the next session uses the engine it
#' asks for; the first call after the upgrade fetches the new engine - a few hundred
#' kilobytes, with PyTorch already cached - and the environment the old version used is
#' left alone, so going back to it costs nothing either.
#'
#' That is the opposite of the arrangement most R packages wrapping Python have, where a
#' persistent environment is installed once by hand and updating the R package does not
#' touch it. Here there is no environment anybody maintains: there is a pin, and the
#' environment always matches it. The cost is that the two cannot be moved separately -
#' which is the point, since a release that could drift from its engine is the failure
#' the pin exists to prevent.
#'
#' One case is worth knowing: updating **on the day the engine is published**, uv may
#' still be serving a cached index listing and report that the pinned version does not
#' exist. It is a stale read rather than a missing release, it mends itself, and the
#' failure message says so.
#'
#' If `RETICULATE_PYTHON` is set, none of this applies - that Python is used whatever the
#' pin says, and a mismatch is reported as a warning naming both versions.
#'
#' @return A list with the engine version, the interpreter in use and where its
#'   environment lives, or `NULL` fields when Python has not been started yet.
#'
#' @section Why this page shows no output:
#' What this prints is a property of the machine it runs on, so an example output here
#' would describe whichever machine built this page rather than yours. Run it and read
#' your own.
#'
#' @export
#' @examples
#' \dontrun{
#' platypus_status()
#' }
platypus_status <- function() {
  started <- reticulate::py_available(initialize = FALSE)
  out <- list(
    requirement = .platypus_requirement(),
    started = started,
    reticulate = as.character(utils::packageVersion("reticulate")),
    reticulate_python = Sys.getenv("RETICULATE_PYTHON", unset = NA_character_)
  )
  if (started) {
    config <- reticulate::py_config()
    out$python <- config$python
    out$python_version <- as.character(config$version)
    out$environment <- config$virtualenv
    out$engine_version <- tryCatch(engine()$`__version__`, error = function(e) NA_character_)
  }
  structure(out, class = "platypus_status")
}

#' @export
print.platypus_status <- function(x, ...) {
  cat("platypus engine\n")
  cat("  requires    :", x$requirement, "\n")
  cat("  started     :", if (isTRUE(x$started)) "yes" else "no (starts on first use)", "\n")
  if (isTRUE(x$started)) {
    cat("  version     :", x$engine_version, "\n")
    cat("  python      :", x$python, paste0("(", x$python_version, ")"), "\n")
    cat("  environment :", x$environment, "\n")
  }
  if (!is.na(x$reticulate_python)) {
    cat("  note        : RETICULATE_PYTHON is set, overriding the managed environment\n")
  }
  invisible(x)
}


#' Ask for a particular PyTorch build
#'
#' Call this before anything starts the engine - straight after `library(rplatypus)` - and
#' before the first call that needs Python.
#'
#' There is one reason to: **a GeForce GTX 10-series card, or anything older**. PyTorch
#' 2.8 and later ship CUDA 13 builds, and CUDA 13 dropped the Maxwell, Pascal and Volta
#' generations outright. No driver update brings them back. Without this, such a card is
#' simply not used and everything runs on the processor, perhaps ten times slower, with
#' nothing obviously wrong.
#'
#' On anything from Turing - the RTX 20-series onwards - the default is correct and this
#' is unnecessary.
#'
#' @section Saying it once instead of every session:
#'
#' `py_require()` is session state, so this does not survive a restart - and forgetting it
#' costs about ten times the training time without costing an error, which is the kind of
#' bill that goes unnoticed. Set it where a session starts instead:
#'
#' ```r
#' options(rplatypus.torch = "pascal")   # ~/.Rprofile
#' ```
#'
#' or `PLATYPUS_TORCH=pascal` in `~/.Renviron`, which also reaches runs that never load an
#' `.Rprofile` - `Rscript`, a scheduler, CI. The option wins over the variable, so a
#' session can override what a machine was configured with. `"default"` asks for the
#' ordinary build, which is how to turn the setting off for one session without editing
#' the file it came from.
#'
#' Both are read when the package is loaded, which is the last moment anything can change
#' what the environment will be. A value neither of them recognises is reported at load
#' and ignored: a bad line in a startup file should not make the package unloadable.
#'
#' @param build `"pascal"` for the last PyTorch built against CUDA 12, or `NULL` for the
#'   default.
#' @return The requirement string now in force, invisibly.
#'
#' @section Why this page shows no output:
#' What this prints is a property of the machine it runs on, so an example output here
#' would describe whichever machine built this page rather than yours. Run it and read
#' your own.
#'
#' @export
#' @examples
#' \dontrun{
#' library(rplatypus)
#' platypus_use_torch("pascal")   # GTX 10-series and older
#' }
platypus_use_torch <- function(build = c("pascal", "default")) {
  build <- if (is.null(build)) "default" else match.arg(build)
  if (reticulate::py_available(initialize = FALSE)) {
    stop(
      "The engine has already started, so the PyTorch build can no longer be changed.\n",
      "  Call platypus_use_torch() right after library(rplatypus), before anything that ",
      "needs Python.\n  Restart R to change it now.",
      call. = FALSE
    )
  }
  # `py_require()` accumulates by default, and .onLoad has already declared the plain
  # requirement. Asking again left *both* strings in the list, and uv refused the pair
  # because the two resolve to different torch builds - so this function could never do
  # the one thing it exists for, on exactly the machines it exists for. The previous
  # string is withdrawn before the new one is declared; `action = "set"` would do it in
  # one call and would also drop reticulate's own numpy.
  reticulate::py_require(.platypus_requirement(), action = "remove")
  .platypus_requirement(if (identical(build, "default")) NULL else build)
  reticulate::py_require(.platypus_requirement())
  invisible(.platypus_requirement())
}

#' Where the work will happen
#'
#' Reports the PyTorch build in use and the device it can see. Starts the engine if it is
#' not running.
#'
#' The answer comes from the engine's own `device_report()` since `0.8.0a38` - this
#' package used to compute it, in a file of Python it ships, where no user of the engine
#' could reach it. What stays here is the advice: the line telling you to call
#' [platypus_use_torch()] is about R's session model and would mean nothing to somebody
#' who installed the engine with pip.
#'
#' **An accelerator that is not CUDA is named**, because the published weights were all
#' trained on CUDA cards and a score from another backend is not directly comparable with
#' the registry's. Until `0.8.0a38` the engine asked about CUDA alone, so an Apple Silicon
#' Mac reported `cpu` while a working `mps` backend sat in the same installation.
#'
#' @return A list, printed readably.
#'
#' @section Why this page shows no output:
#' What this prints is a property of the machine it runs on, so an example output here
#' would describe whichever machine built this page rather than yours. Run it and read
#' your own.
#'
#' @export
#' @examples
#' \dontrun{
#' platypus_device()
#' }
platypus_device <- function() {
  structure(shim()$device_report(), class = "platypus_device")
}

#' @export
print.platypus_device <- function(x, ...) {
  cat("torch      :", x$torch, "\n")
  cat("cuda build :", x$cuda_build, "\n")
  cat("device     :", x$device, "\n")
  # Only when it is not CUDA. Every published set of weights was trained on a CUDA card,
  # so that is the unremarkable case and naming it would be noise in the line above; an
  # `mps` or `xpu` run is the one worth saying out loud, because a number from it is not
  # obviously comparable with the registry's.
  if (!is.null(x$backend) && !identical(x$backend, "cuda")) {
    cat("backend    :", x$backend, "- not CUDA, so scores are not directly\n")
    cat("             comparable with the published weights, which were trained on it\n")
  }
  if (isTRUE(x$gpu_present_but_unusable)) {
    cat("\n  This machine has a GPU that this PyTorch build cannot use, so the work will\n")
    cat("  run on the processor instead - often about ten times slower.\n")
    cat("  For a GTX 10-series card or older, restart R and call:\n")
    cat("      platypus_use_torch(\"pascal\")\n")
  }
  invisible(x)
}
