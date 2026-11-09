# EVERY JOB IN EVERY WORKFLOW CARRIES A CEILING, which is `maju116/pyplatypus#457`. Without
# `timeout-minutes` a hung job runs to GitHub's 360-minute default, and the sixteenth review
# pass saw the engine's suite deadlock once at a two-worker detection test - the main process
# asleep, both children at zero CPU, `utime` unmoved across two reads thirteen minutes apart.
# Nothing in either repository set a timeout, so that run would have burned six hours before
# going red.
#
# This is the COMPLETENESS half rather than a check of the number. A ceiling nobody set is how
# this comes back - a new job arrives and inherits the default in silence - and refusing the
# job that has none is the one thing a test can do about it. What the right figure is cannot
# be tested, only measured, and its argument lives in the comment beside it in the workflow.
#
# Parsed by indentation rather than with `yaml`, which is only in `Suggests`: a
# `skip_if_not_installed` here would make the answer depend on what happens to be installed,
# and §3D.7 reads the skip count as a signal about the engine rather than about the parser.

workflow_files <- function() {
  for (root in c(".", "..", file.path("..", ".."))) {
    candidate <- file.path(root, ".github", "workflows")
    if (dir.exists(candidate)) {
      return(sort(Sys.glob(file.path(candidate, "*.y*ml"))))
    }
  }
  character()
}

jobs_without_a_ceiling <- function(path) {
  lines <- readLines(path, warn = FALSE)
  starts <- grep("^  [A-Za-z0-9_-]+:[[:space:]]*$", lines)
  if (!length(starts)) {
    return(NA_character_)
  }
  ends <- c(starts[-1] - 1L, length(lines))
  without <- character()
  for (i in seq_along(starts)) {
    block <- lines[starts[i]:ends[i]]
    # A job is a block that says where it runs; `on:`'s own children do not.
    if (!any(grepl("^    runs-on:", block))) {
      next
    }
    if (!any(grepl("^    timeout-minutes:[[:space:]]*[0-9]+[[:space:]]*$", block))) {
      without <- c(without, trimws(sub(":.*$", "", lines[starts[i]])))
    }
  }
  without
}

test_that("every job in this package's workflows carries a timeout", {
  files <- workflow_files()
  skip_if(
    !length(files),
    "the workflows are not in the build - run the suite from the repository to check them"
  )

  # Controls on the scan, because an empty file list or a file with no jobs would make the
  # assertion below pass over nothing.
  expect_gte(length(files), 2L)
  expect_true(any(grepl("R-CMD-check", basename(files))))

  for (path in files) {
    without <- jobs_without_a_ceiling(path)
    expect_false(
      identical(without, NA_character_),
      label = paste("jobs found in", basename(path))
    )
    expect_identical(
      paste(without, collapse = ", "), "",
      label = paste("jobs in", basename(path), "with no timeout-minutes")
    )
  }
})

test_that("the scan can tell a job with a ceiling from one without", {
  # Both directions on text, because a scan that answered "none missing" to everything
  # would report a clean sweep over workflows it never read.
  good <- tempfile(fileext = ".yaml")
  bad <- tempfile(fileext = ".yaml")
  on.exit(unlink(c(good, bad)), add = TRUE)
  writeLines(c("jobs:", "  one:", "    runs-on: ubuntu-latest", "    timeout-minutes: 45"), good)
  writeLines(c("jobs:", "  one:", "    runs-on: ubuntu-latest"), bad)
  expect_identical(jobs_without_a_ceiling(good), character())
  expect_identical(jobs_without_a_ceiling(bad), "one")
})
