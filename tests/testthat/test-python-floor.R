# Which Python this package asks for, held to the engine's own floor.
#
# `rplatypus#338`: `py_require()` takes a `python_version` and this package passed none, so
# the interpreter of the isolated environment was whatever uv's candidate list offered first.
# Measured on 2026-11-11, that list begins `3.11.11, 3.10.16, 3.12.9, 3.9.21, 3.13.2` and is
# NOT sorted by version - reticulate filters it by the declared constraints and takes the
# first that satisfies them - so with no constraint the answer is whatever happens to be at
# the head of a list this package has no opinion about.
#
# The floor is the ENGINE's, `requires-python` in its manifest, and this file is a receipt
# rather than a pair: the engine declares and R follows, so a floor that moves there turns
# this red until the constant follows. That is the pin's ratchet one field over, and it is
# `test-linter-pin.R`'s shape because that test is the same relationship about ruff.
#
# Two halves, and the second is the one that matters. The first compares the numbers. The
# second asserts the constant actually REACHES reticulate: a constant nothing passes is
# §4's declaration attributing a mechanism to code that does not have it, which is the
# strongest disguise this project has met, and the repair - `python_version =` in `.onLoad`
# - is one argument that a reader cannot see from the constant alone.
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

test_that("the Python floor this package declares is the engine's own", {
  # LOCATE THE REPOSITORY BEFORE TOUCHING THE NETWORK, which is `test-linter-pin.R`'s guard
  # and the reason it exists: `.Rbuildignore` keeps `.github` out of the build, so its
  # absence is how a test knows it is running inside one - and a test that reaches the
  # internet under a CRAN check is a different problem from the one it was written for.
  # The `engine` job runs from a checkout, so this is where the comparison actually happens.
  in_a_checkout <- FALSE
  for (root in c(".", "..", file.path("..", ".."))) {
    if (dir.exists(file.path(root, ".github", "workflows"))) {
      in_a_checkout <- TRUE
      break
    }
  }
  skip_if(
    !in_a_checkout,
    "not in the repository - run the suite from a checkout to compare with the engine"
  )

  mine <- rplatypus:::pyplatypus_python
  expect_true(
    grepl("^>=[0-9]+\\.[0-9]+$", mine),
    info = sprintf("the declared constraint is `%s`, which this test cannot compare", mine)
  )

  theirs_lines <- fetch_lines(engine_manifest_url)

  # The positive control, because "no network" and "the manifest moved in the engine" are
  # the same silence otherwise - `test-linter-pin.R` carries this and it is the half that
  # makes a skip mean something.
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
  # through is a wrong body of the right size.
  expect_true(
    any(grepl('^name = "pyplatypus"', theirs_lines)),
    info = "what was fetched is not the engine's manifest; the comparison below would be empty"
  )

  declared <- grep("^requires-python", theirs_lines, value = TRUE)
  # Two empty sets compare equal, which is how this would pass on an engine that had
  # stopped declaring a floor at all.
  expect_length(declared, 1L)
  theirs <- trimws(gsub('"', "", sub("^requires-python\\s*=\\s*", "", declared)))

  expect_identical(
    mine,
    theirs,
    info = sprintf(
      paste0(
        "this package asks uv for Python `%s` and the engine declares `requires-python = ",
        '"%s"`.\n  The engine declares and this follows: move `pyplatypus_python` in ',
        "`R/bridge.R`."
      ),
      mine, theirs
    )
  )
})

test_that("the floor is actually declared rather than only written down", {
  # The half a comparison of two strings cannot see: `pyplatypus_python` could be correct and
  # passed nowhere, which is what it was before `#338` - `py_require()` has taken a
  # `python_version` the whole time and was never given one. That is §4's declaration
  # attributing a mechanism to code which does not have it, and the only thing that catches
  # it is reading the code that would have to be deleted for the claim to become false.
  #
  # ASKED OF THE DEPARSED NAMESPACE rather than of session state, and that is a measurement
  # rather than a style: reticulate REPLACES the constraint with the resolved version once
  # Python starts. Measured 2026-11-11, both ways -
  #
  #                        before Python starts     after
  #     with this change   >=3.11                   3.11.11
  #     without it         (none)                   3.11.11
  #
  # - so after initialisation the two are indistinguishable, and in a full suite run some
  # earlier file has already started the engine. This test FAILED that way on its first full
  # run, which is the right way round. A subprocess would dodge the ordering and buy a worse
  # problem: `callr` inherits the library paths, so it reads the INSTALLED package, and §4
  # records that trap catching this author with a stale pin.
  #
  # The namespace is present in an installed package, so this holds under `R CMD check` and
  # in the `engine` job - the two runs where source files are absent.
  body <- paste(deparse(rplatypus:::.onLoad), collapse = " ")

  expect_match(body, "py_require", fixed = TRUE)
  expect_match(
    gsub("[[:space:]]+", " ", body),
    "python_version = pyplatypus_python",
    fixed = TRUE,
    info = paste0(
      "`.onLoad` does not pass `python_version` to `py_require()`. The constant is then a ",
      "sentence rather than a mechanism, and the interpreter is whatever uv's candidate ",
      "list offers first."
    )
  )

  # And whatever reticulate holds for this session must be consistent with the declaration -
  # true in both states above, which is why it is asserted separately and weakly.
  held <- reticulate:::py_reqs_python_version()
  expect_true(length(held) >= 1L, info = "reticulate holds no Python constraint at all")
  floor <- numeric_version(sub("^>=", "", rplatypus:::pyplatypus_python))
  for (value in held) {
    if (identical(value, rplatypus:::pyplatypus_python)) next
    resolved <- numeric_version(value, strict = FALSE)
    expect_false(
      is.na(resolved),
      info = sprintf("reticulate holds `%s`, which is neither our constraint nor a version", value)
    )
    expect_gte(resolved, floor, label = sprintf("the Python reticulate resolved (%s)", value))
  }
})
