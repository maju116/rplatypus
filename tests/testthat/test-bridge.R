test_that("loading the package does not start Python", {
  # The reason library(rplatypus) is instant and works on a machine that has never seen
  # Python. If this ever fails, delay_load has been lost somewhere.
  #
  # In a fresh process on purpose. Asking the current session would make the answer
  # depend on whether anything else had already started the engine, so the test would
  # quietly stop meaning anything the moment another test ran first.
  skip_if_not_installed("callr")
  started <- callr::r(function() {
    library(rplatypus)
    reticulate::py_available(initialize = FALSE)
  })
  expect_false(started)
})

test_that("platypus_use_torch replaces the requirement instead of adding a second", {
  # The bug this pins: `py_require()` accumulates, .onLoad had already declared the plain
  # requirement, and asking again left both in the list. uv then refuses the pair, because
  # the two resolve to different torch builds - so the function could never do the one
  # thing it is for, and the only existing test of it asserted that it *errors* once the
  # engine has started, which is true either way.
  #
  # In a fresh process, like the test above and for the same reason: requirements are
  # session-global, so asking the current session would make this depend on what ran first.
  #
  # **The child loads whatever this run loaded, which is not the same thing as loading the
  # package.** It used to call `library(rplatypus)`, which reaches the user library - so the
  # last assertion compared the *installed* package's pin against the *source's* version and
  # failed on every pin move until somebody reinstalled, reporting it as a wrong pin. §4's
  # "installed is not source" from the inside: the two were both here, and the test read one
  # and asserted about the other. The `engine` job checks the installed route on purpose and
  # separately, which is where that question belongs.
  skip_if_not_installed("callr")
  source_tree <- normalizePath(testthat::test_path("..", ".."), mustWork = FALSE)
  loaded_from_source <- file.exists(file.path(source_tree, "DESCRIPTION"))
  asked <- callr::r(
    function(source_tree, loaded_from_source) {
      if (loaded_from_source) pkgload::load_all(source_tree, quiet = TRUE) else library(rplatypus)
      platypus_use_torch("pascal")
      grep("pyplatypus", reticulate::py_require()$packages, fixed = TRUE, value = TRUE)
    },
    args = list(source_tree, loaded_from_source)
  )
  expect_length(asked, 1)
  expect_match(asked, "pascal", fixed = TRUE)
  # Two modes, the same way `platypus_status()` below handles them, rather than one
  # assertion that is only true of the installed route. PLATYPUS_ENGINE_PATH replaces the
  # pinned name with a source tree, so asserting the pin here made §7's development
  # command - the one where the two halves meet before a release - fail by construction,
  # on a line that reads like a wrong pin. The control that found it: the same failure
  # appears with the previous pin, so it was never about which version the pin names.
  if (nzchar(Sys.getenv("PLATYPUS_ENGINE_PATH"))) {
    tree <- sub("\\[.*$", "", asked)
    expect_true(dir.exists(tree))
    expect_true(file.exists(file.path(tree, "pyproject.toml")))
  } else {
    expect_match(asked, rplatypus:::pyplatypus_version, fixed = TRUE)
  }
})

