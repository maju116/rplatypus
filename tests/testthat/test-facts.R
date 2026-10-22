# The platypus facts, and the one thing about them that is not a joke.
#
# Three of these tests are about the easter egg being harmless rather than about it being
# funny, and the first is the only one that guards something that would actually cost a
# user something: a fact chosen at attach time must not move the random number stream.

test_that("choosing a fact does not disturb the caller's random number stream", {
  # This is the whole reason `fact_index()` exists instead of a `sample()` call. Measured
  # before it was written: one `sample()` between `set.seed(1)` and `runif(1)` changes the
  # answer from 0.2655087 to 0.3721239, and in a package that offers seeded splits and
  # `deterministic = TRUE`, `library()` is the worst place in the world for that.
  set.seed(1)
  without <- runif(1)

  set.seed(1)
  invisible(platypus_fact())
  with_fact <- runif(1)

  expect_identical(with_fact, without)

  # The seed object itself, not just the next number out of it.
  set.seed(42)
  before <- get(".Random.seed", envir = globalenv(), inherits = FALSE)
  invisible(platypus_fact())
  expect_identical(get(".Random.seed", envir = globalenv(), inherits = FALSE), before)

  # THE POSITIVE CONTROL, without which the three assertions above pass on a package that
  # has no randomness in it at all and prove nothing. This is the implementation that was
  # not used, and it has to fail.
  set.seed(1)
  invisible(sample.int(length(rplatypus:::platypus_facts), 1L))
  naive <- runif(1)
  expect_false(identical(naive, without))
})

test_that("a fact leaves no seed behind in a session that never had one", {
  # The other half of the same promise, and the case the assertions above cannot see,
  # because a test suite has a seed by the time it gets here. A session that never seeded
  # anything must not acquire a `.Random.seed` by attaching this package: that would make
  # the *next* `runif()` draw from a stream the easter egg started.
  had <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  if (had) {
    keep <- get(".Random.seed", envir = globalenv(), inherits = FALSE)
    on.exit(assign(".Random.seed", keep, envir = globalenv()),  # nolint: object_name_linter.
            add = TRUE)
    rm(".Random.seed", envir = globalenv())
  }

  invisible(rplatypus:::fact_index(10L))
  expect_false(exists(".Random.seed", envir = globalenv(), inherits = FALSE))
})

test_that("nothing is printed when the package is attached non-interactively", {
  # Where a stray startup message actually hurts: `R CMD check` logs, CI output, knitr
  # renders, and other people's reverse-dependency checks.
  expect_false(rplatypus:::facts_wanted(session_interactive = FALSE))
  expect_silent(rplatypus:::.onAttach("lib", "rplatypus"))
})

test_that("the option and the environment variable both turn facts off", {
  # Each assertion passes `session_interactive = TRUE`, because the real check
  # short-circuits on `interactive()` and the suite is not: without the argument every line
  # here would pass for that one reason and say nothing about the option.
  withr::local_options(list(rplatypus.facts = NULL))
  withr::local_envvar(list(PLATYPUS_FACTS = NA))
  expect_true(rplatypus:::facts_wanted(session_interactive = TRUE))

  withr::local_options(list(rplatypus.facts = FALSE))
  expect_false(rplatypus:::facts_wanted(session_interactive = TRUE))

  withr::local_options(list(rplatypus.facts = NULL))
  for (off in c("0", "false", "FALSE", "no", "off", " off ")) {
    withr::local_envvar(list(PLATYPUS_FACTS = off))
    expect_false(
      rplatypus:::facts_wanted(session_interactive = TRUE),
      info = paste0("PLATYPUS_FACTS=", off, " should silence the fact")
    )
  }

  # And the option wins over the variable, which is the one interaction worth pinning.
  withr::local_envvar(list(PLATYPUS_FACTS = "0"))
  withr::local_options(list(rplatypus.facts = TRUE))
  expect_true(rplatypus:::facts_wanted(session_interactive = TRUE))
})

test_that("every fact has a source, because several of these correct a popular claim", {
  facts <- rplatypus:::platypus_facts
  expect_gt(length(facts), 20)

  for (i in seq_along(facts)) {
    expect_true(
      is.character(facts[[i]]$fact) && nzchar(trimws(facts[[i]]$fact)),
      info = paste("fact", i, "has no text")
    )
    expect_true(
      is.character(facts[[i]]$source) && nzchar(trimws(facts[[i]]$source)),
      info = paste("fact", i, "has no source - every one of these was read somewhere")
    )
  }

  # Nothing says the same thing twice, which is the way a hand-written list of 25 goes
  # wrong - and the way it goes wrong silently.
  texts <- vapply(facts, `[[`, character(1), "fact")
  expect_identical(texts[duplicated(texts)], character(0))
})

