# The conditions this package raises, and the page that documents them.
#
# They were classed from the beginning and documented nowhere, so the one thing a script
# needs in order to handle a failure - which class to catch - was discoverable only by
# reading `R/errors.R`. §8 item 4 of the project notes carried that for a while as "R
# documents no condition classes".
#
# Writing the page found two defects in the class vector, which is the argument for writing
# documentation as a user would read it rather than describing what the code does.

documented_kinds <- function() {
  # `rd_database()` is in helper-rd.R, which lintr does not see from here - the same
  # annotation test-examples.R carries, for the same reason.
  db <- rd_database()  # nolint: object_usage_linter.
  page <- db[["platypus_conditions.Rd"]]
  if (is.null(page)) return(character(0))

  text <- paste(as.character(page), collapse = "\n")
  # Only the one section lists them. Taking the whole page would also collect
  # `platypus_status`, `platypus_fit` and `platypus_spec` from the prose and the example,
  # and a test that counts those is counting the wrong thing.
  start <- regexpr("The kinds the pinned engine can send", text, fixed = TRUE)
  if (start < 0) return(character(0))
  rest <- substring(text, start)
  stop_at <- regexpr("\\\\section", rest)
  section <- if (stop_at > 0) substring(rest, 1, stop_at - 1) else rest

  found <- regmatches(section, gregexpr("platypus_[a-z_]+", section))[[1]]
  sort(unique(sub("^platypus_", "", found)))
}

engine_kinds <- function() {
  reticulate::py_run_string("
import importlib, pkgutil
import pyplatypus
from pyplatypus.errors import PlatypusError

for found in pkgutil.walk_packages(pyplatypus.__path__, 'pyplatypus.'):
    try:
        importlib.import_module(found.name)
    except Exception:
        pass


def _walk(cls):
    yield cls
    for sub in cls.__subclasses__():
        yield from _walk(sub)


_kinds = sorted({cls.kind for cls in _walk(PlatypusError)})
", convert = TRUE)$`_kinds`
}


test_that("the class vector names the specific kind, then the base, and says nothing twice", {
  expect_identical(
    rplatypus:::condition_classes("config_error"),
    c("platypus_config_error", "platypus_error", "error", "condition")
  )

  # The engine's base class reports `kind = "platypus_error"`, which the old code pasted the
  # prefix onto: `platypus_platypus_error`, a class in nobody's documentation and nobody's
  # `tryCatch()`. Found by writing the documentation, not by reading the code.
  expect_identical(
    rplatypus:::condition_classes("platypus_error"),
    c("platypus_error", "error", "condition")
  )

  # And a failure with no kind said `platypus_error` twice in one vector.
  expect_identical(
    rplatypus:::condition_classes(NULL),
    c("platypus_error", "error", "condition")
  )

  for (kind in c("config_error", "platypus_error", "unknown_case", NULL)) {
    classes <- rplatypus:::condition_classes(kind)
    expect_false(any(duplicated(classes)), info = kind)
    expect_false(any(grepl("platypus_platypus", classes, fixed = TRUE)), info = kind)
    expect_identical(classes[length(classes) - 1L], "error", info = kind)
  }
})

test_that("a raised condition carries the classes and the problems as data", {
  failure <- list(
    ok = FALSE, kind = "config_error", source = "spec.yml",
    problems = list(list(where = "models[1]$loss", problem = "no such loss", got = "'focaal'"))
  )
  condition <- tryCatch(rplatypus:::abort_engine(failure), condition = identity)

  expect_s3_class(condition, "platypus_config_error")
  expect_s3_class(condition, "platypus_error")
  expect_s3_class(condition, "error")
  # The documented promise: one row per problem, with these columns.
  expect_s3_class(condition$problems, "data.frame")
  expect_true(all(c("where", "problem") %in% names(condition$problems)))
  expect_identical(nrow(condition$problems), 1L)
  expect_identical(condition$source, "spec.yml")
})

test_that("the documented kinds are the ones the pinned engine can actually send", {
  # The page lists nineteen class names - eighteen kinds the engine defines and one the
  # bridge raises itself. The number in this comment is asserted nowhere and has been
  # wrong before: it read fifteen while the list held eighteen. A list in prose is a
  # claim, and this is the test
  # that makes it one the engine can contradict - §3C's rule, applied to a list rather
  # than to a number.
  skip_if_no_engine()

  documented <- documented_kinds()
  expect_gt(length(documented), 10)        # or this passes by reading nothing

  from_engine <- engine_kinds()
  expect_gt(length(from_engine), 10)

  # `platypus_error` is the base class and is documented as the thing to catch rather than
  # as a kind, so it is not in the list. Everything else the engine defines must be.
  undocumented <- setdiff(setdiff(from_engine, "platypus_error"), documented)
  expect_identical(
    undocumented, character(0),
    info = paste(
      "the engine defines a kind this page does not list, so it reaches R as a class",
      "nobody can look up:", paste(undocumented, collapse = ", ")
    )
  )

  # The other direction, which is the one that rots: a kind documented after the engine
  # stopped sending it. `unknown_case` is the bridge's own and has no engine class, which
  # the page says in as many words.
  invented <- setdiff(documented, c(from_engine, "unknown_case"))
  expect_identical(
    invented, character(0),
    info = paste(
      "this page lists a kind the engine does not define and the bridge does not raise:",
      paste(invented, collapse = ", ")
    )
  )
})

test_that("the bridge raises the one kind the engine does not define", {
  # `unknown_case` is the page's single exception, so it is worth holding to the shim
  # rather than to the sentence that claims it.
  #
  # `system.file()` rather than a walk up from the test directory, and the first version of
  # this test was the walk: it found the file under `pkgload::load_all()`, found nothing
  # under `R CMD check`, and then crashed - `character(0)[1]` is `NA`, and `readLines(NA)`
  # is an error rather than an empty result. So it failed in the one run that matters most
  # and failed unreadably. pkgload shims `system.file()` onto the source tree, so this
  # finds the shim from a checkout, an installed package and a built tarball alike.
  path <- system.file("python", "platypus_shim.py", package = "rplatypus")
  expect_true(nzchar(path), info = "the shim is not where the package says it is")

  shim <- readLines(path, warn = FALSE)
  expect_true(
    any(grepl("unknown_case", shim, fixed = TRUE)),
    info = "the page documents platypus_unknown_case as the bridge's own, and it is gone"
  )
})
