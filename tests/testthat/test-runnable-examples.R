# No runnable example may reach the engine, over EVERY help page rather than over three
# names. `rplatypus#249`.
#
# §3F carried the row *"the functions with runnable examples reach no bridge"* while the
# test it named looped over a literal `c("mask_volume", "instance_sizes", "mask_coverage")`
# and searched each one's own body. A new export whose page has a runnable example reaching
# `shim()` passed it, and so did a helper one level down.
#
# What makes this worth a scan rather than a list is §4's gate that passes because of the
# machine it ran on: `R CMD check` runs every example not in `\dontrun{}`, this machine has
# the engine, and `py_require()` resolves it - so the check is green here and CRAN, which has
# no Python, would be the first to see the failure.

reachable_from <- function(name, namespace = asNamespace("rplatypus"), seen = character()) {
  if (name %in% seen) return(seen)
  seen <- c(seen, name)
  fn <- get0(name, envir = namespace, mode = "function")
  if (is.null(fn)) return(seen)
  # The call graph rather than a text search, so a helper that reaches the bridge is found
  # one level down - which is the half the three-name version could not see.
  called <- tryCatch(codetools::findGlobals(fn, merge = FALSE)$functions,
                     error = function(e) character())
  internal <- intersect(called, ls(namespace, all.names = TRUE))
  for (nxt in setdiff(internal, seen)) seen <- reachable_from(nxt, namespace, seen)
  seen
}

reaches_bridge <- function(name) {
  any(c("shim", "engine") %in% reachable_from(name))
}

#' The example code of one help page, with `\dontrun{}` dropped or kept
runnable_code <- function(path, keep_dontrun = FALSE) {
  rd <- tools::parse_Rd(path)
  tags <- vapply(rd, function(node) attr(node, "Rd_tag") %||% "", character(1))
  blocks <- rd[tags == "\\examples"]
  if (!length(blocks)) return(character())
  pieces <- unlist(lapply(blocks, function(block) {
    lapply(block, function(node) {
      tag <- attr(node, "Rd_tag") %||% ""
      # `\dontrun` is the one thing CRAN does not run, so it is the one thing this scan
      # must drop - and keeping it is the control that the dropping is what matters.
      if (identical(tag, "\\dontrun") && !keep_dontrun) return("")
      paste(unlist(as.character(node)), collapse = "")
    })
  }))
  paste(pieces, collapse = "")
}

names_used <- function(code) {
  if (!length(code) || !nzchar(trimws(code))) return(character())
  expressions <- tryCatch(parse(text = code), error = function(e) NULL)
  if (is.null(expressions)) {
    # A page whose remaining text does not parse is reported rather than skipped: silence
    # here would be a page nobody scanned, which reads exactly like a page with nothing in it.
    return(NA_character_)
  }
  unique(unlist(lapply(expressions, function(e) all.names(e))))
}

pages_reaching_the_bridge <- function(keep_dontrun = FALSE) {
  ours <- getNamespaceExports("rplatypus")
  found <- character()
  unparsed <- character()
  for (path in Sys.glob("../../man/*.Rd")) {
    used <- names_used(runnable_code(path, keep_dontrun = keep_dontrun))
    if (length(used) == 1L && is.na(used)) {
      unparsed <- c(unparsed, basename(path))
      next
    }
    for (name in intersect(used, ours)) {
      if (reaches_bridge(name)) found <- c(found, basename(path))
    }
  }
  list(pages = unique(found), unparsed = unparsed)
}


test_that("no runnable example reaches the engine, over every help page", {
  skip_if_not_installed("codetools")
  skip_if(!length(Sys.glob("../../man/*.Rd")), "run from the package root")

  answer <- pages_reaching_the_bridge()

  expect_identical(answer$unparsed, character(),
                   info = "a page's runnable code did not parse, so it was not scanned")
  expect_identical(answer$pages, character())

  # Three controls, because a scan that found nothing and a scan that looked at nothing read
  # identically.
  #
  # 1. the pages ARE being read: there are as many as `man/` holds
  expect_gt(length(Sys.glob("../../man/*.Rd")), 60)
  # 2. the predicate can say yes, and does for the measurements that forward
  expect_true(reaches_bridge("ellipse_measure"))
  expect_false(reaches_bridge("mask_volume"))
  # 3. and the `\dontrun` dropping is what makes the answer empty: with it kept, pages that
  #    reach the bridge are found. This is the half that proves the scan is not vacuous.
  kept <- pages_reaching_the_bridge(keep_dontrun = TRUE)
  expect_gt(length(kept$pages), 10)
})
