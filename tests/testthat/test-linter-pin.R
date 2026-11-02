# The linter's version, which was §3F's ninth row and the only one that row said nothing
# held. `maju116/pyplatypus`'s `pyproject.toml` pins it exactly - `ruff==x.y.z` - and that
# file's own comment says the version is "declared here and nowhere else", which has been
# false since this package's `lint` job gained ruff.
#
# `inst/python/platypus_shim.py` is the one Python file this package ships, and CI checks it
# with `uvx ruff@x.y.z` - twice, once for `check` and once for `format`. So the number lives
# in four places outside the pin: the engine's manifest, those two lines, and the workbench's
# own notes in §3D.7 and §7.
#
# What the gap costs is invisible until it costs something: ruff adds and changes rules
# between minor releases, so a bump in the engine leaves this package linting by older rules
# and NOTHING FAILS. The two agree again only when somebody notices. Measured on the first
# bump, `0.16.10` to `0.17.2` on 2026-10-26: the shim was clean under both, so that one cost
# nothing and the two were moved together by hand. The next one did not announce itself
# either - it arrived as a Dependabot pull request, which is a notice to whoever reads the
# pull request list rather than to the suite.
#
# The receipt lives on this side alone, for the field-prose ledger's reason: the engine
# declares the version and this package follows, so a bump there turning this red until R
# follows is the pin's ratchet in another place.
# One property of the endpoint, and it bites in BOTH directions. `raw.githubusercontent`
# serves from a cache, so for a few minutes after a bump merges in the engine this test's
# verdict lags the engine's `main`. `test-brand.R` records the red half - a failure against
# content that is already correct. Measured here on 2026-11-02, minutes after
# `maju116/pyplatypus#340` merged: the endpoint still served `ruff==0.17.2` while `main`
# said `0.17.3`, so the test was **green against a divergence that already existed**. A
# green reading taken within minutes of an engine bump is not yet evidence; CI's run,
# minutes later, is.
engine_manifest_url <- "https://raw.githubusercontent.com/maju116/pyplatypus/main/pyproject.toml"
engine_control_url <- "https://raw.githubusercontent.com/maju116/pyplatypus/main/README.md"

fetch_lines <- function(address) {
  tryCatch(
    {
      connection <- url(address, open = "rb")
      on.exit(close(connection), add = TRUE)
      readLines(connection, warn = FALSE)
    },
    error = function(e) NULL,
    warning = function(w) NULL
  )
}

test_that("the ruff this package runs is the one the engine pins", {
  # `.Rbuildignore` keeps `.github` out of the build, so under `R CMD check` the workflow is
  # genuinely absent. Locating it first means the network is never touched there - a test
  # that reaches the internet under a CRAN check is a different problem.
  workflow_path <- NULL
  for (root in c(".", "..", file.path("..", ".."))) {
    candidate <- file.path(root, ".github", "workflows", "R-CMD-check.yaml")
    if (file.exists(candidate)) {
      workflow_path <- candidate
      break
    }
  }
  skip_if(
    is.null(workflow_path),
    "the workflow is not in the build - run the suite from the repository to compare it"
  )

  ours <- grep("uvx ruff@", readLines(workflow_path, warn = FALSE), value = TRUE)
  # BOTH commands, or this compares one line and reports the other agreed. §3D.7 records the
  # cost of writing down one of a job's three commands.
  expect_gte(
    length(ours),
    2L,
    label = "lines running `uvx ruff@` in the workflow"
  )
  mine <- unique(sub(".*uvx ruff@([0-9][0-9.]*).*", "\\1", ours))
  expect_length(mine, 1L)

  theirs_lines <- fetch_lines(engine_manifest_url)

  # The positive control, because "no network" and "the manifest moved in the engine" are
  # the same silence otherwise.
  if (is.null(theirs_lines) || !length(theirs_lines)) {
    if (length(fetch_lines(engine_control_url)) > 0) {
      fail(paste0(
        "the engine's README is reachable but ", engine_manifest_url, " is not. ",
        "`pyproject.toml` has moved or been renamed in maju116/pyplatypus."
      ))
      return(invisible())
    }
    skip("no network: the engine's pyproject.toml could not be fetched")
  }

  # A 404 body or a rate-limit notice must not read as agreement, and the case that slips
  # through is a wrong body of the right size - so this asks for something only that file
  # has rather than for a length.
  expect_true(
    any(grepl('^name = "pyplatypus"', theirs_lines)),
    info = "what was fetched is not the engine's manifest; the comparison below would be empty"
  )

  pinned <- grep("ruff==", theirs_lines, value = TRUE)
  # Two empty sets compare equal, which is how this check would pass on an engine that had
  # stopped pinning ruff at all.
  expect_gte(length(pinned), 1L, label = "lines pinning `ruff==` in the engine's manifest")
  theirs <- unique(sub(".*ruff==([0-9][0-9.]*).*", "\\1", pinned))
  expect_length(theirs, 1L)

  expect_identical(
    mine,
    theirs,
    info = sprintf(
      paste0(
        "this package runs `uvx ruff@%s` and the engine pins `ruff==%s`.\n",
        "  Four copies live outside that pin: the engine's `pyproject.toml`, the two ",
        "`uvx ruff@` lines in\n  `.github/workflows/R-CMD-check.yaml`, and the workbench's ",
        "§3D.7 and §7. Move them together."
      ),
      mine, theirs
    )
  )
})
