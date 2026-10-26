# The shipped vignette is generated from its `.Rmd.orig` and NOTHING held the two together.
#
# `maju116/rplatypus#234`. `precompute.R` knits six sources into the `.Rmd` files that ship,
# because one of them trains two models on 5.6 GB of images that a CRAN machine does not have.
# That two-file shape is correct; what was missing is anything noticing when the output stops
# matching the input.
#
# Measured on 2026-10-26, before this test existed: five of the six shipped files were behind
# their source, all by the same block - the "THIS PROSE HAS A COUNTERPART" comment that
# `#186` added to every source on 2026-10-23, which only `fetal-head` had caught up with.
#
# **Every missing line was an HTML comment, so no reader had ever seen the drift.** That is
# the reason to write this rather than a reason not to: §4 says an error that changes no
# decision is an error nobody looks for, and a drift a reader cannot see is that error with a
# longer fuse. The next edit to a source could be a sentence about what a function does.
#
# `test-readme.R` checks which vignettes HAVE a `.orig`, so the list cannot rot. It says
# nothing about whether the output was knitted from the current input, and those are different
# questions.

test_that("every prose line of a vignette source reached the file that ships", {
  dir <- vignettes_dir()
  skip_if(is.null(dir), "vignettes/ not reachable from here")

  sources <- Sys.glob(file.path(dir, "*.Rmd.orig"))
  # Control: an empty glob reports nothing missing and would pass by looking at nothing,
  # which is the failure this project keeps finding in its own instruments.
  expect_gt(length(sources), 2)

  for (source in sources) {
    name <- sub("\\.Rmd\\.orig$", "", basename(source))
    knitted <- file.path(dir, paste0(name, ".Rmd"))
    expect_true(file.exists(knitted), info = paste(name, "has a source and no knitted file"))
    if (!file.exists(knitted)) next

    from <- knitr_prose(source)
    to <- knitr_prose(knitted)

    # Inline `r ...` is evaluated in the output, so such a line can never match and is
    # dropped - by the caller rather than by the extractor, so the count below is honest
    # about how much was actually compared.
    comparable <- from[!grepl("`r ", from, fixed = TRUE)]

    # Control, per vignette: a source that failed to read, or whose prose is all inline
    # expressions, must not report a clean comparison.
    expect_gt(length(comparable), 20)

    missing <- setdiff(comparable, to)
    expect_identical(
      missing, character(0),
      info = paste0(
        name, ": ", length(missing), " of ", length(comparable),
        " prose lines are in the source and not in the shipped file - re-knit it with ",
        "`Rscript vignettes/precompute.R ", name, "`. First: ",
        if (length(missing)) substr(missing[1], 1, 60) else ""
      )
    )
  }
})


test_that("the comparison can fail, which is the only reason to believe it passing", {
  # The positive control for the instrument rather than for the vignettes. Run on strings, so
  # it needs no files and cannot be satisfied by whatever happens to be on this disk.
  #
  # Written because the test above is a `setdiff` against a file somebody else generates: if
  # `knitr_prose()` returned nothing, or everything, the loop would report a clean run in both
  # directions and nobody would know which.
  source_like <- c(
    "---", "title: thing", "---",
    "A sentence that survives knitting.",
    "",
    "```{r chunk}",
    "x <- 1",
    "```",
    "A number computed inline: `r x`.",
    "A sentence that was ADDED to the source and never knitted."
  )
  knitted_like <- c(
    "---", "title: thing", "---",
    "A sentence that survives knitting.",
    "",
    "``` r",
    "x <- 1",
    "#> [1] 1",
    "```",
    "A number computed inline: 1."
  )

  tmp <- withr::local_tempdir()
  writeLines(source_like, file.path(tmp, "a.Rmd.orig"))
  writeLines(knitted_like, file.path(tmp, "a.Rmd"))

  from <- knitr_prose(file.path(tmp, "a.Rmd.orig"))
  to <- knitr_prose(file.path(tmp, "a.Rmd"))
  comparable <- from[!grepl("`r ", from, fixed = TRUE)]

  # The chunk body is gone from both, the inline line is dropped, and the prose that is in
  # the source alone is caught - all three at once, so the extractor is pinned in every
  # direction this test can reach.
  expect_false("x <- 1" %in% from)
  expect_false("x <- 1" %in% to)
  expect_false(any(grepl("`r x`", comparable, fixed = TRUE)))
  expect_identical(
    setdiff(comparable, to),
    "A sentence that was ADDED to the source and never knitted."
  )

  # And the other direction: with that line removed from the source, the comparison is clean.
  writeLines(source_like[-length(source_like)], file.path(tmp, "b.Rmd.orig"))
  clean <- knitr_prose(file.path(tmp, "b.Rmd.orig"))
  clean <- clean[!grepl("`r ", clean, fixed = TRUE)]
  expect_identical(setdiff(clean, to), character(0))
})
