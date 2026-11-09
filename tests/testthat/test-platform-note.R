# The macOS fact is the engine's and this page keeps a copy of it, which is what §3F is a
# list of. `maju116/rplatypus#327`, from `maju116/pyplatypus#459`.
#
# torch has published no macOS x86_64 wheel since 2.2.2 and the engine's floor is 2.7, so on
# an Intel Mac the engine cannot be built at all. Neither package can work around it and no
# resolver says it in words anybody can act on - the engine measured that and put the
# sentence in its README, which is the only instrument that reaches that user. This package
# then owes the same sentence for a different reason: its own install SUCCEEDS there, so an
# Intel Mac meets a package that loads and then cannot make its first call.
#
# Two copies of somebody else's measurement is drift waiting to happen, and the direction is
# the same one `test-brand.R` and `test-linter-pin.R` already run in: the engine declares and
# this side follows, so a change there turning this red until R follows is the pin's ratchet
# in another place. What is compared is the VERSION the claim is pinned to, read out of each
# document by its role rather than as a formatted string - the engine's page wraps the number
# onto its own line and this one does not, so a line-for-line comparison would be a
# comparison of typography.
engine_readme_url <- "https://raw.githubusercontent.com/maju116/pyplatypus/main/README.md"
engine_control_url <- "https://raw.githubusercontent.com/maju116/pyplatypus/main/pyproject.toml"

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

# The versions the claim is pinned to, wherever the sentence is written. Backticks are
# stripped because the engine writes `x86_64` and this page writes it plain, and the lines
# are collapsed because either document may wrap mid-sentence. The pattern ends on a digit
# rather than on `[0-9.]+`: the engine's own test for this was written the greedy way first
# and read a sentence's full stop as part of the version.
claimed_torch_versions <- function(lines) {
  flat <- paste(gsub("`", "", lines), collapse = " ")
  phrase <- "no macOS x86_64 wheel since [0-9]+(\\.[0-9]+)*"
  hits <- regmatches(flat, gregexpr(phrase, flat, perl = TRUE))[[1]]
  unique(sub("^.*since ", "", hits))
}

test_that("the macOS claim on this page is the engine's own, version for version", {
  # `.Rbuildignore` is not in a built package, so its absence is how this test knows it is
  # looking at the repository rather than at a tarball - and a test that reaches the network
  # under a CRAN check is a different problem. README.md *is* in the build, so the file being
  # present cannot be the signal the way `_brand.yml`'s absence is in `test-brand.R`.
  root <- NULL
  for (candidate in c(".", "..", file.path("..", ".."))) {
    if (file.exists(file.path(candidate, ".Rbuildignore"))) {
      root <- candidate
      break
    }
  }
  skip_if(
    is.null(root),
    "not in the repository - run the suite from a checkout to compare the two pages"
  )

  ours <- claimed_torch_versions(readLines(file.path(root, "README.md"), warn = FALSE))
  theirs_lines <- fetch_lines(engine_readme_url)

  # The positive control, because "no network" and "the engine's README moved or dropped the
  # claim" are the same silence otherwise. Only BOTH unreachable is a skip.
  if (is.null(theirs_lines)) {
    skip_if(is.null(fetch_lines(engine_control_url)), "the engine's repository is unreachable")
    fail("the engine's README could not be read while its manifest could - the file moved")
  }

  theirs <- claimed_torch_versions(theirs_lines)

  # And the control on the far side: a page that no longer makes the claim at all answers
  # with nothing, which would otherwise make the comparison below pass over an empty set.
  expect_length(theirs, 1)
  expect_gt(length(ours), 0)
  expect_identical(ours, theirs)
})
