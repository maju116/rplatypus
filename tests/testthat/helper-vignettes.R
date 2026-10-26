#' Where the vignette sources are, from wherever the suite was started
#'
#' `test_dir("tests/testthat")` runs from the package root, `R CMD check` from
#' `rplatypus.Rcheck/tests`, and the installed package has no `vignettes/` at all - so this
#' answers NULL rather than guessing, and every caller skips on NULL.
#'
#' Moved here from `test-readme.R` on 2026-10-26 when a second file needed it. A copy in
#' each would have been the shape §3F of the workbench's notes is a list of, for a function
#' whose whole content is three candidate paths.
vignettes_dir <- function() {
  for (candidate in c("vignettes", file.path("..", "..", "vignettes"),
                      file.path("..", "..", "..", "vignettes"))) {
    if (dir.exists(candidate)) {
      return(candidate)
    }
  }
  NULL
}

#' The prose lines of a knitr document: what is copied through verbatim
#'
#' knitr replaces a chunk with the chunk plus its output and leaves everything else alone, so
#' a prose line of a `.Rmd.orig` must appear in the `.Rmd` knitted from it. This returns the
#' lines that comparison is allowed to use:
#'
#'   * R chunk bodies are dropped, in BOTH spellings of the opening fence
#'   * fence lines themselves are dropped, because they carry no claim
#'   * output lines are dropped, because only the `.Rmd` has them
#'   * blank lines are dropped, for the same reason as fences
#'
#' **Both spellings, and that is not a detail.** A source opens a chunk with ```{r name} and
#' knitr rewrites it as ``` r, so a pattern written for the source alone leaves every line of
#' every chunk body in the OUTPUT's prose - which makes the comparison one-sidedly permissive
#' rather than wrong, and therefore invisible. The control in
#' `test-precomputed-vignettes.R` caught exactly that on the first run of this function.
#'
#' A fenced block that is not an R chunk is kept: it is verbatim on both sides, so comparing
#' it costs nothing and skipping it would be coverage given away.
#'
#' Lines holding an inline `` `r expression` `` are returned, and the CALLER drops them: they
#' are evaluated in the output by construction, so they can never match. Dropping them here
#' instead would hide how many lines a comparison actually looked at.
knitr_prose <- function(path) {
  lines <- readLines(path, warn = FALSE)
  inside <- FALSE
  keep <- character(0)
  for (line in lines) {
    if (!inside && grepl("^```+\\s*\\{?r\\b", line)) {
      inside <- TRUE
      next
    }
    if (inside) {
      if (startsWith(line, "```")) inside <- FALSE
      next
    }
    if (startsWith(line, "```") || startsWith(line, "#>")) next
    trimmed <- trimws(line)
    if (nzchar(trimmed)) keep <- c(keep, trimmed)
  }
  keep
}