# The numbering is published the moment somebody quotes "Platypus fact nr 7", so it is an
# identity and not a position: facts are appended and never reordered, and a fact that
# turns out to be wrong is corrected in place keeping its number.
#
# This is the ledger that holds that, and it is the first 24 characters rather than the
# whole text on purpose. A reorder moves every anchor and fails loudly; a correction to the
# body of a fact - which is allowed and expected - touches nothing here. A correction to
# the opening of one has to be made twice, which is the right amount of friction for
# rewriting the first line of a published fact.
#
# Same idea as `tests/testthat/fixtures/field-prose.yml`, at a twenty-fifth of the size.
fact_anchors <- c(
  "There are five living sp",
  "A female lays one to thr",
  "A platypus has no nipple",
  "Because that milk sits i",
  "The platypus is one of v",
  "That venom will not kill",
  "'Platypus venom can kill",
  "The bill is an electrica",
  "It hunts with its eyes, ",
  "Its body runs at about 3",
  "'The platypus has no sto",
  "An adult has no teeth. I",
  "It swims with its front ",
  "The front claws are neve",
  "It stores fat in its tai",
  "A dive lasts about half ",
  "A male platypus has ten ",
  "Its genome, published in",
  "Platypus fur fluoresces ",
  "The animal does not own ",
  "The first specimen sent ",
  "'Platypi' is wrong. It a",
  "There is no accepted wor",
  "It is Near Threatened on",
  "The largest platypus kno"
)

test_that("the fact numbers are stable, because they get quoted", {
  facts <- rplatypus:::platypus_facts
  expect_identical(
    vapply(facts, function(f) substr(f$fact, 1, 24), character(1)),
    fact_anchors,
    info = paste(
      "a fact moved. Facts are appended and never reordered - 'Platypus fact nr 7' has to",
      "mean one thing. If a fact's opening was deliberately rewritten, update the anchor"
    )
  )
})

test_that("platypus_fact() returns the fact it was asked for", {
  facts <- rplatypus:::platypus_facts

  one <- platypus_fact(1)
  expect_s3_class(one, "platypus_fact")
  expect_identical(one$number, 1L)
  expect_identical(one$fact, facts[[1]]$fact)
  expect_identical(one$of, length(facts))

  last <- platypus_fact(length(facts))
  expect_identical(last$fact, facts[[length(facts)]]$fact)

  # A double, because `platypus_fact(7)` is what anybody types.
  expect_identical(platypus_fact(7)$number, 7L)

  random <- platypus_fact()
  expect_s3_class(random, "platypus_fact")
  expect_true(random$number %in% seq_along(facts))
})

test_that("an impossible fact number is refused and says what the range is", {
  n <- length(rplatypus:::platypus_facts)
  expect_error(platypus_fact(0), "between 1 and")
  expect_error(platypus_fact(n + 1), paste0("between 1 and ", n))
  expect_error(platypus_fact("seven"), "must be a single number")
  expect_error(platypus_fact(c(1, 2)), "must be a single number")
  expect_error(platypus_fact(NA), "must be a single number")
})

test_that("printing a fact shows its number and its source", {
  # The source is compared against the entry it came from rather than against a word
  # written out here, and that is not tidiness. The first version of this test asserted
  # the printed output matched "GBIF" - and fact 20's own text says "Searching GBIF", so
  # the assertion passed whether or not the source line was printed at all. Measured:
  # deleting the source line from `print()` left this test green. §4's probe answering a
  # question adjacent to the one it is named after, in its cheapest form.
  squish <- function(x) gsub("[[:space:]]+", " ", trimws(x))

  for (number in c(1L, 11L, 20L, 25L)) {
    entry <- rplatypus:::platypus_facts[[number]]
    printed <- squish(paste(capture.output(print(platypus_fact(number))), collapse = " "))

    expect_match(printed, paste0("Platypus fact nr ", number), fixed = TRUE)
    expect_true(
      grepl(squish(entry$fact), printed, fixed = TRUE),
      info = paste("the text of fact", number, "is not in what print() wrote")
    )
    expect_true(
      grepl(squish(entry$source), printed, fixed = TRUE),
      info = paste("the source of fact", number, "is missing, and it is half the point")
    )
  }
})

test_that("the startup line carries the fact it was built from", {
  fact <- platypus_fact(11)
  line <- rplatypus:::fact_startup_message(fact)
  expect_match(line, "Platypus fact nr 11")
  expect_match(line, "gastric")
  expect_match(line, "rplatypus.facts", info = "the startup line has to say how to stop it")
  # Wrapped, so it does not run off the side of a terminal.
  expect_true(all(nchar(strsplit(line, "\n", fixed = TRUE)[[1]]) <= 80))
})

test_that("no fact is too long to read in a terminal", {
  # A startup message is one or two lines of somebody else's screen, uninvited.
  widths <- vapply(rplatypus:::platypus_facts, function(f) nchar(f$fact), integer(1))
  expect_true(
    all(widths <= 320),
    info = paste("fact", which(widths > 320)[1], "is too long for a startup line")
  )
})
