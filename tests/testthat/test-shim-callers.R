# A SHIM FUNCTION WITH NO CALLER IS A SECOND COPY OF AN ENGINE SIGNATURE THAT NOTHING
# HOLDS, and `maju116/rplatypus#317` was three of them - `anchor_report`, `target_survey`
# and `model_names` - found by reading the file rather than by anything failing. The engine
# has the same shape twice: `DetectionMetrics.as_rows()`, whose only caller was the test
# written for it, was deleted rather than completed on §3F's argument that a copy removed is
# worth more than a copy corrected. This is the census that makes a fourth one fail here.
#
# THE QUESTION IS ASKED OF THE CODE RATHER THAN OF `R/`, which is what lets it run where it
# matters most. `R/` is not in an installed package, so a grep over the sources would skip
# under `R CMD check` and in the `engine` job. Every function in the namespace is deparsed
# instead, so `shim()$case_table` is found as the call it is.
#
# THE SUITE COUNTS AS A CALLER, and that is not a loosening. Four of these functions exist
# for it: `volume_support`, `series_support` and `window_presets` are the probes the helpers
# ask before skipping, and `drawing_style`'s own docstring says it is there for
# `test-drawing-style.R` and is "not used when drawing". A shim function the suite reaches
# is reached.
#
# THIS FILE IS EXCLUDED FROM THE SEARCH, and the reason is the whole instrument: the
# paragraph above names all three deleted functions, so a census that read its own comment
# would report them reached. §4's probe that answers a question adjacent to the one it was
# named after, which here would have made the census pass over the very defect it is for.
#
# AND THE EXCLUSION IS HELD BY THE NEGATIVE CONTROL RATHER THAN BY THE CENSUS ROW, which
# is measured rather than designed: dropping it was mutated with a callerless function
# reinstated beside it, expecting the row to go quiet - and what failed instead was
# `reached("zzz_not_a_shim_function")`, because that literal is in this file. So reading
# its own source is caught whether or not anything is callerless, which is one assertion
# earlier than the shape this comment first claimed.
#
# WHAT IT CANNOT DO is tell a call from a coincidence: a local variable called `predictions`
# in some unrelated function satisfies the search for the shim's `predictions`. That is the
# comfortable direction - it can miss a dead function, never condemn a live one - and it is
# the trade this census makes to stay free of a list of names. It guarantees somebody was
# asked, which is what the field-prose ledger and the shared-`@param` census do.
#
# NO EXEMPTION LIST, measured rather than hoped for: with #317's three gone, every public
# function in that file is reached. The day one needs an exemption is the day somebody
# writes a function ahead of its caller, and the reason belongs beside the name then.

shim_function_names <- function() {
  # `system.file()` rather than a walk up from the test directory, which is
  # `test-conditions.R`'s own measurement: pkgload shims it onto the source tree, so this
  # finds the shim from a checkout, an installed package and a built tarball alike. A
  # failure rather than a skip, because §3D.7 reads the skip count as the signal that the
  # bridge was exercised, and a census that quietly did not run is worth nothing.
  path <- system.file("python", "platypus_shim.py", package = "rplatypus")
  testthat::expect_true(nzchar(path), info = "the shim is not where the package says it is")
  lines <- readLines(path, warn = FALSE)
  # `^def ` is the top level, so a nested helper is out by indentation, and `[a-z]` leaves
  # the private ones out by their underscore rather than by a second filter.
  defs <- grep("^def [a-z]", lines, value = TRUE)
  sub("^def ([a-zA-Z_][a-zA-Z0-9_]*).*$", "\\1", defs)
}

# Everything that could hold a call: the package's own code, read off the namespace rather
# than off the sources, and the suite's files minus this one.
shim_caller_text <- function() {
  namespace <- asNamespace("rplatypus")
  code <- vapply(
    ls(namespace, all.names = TRUE),
    function(name) {
      object <- get(name, envir = namespace)
      if (is.function(object)) paste(deparse(object), collapse = "\n") else ""
    },
    character(1)
  )
  files <- list.files(testthat::test_path("."), pattern = "[.]R$", full.names = TRUE)
  files <- files[basename(files) != "test-shim-callers.R"]
  c(unname(code), unlist(lapply(files, readLines, warn = FALSE)))
}

test_that("every function the shipped shim exports is reached from R or from the suite", {
  names <- shim_function_names()

  # Controls on the enumeration: a regex that matched nothing would report a clean census
  # over a file it never read, which is the reading §4 says to disbelieve first.
  # 30 rather than 43, the number there are: a floor is for a scan that found nothing,
  # and one set just under the true count fails the day somebody legitimately deletes
  # four functions - §4's check tight enough to fail on correct content.
  expect_gt(length(names), 30)
  expect_true(all(c("case_table", "instance_predictions") %in% names))
  expect_false(any(startsWith(names, "_")))

  haystack <- shim_caller_text()
  expect_gt(length(haystack), 100)

  reached <- function(name) {
    any(grepl(paste0("\\b", name, "\\b"), haystack, perl = TRUE))
  }

  # Controls on the matcher, both directions, because one that answers TRUE to everything
  # and one that answers FALSE to everything both read as a verdict.
  expect_true(reached("case_table"))
  expect_false(reached("zzz_not_a_shim_function"))

  unreached <- Filter(function(name) !reached(name), names)
  # Pasted rather than compared as a vector, so that a failure names the functions.
  expect_identical(paste(unreached, collapse = ", "), "")
})
