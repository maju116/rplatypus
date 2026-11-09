# THE CRAN GATE IS TWO THINGS AND THE COMMENT ABOVE IT WAS ONLY TRUE OF ONE, which is
# `maju116/rplatypus#322`. `#319` deleted an `args:` override so that
# `check-r-package@v2`'s own default - `c("--no-manual", "--as-cran")` - would apply, and
# wrote beside it that the flag therefore emits `Maintainer` and `Days since last update`.
# It did not. Before calling `rcmdcheck`, the action sets `_R_CHECK_CRAN_INCOMING_` to the
# string `false` whenever that variable is empty - and `tools:::.check_packages` consults
# `--as-cran` for the incoming section ONLY when the variable is unset, taking the
# variable's own value otherwise. So the flag was passed and the whole *CRAN incoming
# feasibility* section never ran.
#
# TURNING IT ON WAS TRIED AND MADE THE GATE WORSE, measured in CI on this workflow: the
# section needs CRAN's own package database, the fetch timed out from the runner at 60
# seconds, and `R CMD check` printed `Execution halted` after SEVEN `* checking` steps -
# with `rcmdcheck` reporting success and the job going green. So the decision is the
# section stays off, the prose says so, and what this file holds changed with it.
#
#     the section on, in CI          7 steps, no Status: line, job GREEN
#     the section on, locally      50 steps, Status: 2 NOTEs
#     the section off (today)      48 steps, Status: 1 NOTE
#
# WHAT IT HOLDS NOW, and it is still two halves because either alone reads as a gate
# stronger than it is:
#
#   - the FLAG arrives, which means no `args:` override on the step - the thing `#319`
#     deleted and the thing a future edit would most plausibly put back;
#   - the CHECK LEAVES A VERDICT, which means the step that asserts a `Status:` line is in
#     the job. That guard is what this branch really produced: a check that dies before its
#     verdict is indistinguishable from a clean one, and nothing noticed until something
#     died. §4's step with no repair chained to a check whose result nobody reads.
#
# WHAT IT CANNOT DO is read a CI run; that needs `gh` and a network, and a test that reaches
# the internet under a CRAN check is a different problem. It holds the workflow to the claim
# its own comment makes, which is the half that drifted.

# `.Rbuildignore` keeps `.github` out of the build, so under `R CMD check` the workflow is
# genuinely absent and this skips - the same shape `test-linter-pin.R` uses and for the same
# reason. The gates of §3D.7 run from the repository, where it is present.
find_workflow <- function() {
  for (root in c(".", "..", file.path("..", ".."))) {
    candidate <- file.path(root, ".github", "workflows", "R-CMD-check.yaml")
    if (file.exists(candidate)) {
      return(candidate)
    }
  }
  NULL
}

# The job's own block, by indentation rather than by a line range over the whole file:
# §4's empty `awk` range answers zero exactly like an empty search, so the span's length is
# returned beside its contents and asserted.
job_block <- function(lines, job) {
  start <- grep(paste0("^  ", job, ":\\s*$"), lines)
  if (length(start) != 1L) {
    return(NULL)
  }
  rest <- lines[(start + 1L):length(lines)]
  next_job <- grep("^  [A-Za-z0-9_-]+:\\s*$", rest)
  end <- if (length(next_job)) start + next_job[1L] - 1L else length(lines)
  lines[start:end]
}

test_that("the CRAN gate carries both halves, the flag and a verdict", {
  path <- find_workflow()
  skip_if(
    is.null(path),
    "the workflow is not in the build - run the suite from the repository to check the gate"
  )

  lines <- readLines(path, warn = FALSE)
  block <- job_block(lines, "R-CMD-check")

  # Controls on the extraction, because a block that came back empty would report every
  # absence below as a pass.
  expect_false(is.null(block))
  expect_gt(length(block), 30L)

  # The `uses:` line and not merely a mention of the name: the `env:` comment above names
  # the action too, so a loose match found two lines and took the first - which is the
  # instrument answering a question next to the one asked.
  step <- grep("^\\s*-?\\s*uses:\\s*r-lib/actions/check-r-package", block)
  expect_length(step, 1L)

  # HALF ONE: the flag arrives from the action's own default, so there is no `args:`
  # override on the step.
  with_block <- block[step:length(block)]
  overrides <- grep("^\\s*args:", with_block, value = TRUE)
  expect_identical(
    paste(trimws(overrides), collapse = "; "),
    "",
    label = "`args:` overrides on the check-r-package step"
  )

  # HALF TWO: the job asserts the check reached a verdict. Held by the step's presence AND
  # by what it greps for, because a step that looked for the wrong string would be a guard
  # in name only.
  #
  # SCOPED TO THE STEP'S OWN LINES, and the first draft was not: `any(grepl("Status:",
  # block))` is satisfied by the `env:` comment above, which quotes `Status: 1 NOTE` in its
  # measurement table. That is the shape `maju116/pyplatypus#388` was - a grep satisfied by
  # a name in a comment - and it would have passed over a guard that looked for nothing.
  verdict <- grep("^\\s*- name: The check has to have reached a verdict", block)
  expect_length(verdict, 1L)
  guard <- block[verdict:length(block)]
  expect_true(any(grepl("00check.log", guard, fixed = TRUE)))
  expect_true(any(grepl("grep -qE '^Status:'", guard, fixed = TRUE)))
})

test_that("the verdict guard's own question is the one a truncated check fails", {
  # The guard is shell in a workflow, so the suite cannot run it - but the question it asks
  # is one line and is worth holding here rather than nowhere: a log that stops before its
  # verdict has no `Status:` line, and one that finishes has exactly one. Both directions,
  # on text, because the real logs live in CI.
  finished <- c("* checking foo ... OK", "* DONE", "Status: 1 NOTE")
  truncated <- c("* checking foo ... OK", "* checking CRAN incoming feasibility ...",
                 "Error in read.dcf(con) : cannot open the connection", "Execution halted")
  expect_length(grep("^Status:", finished), 1L)
  expect_length(grep("^Status:", truncated), 0L)
})