test_that("status reports the pinned engine before anything has started", {
  status <- platypus_status()
  expect_s3_class(status, "platypus_status")
  # The pinned version is what matters; the extras depend on whether
  # platypus_use_torch() has been called, which is none of this test's business.
  # PLATYPUS_ENGINE_PATH replaces the pinned name with a source tree during development -
  # but with the same extras, which is the point. Asserted as parts, for the reason in the
  # comment below: this used to check `dir.exists()` on the whole string, and that broke
  # the moment the extras arrived. What matters is that the development route asks for
  # what the installed route asks for, because a route that differs hides exactly the
  # class of problem it exists to surface.
  if (nzchar(Sys.getenv("PLATYPUS_ENGINE_PATH"))) {
    tree <- sub("\\[.*$", "", status$requirement)
    expect_true(dir.exists(tree))
    expect_true(file.exists(file.path(tree, "pyproject.toml")))
    for (extra in c("hub", "encoders")) {
      expect_match(status$requirement, extra, fixed = TRUE)
    }
  } else {
    # The extras that are always asked for, and the pinned version. Asserted as parts
    # rather than as one pattern over the whole string: the previous version of this
    # expectation was `[a-z,]*hub\]`, which quietly required `hub` to be the *last* extra
    # and failed the moment a second one was added. A pattern that encodes the order of a
    # set is describing today's implementation, not the intention.
    expect_match(status$requirement, "^pyplatypus\\[")
    for (extra in c("hub", "encoders")) {
      expect_match(status$requirement, extra, fixed = TRUE)
    }
    expect_match(
      status$requirement,
      paste0("==", rplatypus:::pyplatypus_version, "$"),
      fixed = FALSE
    )
  }
  expect_type(status$started, "logical")
})

test_that("status prints something a person can read", {
  output <- capture.output(print(platypus_status()))
  expect_true(any(grepl("platypus engine", output)))
  expect_true(any(grepl("requires", output)))
})

test_that("a broken RETICULATE_PYTHON is reported rather than left to fail later", {
  # It overrides py_require() entirely, so silence here means an unreadable failure
  # somewhere inside reticulate much later.
  withr::with_envvar(c(RETICULATE_PYTHON = "/definitely/not/a/python"), {
    expect_message(
      rplatypus:::check_reticulate_python(),
      "does not exist"
    )
  })
})

test_that("a RETICULATE_PYTHON that exists is still called out", {
  withr::with_envvar(c(RETICULATE_PYTHON = tempdir()), {
    expect_message(
      rplatypus:::check_reticulate_python(),
      "instead of the isolated environment"
    )
  })
})

test_that("an unset RETICULATE_PYTHON says nothing at all", {
  withr::with_envvar(c(RETICULATE_PYTHON = NA), {
    expect_silent(rplatypus:::check_reticulate_python())
  })
})

test_that("the engine starts and is the version this package pins", {
  skip_if_no_engine()
  status <- platypus_status()
  expect_true(status$started)
  expect_true(nzchar(status$python))
  # Compared against the constant rather than a literal, so this asserts the pin was
  # honoured instead of restating it. A source tree named by PLATYPUS_ENGINE_PATH is
  # allowed to be ahead of the pin - that is what the escape hatch is for.
  if (!nzchar(Sys.getenv("PLATYPUS_ENGINE_PATH"))) {
    expect_identical(status$engine_version, rplatypus:::pyplatypus_version)
  }
})

test_that("data crosses back from Python as ordinary R objects", {
  # The bridge is only useful if what returns is something R code can work with, rather
  # than a handle a user has to keep asking Python about.
  skip_if_no_engine()
  schema <- rplatypus:::engine()$spec_schema()
  expect_type(schema, "list")
  expect_true(grepl("spec.schema.json", schema[["$id"]], fixed = TRUE))
})

test_that("a bad specification comes back as a readable R error, not a traceback", {
  # The hardest requirement of the whole surface, and the reason the Python side reports
  # its problems as plain data. Fleshed out properly in the next step; this pins the
  # shape now so it cannot regress silently.
  skip_if_no_engine()
  broken <- list(
    task = "semantic_segmentation",
    data = list(train_path = tempdir(), validation_path = tempdir(),
                colormap = list(c(0L, 0L, 0L), c(255L, 255L, 255L))),
    models = list(list(name = "u", input_shape = c(64L, 64L),
                       loss = list(name = "focaal")))
  )
  error <- tryCatch(
    rplatypus:::engine()$from_dict(broken, check_paths = FALSE),
    error = function(e) e
  )
  expect_s3_class(error, "error")
  expect_match(conditionMessage(error), "focaal")
})

