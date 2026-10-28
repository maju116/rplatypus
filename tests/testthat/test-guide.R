# The configuration vignette makes claims that can be checked, so they are.
#
# A reference page generated from the schema cannot contradict the code. A guide written by
# hand can, and the failure is the expensive kind: somebody copies a block, it is refused,
# and the documentation taught them a mistake. Writing the engine's half of this guide
# produced three of those before the prose was finished - `model_checkpoint` has no `mode`,
# it does require a `path`, and `anchors: auto` is not a thing.
#
# The section titles are pinned because pyplatypus's guide walks the same ones, in
# tests/test_guide.py. Neither repository can see the other, so the list is written out in
# both with a comment saying so.

guide_path <- function() {
  for (candidate in c("vignettes", file.path("..", "..", "vignettes"))) {
    path <- file.path(candidate, "configuration.Rmd")
    if (file.exists(path)) {
      return(path)
    }
  }
  NULL
}

# Also in pyplatypus's tests/test_guide.py.
guide_sections <- c(
  "One file, one run",
  "Several models at once",
  "Dividing one folder",
  "Augmentation, callbacks, and the rest of a model",
  "Overlapping classes instead of one per voxel",
  "Instances instead of one mask",
  "Detection instead of segmentation",
  "One label instead of a mask",
  "Not training at all",
  "What is checked, and when",
  "The same run from code"
)

fenced <- function(lines, language) {
  opens <- grep(sprintf("^```%s", language), lines)
  closes <- grep("^```$", lines)
  lapply(opens, function(start) {
    end <- closes[closes > start][1]
    list(line = start, code = lines[(start + 1):(end - 1)])
  })
}

test_that("the guide walks the sections pyplatypus's guide walks", {
  path <- guide_path()
  skip_if(is.null(path), "vignettes/configuration.Rmd not reachable from here")

  headings <- sub("^## ", "", grep("^## ", readLines(path, warn = FALSE), value = TRUE))
  expect_identical(
    headings, guide_sections,
    info = "pyplatypus's guide carries the same list, so change both or neither"
  )
})

test_that("every R chunk in the guide parses and calls functions that exist", {
  path <- guide_path()
  skip_if(is.null(path), "vignettes/configuration.Rmd not reachable from here")

  chunks <- fenced(readLines(path, warn = FALSE), "\\{r")
  expect_gt(length(chunks), 4)

  # `::` calls and chunk-local variables are not this package's to have, so the comparison is
  # against everything reachable rather than against the namespace alone.
  named <- character()
  for (chunk in chunks) {
    parsed <- parse(text = paste(chunk$code, collapse = "\n"))
    for (expression in parsed) named <- c(named, all.names(expression))
  }
  # Operators, chunk-local variables, and calls this package does not own.
  not_ours <- c(
    "::", "$", "<-",
    "spec", "fit",
    "knitr", "opts_chunk", "set",
    "yaml", "write_yaml"
  )
  named <- setdiff(unique(named), not_ours)

  missing <- named[!vapply(named, exists, logical(1))]
  expect_identical(
    missing, character(0),
    info = "the guide calls something that does not exist"
  )
})

test_that("every configuration the guide shows is accepted by the engine", {
  path <- guide_path()
  skip_if(is.null(path), "vignettes/configuration.Rmd not reachable from here")
  skip_if_not(engine_available(), "needs the engine")

  blocks <- fenced(readLines(path, warn = FALSE), "yaml")
  # A `yaml` fence with no `task:` would be something other than a configuration; there are
  # none today, and this says so rather than silently validating fewer than are shown.
  blocks <- Filter(function(b) any(grepl("^task:", b$code)), blocks)
  expect_gte(length(blocks), 5)

  for (block in blocks) {
    file <- tempfile(fileext = ".yaml")
    writeLines(block$code, file)
    expect_no_error(
      platypus_spec(file, check_paths = FALSE),
      message = sprintf(
        "the configuration at line %d of vignettes/configuration.Rmd is refused",
        block$line
      )
    )
  }
})
