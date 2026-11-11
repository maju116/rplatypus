#' The package's own Rd database, from the source tree when it is reachable
#'
#' Source `man/` first, installed package second, and the order matters.
#'
#' `tools::Rd_db("rplatypus")` reads the *installed* package - correct under `R CMD check`,
#' which has just built one, and empty under `pkgload::load_all()`, which is how this package
#' is most often worked on locally. Reading only the installed database left a test skipping
#' in exactly that case: 2 skipped where 0 was expected, and a silently inert tripwire is
#' worse than none. The same hazard made a vignette knit against platypus 0.2.0 and a linter
#' report live helpers as undefined - and caught the author again on 2026-10-10, when a test
#' running through `callr` read an installed package still carrying the previous pin.
#'
#' @keywords internal
#' @noRd
rd_database <- function() {
  for (root in c(".", "..", file.path("..", ".."))) {
    if (dir.exists(file.path(root, "man")) && file.exists(file.path(root, "DESCRIPTION"))) {
      db <- tryCatch(tools::Rd_db(dir = root), error = function(e) list())
      if (length(db)) return(db)
    }
  }
  tryCatch(tools::Rd_db("rplatypus"), error = function(e) list())
}

#' Every name documented as an argument, anywhere in the package
#'
#' Read from the Rd rather than from `#' @param` in `R/`, because the Rd is what a reader
#' sees. A roxygen comment that never regenerated would pass a grep over the source and
#' still be absent from `?platypus_spec`.
#'
#' @keywords internal
#' @noRd
documented_arguments <- function(db = rd_database()) {
  tag_of <- function(x) {
    tag <- attr(x, "Rd_tag")
    if (is.null(tag)) "" else tag
  }
  found <- character(0)
  for (rd in db) {
    tags <- vapply(rd, tag_of, character(1))
    for (block in rd[tags == "\\arguments"]) {
      items <- block[vapply(block, tag_of, character(1)) == "\\item"]
      for (item in items) {
        # An \item is a pair: the names, then the description. Several arguments can share
        # one entry - `validation, split, test` - so the first part is split on commas.
        text <- paste(unlist(lapply(item[[1]], as.character)), collapse = "")
        found <- c(found, trimws(strsplit(text, ",")[[1]]))
      }
    }
  }
  unique(found[nzchar(found)])
}

#' Which help topics document a name as an argument
#'
#' @keywords internal
#' @noRd
argument_locations <- function(db = rd_database()) {
  tag_of <- function(x) {
    tag <- attr(x, "Rd_tag")
    if (is.null(tag)) "" else tag
  }
  found <- list()
  for (topic in names(db)) {
    rd <- db[[topic]]
    tags <- vapply(rd, tag_of, character(1))
    for (block in rd[tags == "\\arguments"]) {
      items <- block[vapply(block, tag_of, character(1)) == "\\item"]
      for (item in items) {
        text <- paste(unlist(lapply(item[[1]], as.character)), collapse = "")
        for (name in trimws(strsplit(text, ",")[[1]])) {
          if (nzchar(name)) {
            found[[name]] <- unique(c(found[[name]], sub("[.]Rd$", "", topic)))
          }
        }
      }
    }
  }
  found
}


#' What each documented argument's entry SAYS, in the Rd a reader sees
#'
#' Keyed by name, taking the longest where a name appears more than once - the same choice
#' `argument_text_lengths()` makes, and that function is `nchar()` over this one rather than
#' a second walk of the database. The markup is flattened, so `\code{"cuda"}` arrives as
#' `"cuda"` with its quotes and without its tag: what a reader is offered, in text.
#'
#' @keywords internal
#' @noRd
argument_texts <- function(db = rd_database()) {
  tag_of <- function(x) {
    tag <- attr(x, "Rd_tag")
    if (is.null(tag)) "" else tag
  }
  found <- list()
  for (rd in db) {
    tags <- vapply(rd, tag_of, character(1))
    for (block in rd[tags == "\\arguments"]) {
      items <- block[vapply(block, tag_of, character(1)) == "\\item"]
      for (item in items) {
        names_text <- paste(unlist(lapply(item[[1]], as.character)), collapse = "")
        body <- trimws(paste(unlist(lapply(item[[2]], as.character)), collapse = ""))
        for (name in trimws(strsplit(names_text, ",")[[1]])) {
          if (nzchar(name)) {
            # Not `%||%`: base R gained that operator in 4.4 and `DESCRIPTION` admits 4.1,
            # so a helper that leans on it would fail on a version this package claims.
            seen <- if (is.null(found[[name]])) "" else found[[name]]
            if (nchar(body) > nchar(seen)) found[[name]] <- body
          }
        }
      }
    }
  }
  found
}


#' How long each documented argument's text is, in the Rd a reader sees
#'
#' Beside `documented_arguments()`, which answers whether a name is documented at all. This
#' answers whether the entry says anything, which is a different question and the one
#' platypus#135's third part is about. Keyed by name, longest where a name appears twice -
#' which is `argument_texts()`'s own choice, so this is that function measured rather than
#' a second traversal that could disagree with it.
#'
#' @keywords internal
#' @noRd
argument_text_lengths <- function(db = rd_database()) {
  lapply(argument_texts(db), nchar)
}


#' The longest description the engine gives each field name, and R's own text for it
#'
#' Keyed by name, taking the longest where a name appears more than once: the question is
#' whether an R reader meeting this name gets something worth reading, and the engine's
#' fullest text is the fair thing to measure against. The Rd half is
#' `argument_text_lengths()`, beside the database it reads.
#'
#' @keywords internal
#' @noRd
prose_lengths <- function() {
  schema <- rplatypus:::engine()$spec_schema()
  engine <- list()
  for (definition in schema$`$defs`) {
    properties <- definition$properties
    if (!length(properties)) next
    for (name in names(properties)) {
      text <- trimws(properties[[name]]$description %||% "")
      if (nzchar(text)) engine[[name]] <- max(c(engine[[name]], nchar(text)))
    }
  }

  r <- argument_text_lengths()
  shared <- intersect(names(engine), names(r))
  list(
    engine = vapply(engine[shared], identity, numeric(1)),
    r = vapply(r[shared], identity, numeric(1))
  )
}