test_that("the torch build can be chosen, but only before the engine starts", {
  # A GTX 10-series card needs the CUDA 12 line, because CUDA 13 dropped Pascal. Once
  # Python is running the environment is fixed, and saying so is kinder than silently
  # doing nothing.
  skip_if_no_engine()
  expect_error(platypus_use_torch("pascal"), "already started")
})

test_that("the device report says where the work will happen", {
  skip_if_no_engine()
  device <- platypus_device()
  expect_s3_class(device, "platypus_device")
  expect_true(nzchar(device$torch))
  expect_type(device$cuda_available, "logical")
  # Since the engine's 0.8.0a38 the report also names which accelerator answered, or NULL
  # for the processor. R prints it only when it is not CUDA, but it has to arrive either
  # way or the printing has nothing to decide on.
  expect_true(is.null(device$backend) || is.character(device$backend))
})

test_that("the report is the engine's, not this package's", {
  # It used to be computed in `inst/python/platypus_shim.py`, which meant a Python user
  # could not reach any of it. The shim forwards now, so the two cannot drift - and the
  # cheapest way to see that is that the engine answers the same thing directly.
  skip_if_no_engine()
  theirs <- rplatypus:::engine()$device_report()
  ours <- platypus_device()

  expect_identical(ours$torch, theirs$torch)
  expect_identical(ours$device, theirs$device)
})

test_that("a backend that is not CUDA is named, and CUDA is not", {
  # The printing rule, tested without a machine of either kind: every published set of
  # weights was trained on CUDA, so that is the unremarkable case, and an `mps` run is the
  # one worth saying out loud because its numbers are not directly comparable.
  mps <- structure(
    list(torch = "2.7.1", cuda_build = "cpu-only build", device = "mps", backend = "mps"),
    class = "platypus_device"
  )
  cuda <- structure(
    list(torch = "2.7.1", cuda_build = "12.6", device = "A card", backend = "cuda"),
    class = "platypus_device"
  )

  expect_output(print(mps), "backend    : mps")
  expect_output(print(mps), "not directly")
  expect_silent(expect_output(print(cuda), "device     : A card"))
  expect_false(any(grepl("backend", capture.output(print(cuda)))))
})

test_that("a stale uv index cache is explained, because it sounds permanent", {
  # The real message uv produced on 2026-09-26, minutes after 0.2.0a2 was published. It
  # states that the version does not exist, which is false and not actionable; the fix is
  # one local command. Anyone who updates platypus on release day can meet this.
  uv_said <- paste(
    "Python engine failed to start:",
    "No solution found when resolving tool dependencies:",
    "Because there is no version of pyplatypus==0.2.0a2 and you require",
    "pyplatypus==0.2.0a2, we can conclude that your requirements are unsatisfiable."
  )
  explained <- rplatypus:::engine_start_failure(uv_said)
  # The advice points at the index cache, and says why the obvious command is not the one:
  # `uv cache clean pyplatypus` removes that package's built artifacts and leaves the index
  # response claiming the version does not exist. Measured on 2026-09-27 against 0.3.0a6.
  expect_match(explained, "simple-v", fixed = TRUE)
  expect_match(explained, "not enough", fixed = TRUE)
  expect_match(explained, "does exist", fixed = TRUE)
  # The download advice would be wrong here: the network is fine, the cache is not.
  expect_false(grepl("needs a network", explained, fixed = TRUE))
})

test_that("any other startup failure still gets the download advice", {
  explained <- rplatypus:::engine_start_failure("Connection refused")
  expect_match(explained, "needs a network", fixed = TRUE)
  expect_match(explained, "works offline", fixed = TRUE)
  expect_false(grepl("uv cache clean", explained, fixed = TRUE))
})

