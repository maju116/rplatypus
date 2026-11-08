# ONE `@param` SERVING SEVERAL FUNCTIONS IS ONE SENTENCE MAKING SEVERAL CLAIMS, and
# `maju116/rplatypus#304` and `#306` are three instances of it going wrong. This is the
# census that found the second and third, kept as a ratchet.
#
# What it CANNOT do is judge the prose, and the measurement says why. Of the seven shared
# items whose functions' defaults differ, two were wrong and five were right, and no
# mechanical signal separates them:
#
#     item                page         functions  names fns  says "default"   verdict
#     monitor             callbacks        4          0          no           right
#     patience            callbacks        3          1          no           right
#     gamma               losses           2          2          yes          fixed, #304
#     alpha               losses           4          0          no           WRONG, #306
#     include_background  metrics          5          2          yes          right
#     eps                 optimizers       7          0          no           right
#     weight_decay        optimizers       8          1          yes          WRONG, #306
#
# A rule of "name at least two of the functions" catches both defects AND condemns
# `monitor`, `patience` and `eps`, which are correct: there the argument means the same
# thing everywhere and only the default differs. §4's check calibrated tightly enough to
# fail on correct content is as useless as a loose one.
#
# So this does what the field-prose ledger does: it guarantees somebody was ASKED. The seven
# are recorded with a reason each, and an eighth - or one of these changing its functions -
# fails here and gets read. That is the whole mechanism, and it is worth having because both
# defects were invisible to `R CMD check`, which is satisfied when an argument is documented
# once.

# The seven, as read on 2026-11-08. A reason rather than a tick, so that a list of
# exemptions cannot become a list nobody re-reads.
known_shared_items <- c(
  "monitor"            = "one meaning, four callbacks; only the default epoch count differs",
  "patience"           = "one meaning, three callbacks; the prose names no default",
  "gamma"              = "two meanings, both stated with their function since #304",
  "alpha"              = "three meanings across four losses, all stated since #306",
  "include_background" = "one meaning, five metrics; the prose states both defaults",
  "eps"                = "one meaning, seven optimisers; the prose states no default",
  "weight_decay"       = "one meaning, eight optimisers; AdamW's 0.01 named since #306"
)

shared_items_disagreeing <- function() {
  exported <- getNamespaceExports("rplatypus")
  found <- character(0)
  for (rd in Sys.glob(testthat::test_path("..", "..", "man", "*.Rd"))) {
    text <- paste(readLines(rd, warn = FALSE), collapse = "\n")
    usage <- regmatches(text, regexpr("(?s)\\\\usage\\{.*?\\n\\}", text, perl = TRUE))
    arguments <- regmatches(text, regexpr("(?s)\\\\arguments\\{.*?\\n\\}\\n", text, perl = TRUE))
    if (!length(usage) || !length(arguments)) next

    heads <- gregexpr("(?m)^([a-zA-Z._][\\w.]*)\\(", usage, perl = TRUE)
    fns <- unique(regmatches(usage, heads)[[1]])
    fns <- intersect(sub("\\($", "", fns), exported)
    if (length(fns) < 2) next

    items <- regmatches(
      arguments, gregexpr("\\\\item\\{([^}]+)\\}", arguments, perl = TRUE)
    )[[1]]
    for (raw in items) {
      name <- sub("^\\\\item\\{", "", sub("\\}$", "", raw))
      # `formals()` is each function's own answer; a second copy of a default would be the
      # very duplication this file is about.
      defaults <- lapply(fns, function(f) {
        fm <- as.list(formals(get(f, envir = asNamespace("rplatypus"))))
        if (!name %in% names(fm)) return(NULL)
        paste(deparse(fm[[name]]), collapse = "")
      })
      defaults <- unlist(Filter(Negate(is.null), defaults))
      if (length(defaults) >= 2 && length(unique(defaults)) > 1) found <- c(found, name)
    }
  }
  sort(unique(found))
}

test_that("every shared `@param` whose functions disagree about the default has been read", {
  skip_if_not(
    length(Sys.glob(testthat::test_path("..", "..", "man", "*.Rd"))) > 10,
    "man/ is not in the installed package"
  )

  found <- shared_items_disagreeing()

  # Control: a scan that finds nothing reports every page clean, which is this project's
  # commonest instrument failure. Seven were there on the day this was written.
  expect_gt(length(found), 4)

  expect_identical(
    setdiff(found, names(known_shared_items)), character(0),
    info = paste(
      "a `@param` documents several functions that disagree about its default and nobody",
      "has read it:", paste(setdiff(found, names(known_shared_items)), collapse = ", "),
      "- read it, decide whether the one sentence is true of every function, and add it to",
      "known_shared_items with the reason. Two of the seven already there were wrong."
    )
  )
  expect_identical(
    setdiff(names(known_shared_items), found), character(0),
    info = paste(
      "these are recorded as read and no longer appear in the census, so the list has",
      "drifted away from the code it is about:",
      paste(setdiff(names(known_shared_items), found), collapse = ", ")
    )
  )
  expect_true(all(nzchar(known_shared_items)))
})
