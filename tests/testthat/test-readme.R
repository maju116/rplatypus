# The README's sections, in the order both packages show them.
#
# Same invariant as the reference groups and for the same reason: the two READMEs cannot be
# equal - this one has to tell its users what happened to `yolo3()`, and the engine has no
# predecessor with users - but they can show the same sections in the same order, so a reader
# arriving from the other repository is not starting again.
#
# Checked rather than left to care. Four claims in the engine's README had gone stale while
# nobody read it, including two that were simply false: that the R surface did not exist, and
# that detection was not on PyPI. This file is the most-read page in the repository and the
# one nothing else looks at.

readme_path <- function() {
  for (candidate in c(".", "..", file.path("..", ".."), file.path("..", "..", ".."))) {
    path <- file.path(candidate, "README.md")
    if (file.exists(path)) {
      return(path)
    }
  }
  NULL
}

# Also in pyplatypus's tests/test_readme.py. "About the engine" is this package's alone -
# the engine is not a dependency of itself - and the two `###` subsections about coming from
# 0.1.1 have no counterpart there, because nothing was released before the rewrite.
section_order <- c(
  "Installing",
  "A worked example",
  "The same thing from a file",
  "What is in it",
  "Boxes instead of masks",
  "A backbone instead of the built-in encoder",
  "Learning it",
  "What is not in it yet",
  "About the engine",
  "About the author",
  "Licence"
)

readme_sections <- function(path) {
  lines <- readLines(path, warn = FALSE)
  # A `## ` inside a fenced block is not a heading, and this README has R and YAML in it.
  fenced <- cumsum(grepl("^\\s*```", lines)) %% 2 == 1
  fence_line <- grepl("^\\s*```", lines)
  heads <- grepl("^## ", lines) & !fenced & !fence_line
  trimws(sub("^## ", "", lines[heads]))
}

test_that("the README sections are a subsequence of the order pyplatypus shares", {
  path <- readme_path()
  skip_if(is.null(path), "README.md not reachable from here")

  got <- readme_sections(path)
  expect_gt(length(got), 8)

  expect_identical(
    setdiff(got, section_order), character(0),
    info = paste(
      "sections outside the shared order. Adding one means adding it to section_order here",
      "and in pyplatypus, or naming it what the other README calls it"
    )
  )
  expect_identical(
    got, section_order[section_order %in% got],
    info = "the README is out of the order both packages share"
  )
})

test_that("the sections that must be here are", {
  # The subsequence test permits absence, which is how the reference-groups test let drift
  # back in until it was pinned. Every one of these has something to say in both packages.
  path <- readme_path()
  skip_if(is.null(path), "README.md not reachable from here")

  expect_identical(
    setdiff(section_order, readme_sections(path)), character(0),
    info = "a section the shared order requires is missing"
  )
})

test_that("no two vignettes draw into the same figure file", {
  # knitr names a figure after its chunk, and all the vignettes share one `fig.path`. So two
  # documents with a chunk called `history` write the same PNG, the second knit silently
  # replaces the first document's picture, and nothing anywhere complains - the figure is
  # still there, still a plot, and about the wrong model.
  #
  # That is not hypothetical: `instances.Rmd` was written with an unprefixed `history` chunk
  # and overwrote `data-science-bowl.Rmd`'s training curve with an instance model's. Caught by
  # listing the tarball rather than by any test, which is why this one exists. `git` held the
  # original, so the cost was a re-knit; had the collision been noticed a week later, the
  # restored figure would have been whatever the last run produced.
  dir <- vignettes_dir()
  skip_if(is.null(dir), "vignettes/ not reachable from here")

  shipped <- Sys.glob(file.path(dir, "*.Rmd"))
  skip_if(!length(shipped), "no knitted vignettes here")

  drawn <- lapply(shipped, function(path) {
    text <- paste(readLines(path, warn = FALSE), collapse = "\n")
    unique(regmatches(text, gregexpr("figures/[^)\"' ]+", text))[[1]])
  })
  names(drawn) <- basename(shipped)
  figures <- unlist(drawn, use.names = FALSE)
  expect_gt(length(figures), 5)   # or this passes by looking at nothing

  shared <- names(which(table(figures) > 1))
  expect_identical(
    shared, character(0),
    info = paste("two vignettes draw into the same file, so one of them shows the other's",
                 "picture:", paste(shared, collapse = ", "))
  )
})

test_that("the README names every vignette that runs something", {
  # Written because the sentence above that list said "Three vignettes" and named four, from
  # the day `retinal-vessels` landed until the two lines were read together. §3C's rule is
  # that a number in prose needs a test holding it or no number at all, and the count is gone
  # - but the *list* is the thing a reader uses, so this holds the list instead.
  #
  # The `.Rmd.orig` files are exactly the vignettes that run something: `precompute.R` knits
  # those and says why `configuration.Rmd` is not among them - it is prose with
  # `eval = FALSE` chunks, held by test-guide.R instead. So a new worked vignette fails this
  # until the README names it, and a prose one does not have to.
  path <- readme_path()
  skip_if(is.null(path), "README.md not reachable from here")
  dir <- vignettes_dir()
  skip_if(is.null(dir), "vignettes/ not reachable from here")

  sources <- Sys.glob(file.path(dir, "*.Rmd.orig"))
  runs_something <- sort(sub("\\.Rmd\\.orig$", "", basename(sources)))
  expect_gt(length(runs_something), 2)   # or this passes by looking at nothing

  readme <- paste(readLines(path, warn = FALSE), collapse = "\n")
  named <- sort(unique(gsub('.*\\("|"\\).*', "", regmatches(
    readme, gregexpr('vignette\\("[A-Za-z0-9-]+"\\)', readme)
  )[[1]])))

  expect_identical(
    setdiff(runs_something, named), character(0),
    info = "a vignette that trains something is not named in the README"
  )
  expect_identical(
    setdiff(named, c(runs_something, "configuration")), character(0),
    info = "the README names a vignette that does not exist"
  )
})