test_that("the always-on extras are asked for whatever else is", {
  # Two paths into the requirement, and both must carry every extra the R surface depends
  # on: fetching published weights and naming a backbone are both documented features, and
  # an environment built without the extra behind one cannot do it at all. `hub` shipped
  # missing once and the feature was unusable from R in every release that advertised it.
  #
  # The parts are asserted separately rather than as one literal string. A single pattern
  # restating the whole bracket has to be rewritten whenever an extra is added, which is
  # how a test stops describing an intention and starts describing an implementation - and
  # the version literal in this file already hid from a grep once for the same reason.
  always <- c("hub", "encoders")

  withr::with_envvar(c(PLATYPUS_ENGINE_PATH = NA), {
    on.exit(rplatypus:::.platypus_requirement(set = NULL), add = TRUE)

    rplatypus:::.platypus_requirement(set = NULL)
    plain <- rplatypus:::.platypus_requirement()
    expect_match(plain, "^pyplatypus\\[")
    for (extra in always) expect_match(plain, extra, fixed = TRUE)
    expect_match(plain, paste0("==", rplatypus:::pyplatypus_version), fixed = TRUE)

    rplatypus:::.platypus_requirement(set = "pascal")
    pascal <- rplatypus:::.platypus_requirement()
    # A torch build asked for explicitly comes first, so the thing the user chose is the
    # thing they see at the front of the message platypus_status() prints.
    expect_match(pascal, "^pyplatypus\\[pascal,")
    for (extra in always) expect_match(pascal, extra, fixed = TRUE)
    expect_match(pascal, paste0("==", rplatypus:::pyplatypus_version), fixed = TRUE)
  })
})

# --- the two things a session has to settle before anything starts Python --------------

test_that("the torch build can be chosen once, by option or by variable", {
  # `py_require()` is session state, so `platypus_use_torch()` does not survive a restart -
  # and on a card older than Turing, forgetting it costs about ten times the training time
  # without costing an error. None of this touches Python.
  withr::with_options(list(rplatypus.torch = "pascal"), {
    expect_identical(rplatypus:::torch_build_requested(), "pascal")
  })
  withr::with_envvar(c(PLATYPUS_TORCH = "pascal"), {
    expect_identical(rplatypus:::torch_build_requested(), "pascal")
  })
})

test_that("the option wins over the variable, and \"default\" means ask for nothing", {
  withr::with_envvar(c(PLATYPUS_TORCH = "pascal"), {
    withr::with_options(list(rplatypus.torch = "default"), {
      # A session may override what a machine was configured with, not the other way round.
      expect_null(rplatypus:::torch_build_requested())
    })
  })
})

test_that("a build nobody has heard of is reported and ignored", {
  # A bad line in ~/.Rprofile must not make the package unloadable.
  withr::with_options(list(rplatypus.torch = "turing"), {
    expect_message(result <- rplatypus:::torch_build_requested(), "ignoring a torch build")
    expect_null(result)
  })
})

test_that("an engine that is not the pinned one says so, naming both versions", {
  # The pin is the mechanism, and on the RETICULATE_PYTHON route it is not in force. The
  # failure without this is a validator refusing a configuration field by name, which
  # tells a reader nothing about their interpreter.
  env <- rplatypus:::.platypus
  old <- env$engine
  withr::defer(env$engine <- old)

  env$engine <- list(`__version__` = "0.8.0a20")
  expect_warning(rplatypus:::check_engine_version(), rplatypus:::pyplatypus_version)
  expect_warning(rplatypus:::check_engine_version(), "0.8.0a20")

  env$engine <- list(`__version__` = rplatypus:::pyplatypus_version)
  expect_silent(rplatypus:::check_engine_version())
})

test_that("the development route is exempt, because it asks for a tree with no version", {
  env <- rplatypus:::.platypus
  old <- env$engine
  withr::defer(env$engine <- old)
  env$engine <- list(`__version__` = "0.8.0a20")

  withr::with_envvar(c(PLATYPUS_ENGINE_PATH = "/tmp"), {
    expect_silent(rplatypus:::check_engine_version())
  })
})
