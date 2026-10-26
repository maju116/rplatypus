# Every `name()` the NEWEST NEWS.md entry writes has to resolve, because a changelog entry
# saying "the route `platypus_engine_report()` warns about" is an instruction telling a reader
# to go and call something, and that one did not exist. It shipped to `main` inside the
# 0.8.0a44 pin entry and was found by running it rather than by reading it.
#
# The engine has had this instrument since `pyplatypus#230`: `test_schema_prose_names.py`
# reads every `description=` out of `spec_schema()` and asserts every `` `name()` `` in them
# resolves. It found the name it was written for and one it was not. This is R's half, and
# §3F's table is where receipts that live on one side only are listed.
#
# THE SCOPE IS THE NEWEST ENTRY, and that is the whole design rather than a convenience.
# Run against the whole file this test fails on 19 names and every one of them is legitimate:
# `summarise_cases`, `predict_stream` and `onehot_to_colours` are the ENGINE's, named while
# describing what the engine does, and `platypus_split`, `mask_report` and
# `segmentation_generator` are names this package used to have, which a changelog mentions
# precisely because they are gone. A changelog is a record, not a description of the current
# surface, so a test over all of it would be asking the wrong question - §4's loosely
# calibrated check, in the direction nobody warns about: tight enough to fail on correct
# content. Only the entry being written now is anybody's to get right.
#
# Both namespaces count, R's and the engine's, because an entry about an engine release
# legitimately names engine functions. The engine's side is derived by asking it rather than
# listed here, which is what the pin makes safe.

test_that("every `name()` in the newest NEWS.md entry resolves", {
  path <- test_path("..", "..", "NEWS.md")
  skip_if_not(file.exists(path), "NEWS.md is not in the installed package")
  skip_if_not(nzchar(Sys.getenv("PLATYPUS_TEST_ENGINE")), "needs the engine to resolve its names")

  news <- readLines(path, warn = FALSE)
  starts <- grep("^### ", news)
  expect_gt(length(starts), 1)  # control: the entry markers were found at all
  newest <- news[starts[1]:(starts[2] - 1)]

  mentioned <- unlist(regmatches(
    newest, gregexpr("`[a-zA-Z.][a-zA-Z0-9._]*\\(\\)`", newest)
  ))
  mentioned <- unique(gsub("[`()]", "", mentioned))

  # Control: an entry with no function names would pass by having nothing to check, which
  # reads exactly like a silent instrument. Every entry this project writes names something.
  expect_gt(length(mentioned), 0)

  ours <- c(
    getNamespaceExports("rplatypus"),
    ls(asNamespace("rplatypus"), all.names = TRUE)
  )
  elsewhere <- c(
    "base", "stats", "utils", "graphics", "grDevices", "methods", "tools",
    "parallel", "reticulate", "ggplot2", "rlang"
  )
  engine <- tryCatch(
    names(reticulate::py_to_r(reticulate::py_run_string(
      "import pyplatypus as p\nnames = [n for n in dir(p) if not n.startswith('_')]"
    )$names)),
    error = function(e) NULL
  )
  if (is.null(engine)) {
    engine <- tryCatch(
      reticulate::py_run_string(
        "import pyplatypus as p\nnames = [n for n in dir(p) if not n.startswith('_')]"
      )$names,
      error = function(e) character(0)
    )
  }
  expect_gt(length(engine), 20)  # control: the engine answered, rather than failing silently

  unresolved <- Filter(
    function(n) {
      if (n %in% ours || n %in% engine) return(FALSE)
      !any(vapply(elsewhere, function(pkg) {
        ns <- tryCatch(asNamespace(pkg), error = function(e) NULL)
        !is.null(ns) && exists(n, envir = ns, inherits = FALSE)
      }, logical(1)))
    },
    mentioned
  )

  expect_identical(
    unresolved, character(0),
    info = paste(
      "the newest NEWS.md entry names these and neither package answers to them:",
      paste(unresolved, collapse = ", ")
    )
  )
})
