# A shipped vignette prints the weights registry's revisions as knitted output, and nothing
# held them to the registry. `maju116/rplatypus#301`.
#
# `data-science-bowl.Rmd` carries a table from `available_weights()[, c("name", "revision")]`,
# and `fives-unet`'s cell read `c4492f7a...` while the registry had said `799fea5c` since
# `0.8.0a74` and `d342f3ad` since `0.8.0a77`. Two pin moves stale.
#
# A REVISION IS THE WORST COLUMN ON THAT PAGE TO LET ROT, because it is the one value a
# reader copies: `hf://maju116/platypus-weights/fives-unet.safetensors@c4492f7a...` is a
# supported form and it still resolves. What it fetches is the sidecar as it was before
# `maju116/pyplatypus#426` - no `cldice_iterations`, which is the file that defect was about.
# So the stale cell does not fail; it hands back the superseded artefact, from the page that
# teaches borrowing published weights.
#
# The two instruments that look like they cover this both answer a different question:
# `test-weights.R` asserts every revision IN THE REGISTRY is forty hex characters and never
# reads a vignette, and `test-precomputed-vignettes.R` compares the PROSE lines of each
# `.Rmd.orig` against its `.Rmd` and drops knitted `#>` output on purpose. §3F's failure mode
# is omission rather than staleness, and this is one.

test_that("every weights revision printed in a shipped vignette is one the registry still pins", {
  dir <- vignettes_dir()
  skip_if(is.null(dir), "vignettes/ not reachable from here")
  skip_if_not(nzchar(Sys.getenv("PLATYPUS_TEST_ENGINE")), "needs the engine for the registry")

  shipped <- Sys.glob(file.path(dir, "*.Rmd"))
  # Control: an empty glob finds no stale revision and passes by looking at nothing, which
  # is this project's commonest instrument failure.
  expect_gt(length(shipped), 4)

  pinned <- available_weights()$revision
  expect_gt(length(pinned), 3)                      # control: the registry answered
  expect_true(all(grepl("^[0-9a-f]{40}$", pinned))) # control: and answered with revisions

  # Forty hex characters is what a revision looks like; a vignette has no other reason to
  # print one, and the control above is what says the pattern can match something real.
  found <- list()
  for (path in shipped) {
    lines <- readLines(path, warn = FALSE)
    hits <- unlist(regmatches(lines, gregexpr("\\b[0-9a-f]{40}\\b", lines)))
    if (length(hits)) found[[basename(path)]] <- unique(hits)
  }

  # Control: if no vignette prints a revision at all this test is asserting nothing, and
  # that is a state worth failing on rather than passing through - the page that prints the
  # table is shipped, so the expectation is that at least one does.
  expect_gt(length(found), 0)

  stale <- lapply(found, function(hits) setdiff(hits, pinned))
  stale <- stale[vapply(stale, length, integer(1)) > 0]

  expect_identical(
    names(stale), character(0),
    info = paste0(
      "these vignettes print a commit the registry no longer pins: ",
      paste(
        vapply(
          names(stale),
          function(f) paste0(f, " -> ", paste(substr(stale[[f]], 1, 8), collapse = ", ")),
          character(1)
        ),
        collapse = "; "
      ),
      ". A revision is what a reader copies into an `hf://...@commit` reference, so a stale ",
      "one silently fetches the superseded file. Re-knit the page from its `.Rmd.orig`."
    )
  )
})
