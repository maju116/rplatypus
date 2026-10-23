# A vignette and the engine's article that mirrors it walk the same sections.
#
# `maju116/rplatypus#117` settles the direction: the vignette is the **source** and the
# article is the **copy**. `maju116/pyplatypus#242` built the engine's half, which fetches
# these vignettes and compares. This is the other direction, and it exists for a reason that
# is about *when* a failure arrives rather than whether:
#
#   a heading edited here would pass this package's suite and redden the ENGINE's `main` at
#   its next commit - about something else entirely. A red build on a commit that did not
#   cause it is worse than a red build on the one that did, so the person editing the source
#   has to learn from their own suite.
#
# What is pinned is the walk, not the route. Measured on the pair that existed first:
# `guide.qmd` and `configuration.Rmd` carry the same ten `##` headings in the same order,
# the same YAML blocks verbatim, and 2 blocks of Python against 11 of R. The engine reaches
# a destination through a configuration file where this package reaches it through
# constructors, and `pyplatypus#237` asks for exactly that difference.
#
# `###` is deliberately not pinned. Sub-structure is where the route differs.

engine_raw <- "https://raw.githubusercontent.com/maju116/pyplatypus/main"
engine_control_url <- paste0(engine_raw, "/README.md")

# The one pair whose names differ: this package's configuration vignette is the engine's
# guide. Everything else is the same stem with a different extension.
article_for <- function(stem) {
  if (identical(stem, "configuration")) "guide.qmd" else paste0(stem, ".qmd")
}

# Vignettes whose article is not written yet, each with the issue that will write it.
#
# `data-science-bowl` was here until `maju116/pyplatypus#246` merged, and the second test
# below failed within minutes of that merge - which is the list working rather than a
# nuisance. An entry whose article now exists is a pair that stopped being compared, and
# this is the only mechanism that says so. **This
# list must shrink to nothing**, and it cannot go stale in either direction: a vignette left
# out of it with no article fails the first test below, and a vignette left *in* it after the
# article appears fails the second. So it is a record of the remaining work rather than a set
# of exemptions somebody has to remember to prune.
awaiting <- c(
  "blood-cells"       = "maju116/pyplatypus#174",
  "volumes"           = "maju116/pyplatypus#175",
  "retinal-vessels"   = "maju116/pyplatypus#243"
)

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

vignette_dir <- function() {
  for (root in c(".", "..", file.path("..", ".."))) {
    candidate <- file.path(root, "vignettes")
    if (dir.exists(candidate) && length(list.files(candidate, pattern = "[.]Rmd$"))) {
      return(candidate)
    }
  }
  NULL
}

sections_of <- function(lines) {
  found <- grep("^## ", lines, value = TRUE)
  sub("^## ", "", found)
}

test_that("every vignette either has an engine article or an issue that will write it", {
  # The guard: without it every assertion below passes by iterating over nothing, which is
  # the shape §4 of the workbench's notes names as its commonest.
  directory <- vignette_dir()
  skip_if(is.null(directory), "vignettes/ is not in the build - run the suite from the repo")

  stems <- sub("[.]Rmd$", "", list.files(directory, pattern = "[.]Rmd$"))
  expect_gt(length(stems), 4)

  # Derived rather than listed, and the first version of this was not. It subtracted
  # `c(names(awaiting), "configuration", "instances")` - a second list of the pairs that do
  # exist, which somebody would have had to maintain beside the first. It failed the moment
  # `pyplatypus#246` merged and `data-science-bowl` belonged to neither list. So the question
  # asked here is the one that needs no bookkeeping: is this vignette either waiting for an
  # article, or does its article answer?
  unaccounted <- character(0)
  for (stem in setdiff(stems, names(awaiting))) {
    if (length(fetch_lines(paste0(engine_raw, "/", article_for(stem)))) > 0) next
    if (length(fetch_lines(engine_control_url)) == 0) {
      skip("no network: cannot tell a missing article from an unreachable one")
    }
    unaccounted <- c(unaccounted, stem)
  }
  expect_identical(
    unaccounted, character(0),
    info = paste0(
      "these vignettes have no engine article and no issue in `awaiting`: ",
      paste(unaccounted, collapse = ", "),
      ". A vignette absent from both is the gap that hides inside a milestone's arithmetic."
    )
  )
})

test_that("a vignette listed as awaiting its article really has none", {
  # The half that keeps the list honest in the other direction. If the engine writes one of
  # these and nobody removes the entry here, this fails - so the list cannot quietly rot into
  # a set of pairs that stopped being checked.
  for (stem in names(awaiting)) {
    lines <- fetch_lines(paste0(engine_raw, "/", article_for(stem)))
    if (is.null(lines) || !length(lines)) next

    fail(paste0(
      article_for(stem), " exists in the engine now, so `awaiting` is stale: remove the ",
      stem, " entry (", awaiting[[stem]], ") and let the pair be compared."
    ))
  }
  succeed()
})

test_that("a vignette with an article walks the same sections", {
  directory <- vignette_dir()
  skip_if(is.null(directory), "vignettes/ is not in the build - run the suite from the repo")

  paired <- setdiff(
    sub("[.]Rmd$", "", list.files(directory, pattern = "[.]Rmd$")),
    names(awaiting)
  )
  expect_gt(length(paired), 2)

  for (stem in paired) {
    address <- paste0(engine_raw, "/", article_for(stem))
    theirs <- fetch_lines(address)

    # The positive control, as `test-brand.R` uses it: "no network" and "the article has
    # moved" are the same silence otherwise.
    if (is.null(theirs) || !length(theirs)) {
      if (length(fetch_lines(engine_control_url)) > 0) {
        fail(paste0(
          "the engine's README is reachable but ", address, " is not. ",
          stem, ".Rmd is paired with it, so either the article was renamed or this ",
          "pairing is wrong - that is a finding, not a network problem."
        ))
        next
      }
      skip(paste0("no network: ", address, " could not be fetched"))
    }

    ours <- sections_of(readLines(file.path(directory, paste0(stem, ".Rmd")), warn = FALSE))
    expect_gt(length(ours), 0)
    expect_identical(
      sections_of(theirs), ours,
      info = paste0(
        stem, ".Rmd and the engine's ", article_for(stem),
        " have come to walk different paths. This vignette is the source, so the article ",
        "follows it - or both change together and deliberately."
      )
    )
  }
})
