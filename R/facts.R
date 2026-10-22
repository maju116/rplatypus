# Platypus facts, and why a joke in a package about measurement is written like this.
#
# The family is called platypus because the animal is one of the author's favourites, and
# this file is the only thing in the package that is there for that reason alone. It still
# follows the rules the rest of it follows, for one reason: a package whose whole argument
# is that numbers should be measured rather than felt cannot ship a made-up animal fact.
# Platypus folklore is unusually full of claims that are plausible and wrong - the venom,
# the stomach, the gravel, the glow, the word "puggle" - so every entry below carries the
# source it was read from, four of them exist to correct a story rather than to tell one,
# and `tests/testthat/test-facts.R` holds each fact to having one.
#
# THE NUMBER IS AN IDENTITY, NOT A POSITION. "Platypus fact nr 7" has to mean the same
# thing in every version of this package or it cannot be quoted, so this list is appended
# to and never reordered, and nothing is deleted from it - a fact that turns out to be
# wrong is corrected in place, keeping its number. Same reasoning as CLAUDE.md's rule
# about not citing a queue entry by its number, pointed the other way: there the number
# was unstable and the reference broke, here the reference is public so the number is
# pinned.
#
# Checked 2026-10-22. Where sources disagree the entry says so rather than picking the
# roundest number, and where a finding is a candidate rather than a settled answer it is
# worded as one.

platypus_facts <- list(
  list(
    fact = paste(
      "There are five living species of egg-laying mammal: the platypus, the short-beaked",
      "echidna, and three long-beaked echidnas. One of those is named after David",
      "Attenborough."
    ),
    source = "Flannery & Groves (1998), Mammalia 62:367-396; Mammal Diversity Database"
  ),
  list(
    fact = paste(
      "A female lays one to three eggs, usually two, and incubates them for about ten days",
      "curled around them, holding them against her belly with her tail."
    ),
    source = "Australian Museum, australian.museum/learn/animals/mammals/platypus"
  ),
  list(
    fact = paste(
      "A platypus has no nipples. Milk seeps through two patches of skin on the mother's",
      "belly and the young lap it out of the fur, for three to four months."
    ),
    source = "Australian Museum; Enjapoori et al. (2014), PMC4224336"
  ),
  list(
    fact = paste(
      "Because that milk sits in the open where bacteria can reach it, it carries an",
      "antibacterial protein found in no other mammal. Its shape had never been seen",
      "before, and the team that solved it nicknamed the fold 'Shirley Temple', after the",
      "ringlets."
    ),
    source = "Newman et al. (2018), Acta Cryst. F74:39-45; CSIRO"
  ),
  list(
    fact = paste(
      "The platypus is one of very few venomous mammals. Only males are: the spur is on the",
      "hind leg, the gland behind it swells during the breeding season and shrinks after,",
      "so it is thought to be for fighting other males rather than for prey or defence."
    ),
    source = "Australian Platypus Conservancy; Warren et al. (2008), Nature 453:175"
  ),
  list(
    fact = paste(
      "That venom will not kill a person, and it is not a sting to shrug off either: the",
      "pain is severe, lasts for days or longer, and responds poorly to ordinary",
      "painkillers - morphine included."
    ),
    source = "Australian Platypus Conservancy, platypus.asn.au"
  ),
  list(
    fact = paste(
      "'Platypus venom can kill a dog' is repeated everywhere and rests on one hunter's",
      "account. Another hunter's dog was spurred repeatedly and recovered every time."
    ),
    source = "Australian Platypus Conservancy, platypus.asn.au/platypus-myths"
  ),
  list(
    fact = paste(
      "The bill is an electrical antenna. It carries roughly 40,000 electroreceptors that",
      "pick up the faint fields of a shrimp's moving muscles, interleaved with about 60,000",
      "touch receptors. Counts differ between papers; those two are the figures usually",
      "cited."
    ),
    source = "Manger & Pettigrew (1996), Brain Behav. Evol. 48:27; Pettigrew (1999)"
  ),
  list(
    fact = paste(
      "It hunts with its eyes, ears and nostrils all shut. Everything it knows about the",
      "bottom of the creek arrives through the bill."
    ),
    source = "Australian Museum, australian.museum/learn/animals/mammals/platypus"
  ),
  list(
    fact = paste(
      "Its body runs at about 32 degrees Celsius, roughly five below a human's, which is",
      "part of how it affords spending half the day in cold water."
    ),
    source = "Australian Platypus Conservancy, platypus.asn.au/platypus-body-temperature"
  ),
  list(
    fact = paste(
      "'The platypus has no stomach' is almost right and worth getting right. It has a",
      "small pouch of one - with no gastric glands, no acid and no enzymes, only mucus. The",
      "genes for acid secretion and gastric proteases are not switched off but deleted, so",
      "the organ is not coming back."
    ),
    source = "Ordo\u00f1ez et al. (2008), Genome Biol. 9:R81; Australian Platypus Conservancy"
  ),
  list(
    fact = paste(
      "An adult has no teeth. It grinds prey between pads of keratin - and the story that it",
      "swallows gravel to help is a myth: the pads reduce a shrimp to paste on their own,",
      "and the grit in its cheek pouches is just grit."
    ),
    source = "Australian Platypus Conservancy, platypus.asn.au/platypus-myths"
  ),
  list(
    fact = paste(
      "It swims with its front feet alone. The webbed hind feet and the tail do not push -",
      "they steer."
    ),
    source = "Australian Museum, australian.museum/learn/animals/mammals/platypus"
  ),
  list(
    fact = paste(
      "The front claws are never hidden. When it walks on land the webbing folds away under",
      "the palm so the claws can reach the ground, which is not the same thing as webbing",
      "that retracts."
    ),
    source = "Australian Platypus Conservancy, platypus.asn.au/platypus-myths"
  ),
  list(
    fact = "It stores fat in its tail, which is why a healthy platypus has a broad one.",
    source = "Australian Museum, australian.museum/learn/animals/mammals/platypus"
  ),
  list(
    fact = paste(
      "A dive lasts about half a minute - mean 31 seconds, with 72% of dives between 18 and",
      "40 - and it makes around 75 of them an hour, for something like twelve hours a day."
    ),
    source = "Bethge (2002), Energetics and foraging behaviour of the platypus, Univ. Tasmania"
  ),
  list(
    fact = paste(
      "A male platypus has ten sex chromosomes, five X and five Y, which pair up in a chain",
      "at meiosis. It also has no SRY - the gene that decides sex in almost every other",
      "mammal - and what replaces it is still an open question."
    ),
    source = paste(
      "Gr\u00fctzner et al. (2004), Nature 432:913-917;",
      "Rens et al. (2007), Genome Biol. 8:R243"
    )
  ),
  list(
    fact = paste(
      "Its genome, published in 2008, settled where the venom came from: platypus and",
      "reptile venoms were built independently out of the same gene families. The",
      "resemblance is convergence, not a leftover."
    ),
    source = "Warren et al. (2008), Nature 453:175-184, doi:10.1038/nature06936"
  ),
  list(
    fact = paste(
      "Platypus fur fluoresces green under ultraviolet light, found in 2020 on three museum",
      "specimens. Widely reported as bizarre, and it is not: more than 120 mammal species",
      "do it."
    ),
    source = "Anich et al. (2020), Mammalia, doi:10.1515/mammalia-2020-0027"
  ),
  list(
    fact = paste(
      "The animal does not own the name. George Shaw called it Platypus in 1799, the name",
      "was already a beetle's, and it has been Ornithorhynchus ever since. Searching GBIF",
      "for the genus Platypus today returns 144 beetles and no mammal."
    ),
    source = "Shaw (1799); Blumenbach (1800); GBIF species search, read 2026-10-22"
  ),
  list(
    fact = paste(
      "The first specimen sent to London was taken for a fraud - a duck's bill sewn onto a",
      "pelt - and was examined for the stitches that were not there."
    ),
    source = "Shaw (1799), The Naturalist's Miscellany; Natural History Museum"
  ),
  list(
    fact = paste(
      "'Platypi' is wrong. It applies a Latin ending to a word taken from Greek; the plural",
      "is platypuses, or platypus. Platypodes would be defensible and nobody says it."
    ),
    source = "Australian Platypus Conservancy, platypus.asn.au/platypus-names"
  ),
  list(
    fact = paste(
      "There is no accepted word for a baby platypus. 'Nestling' is what the specialists",
      "use; 'puggle' escaped from a zoo's publicity in 2003 and belongs to echidnas anyway."
    ),
    source = "Australian Platypus Conservancy, platypus.asn.au/platypus-names"
  ),
  list(
    fact = paste(
      "It is Near Threatened on the IUCN Red List, and worse where it is worst: Endangered",
      "in South Australia, Vulnerable in Victoria. The trend is down and the numbers are",
      "poorly known, which is its own problem."
    ),
    source = "IUCN Red List (2016 assessment); Australian Platypus Conservancy"
  ),
  list(
    fact = paste(
      "The largest platypus known lived up to 15 million years ago, was about a metre long",
      "and had working teeth. It is described from a single molar, which is all anyone has",
      "of it."
    ),
    source = "Pian, Archer & Hand (2013), J. Vertebr. Paleontol. 33:1255-1259"
  )
)

#' One fact about the platypus
#'
#' The package is named after the animal, and this prints something true about it. It has
#' nothing to do with segmentation.
#'
#' A fact is also printed once when the package is attached, in an interactive session
#' only. To stop that, set `options(rplatypus.facts = FALSE)` in `~/.Rprofile`, or the
#' environment variable `PLATYPUS_FACTS` to `0` or `false` in `~/.Renviron`.
#'
#' Each fact carries the source it was read from, because several of the best-known claims
#' about platypuses are wrong and four of these exist to say which. The numbering is stable
#' across versions: facts are added to the end and never reordered, so a number can be
#' quoted.
#'
#' Picking one at random does **not** disturb the random number stream, which is the only
#' part of this worth any care: `library()` must not change what `set.seed(1)` then
#' produces, and `suppressPackageStartupMessages()` hides the message without preventing
#' the side effect, so avoiding it is the only fix that works.
#'
#' @param number Which fact, from 1 to the number there are. `NULL`, the default, picks one
#'   at random.
#' @return An object of class `platypus_fact`, which prints as the fact and its source.
#' @examples
#' platypus_fact(1)
#' platypus_fact()
#' @export
platypus_fact <- function(number = NULL) {
  n <- length(platypus_facts)
  if (is.null(number)) {
    number <- fact_index(n)
  } else {
    if (!is.numeric(number) || length(number) != 1L || is.na(number)) {
      stop("`number` must be a single number between 1 and ", n,
           ", or NULL for a random one.", call. = FALSE)
    }
    number <- as.integer(number)
    if (number < 1L || number > n) {
      stop("there are ", n, " platypus facts, so `number` must be between 1 and ", n,
           ", not ", number, ".", call. = FALSE)
    }
  }

  entry <- platypus_facts[[number]]
  structure(
    list(number = number, fact = entry$fact, source = entry$source, of = n),
    class = "platypus_fact"
  )
}

#' Pick a fact without touching the caller's random number stream
#'
#' `sample()` advances `.Random.seed`, so a fact chosen at attach time changes what the
#' user's own `set.seed()` produces - measured: `set.seed(1); runif(1)` gives 0.2655087
#' normally and 0.3721239 with one `sample()` call in between. In a package that offers
#' seeded splits and `deterministic = TRUE`, `library()` is the worst possible place for
#' that, and wrapping the call in `suppressPackageStartupMessages()` does not help: the
#' arguments are evaluated before the condition is signalled, so suppressing the output
#' keeps the side effect and removes the evidence.
#'
#' So the seed is saved and put back. The three cases are all safe: a seed that existed is
#' restored byte for byte, a `set.seed()` call afterwards overwrites everything anyway, and
#' a session that never seeded anything had no reproducibility to lose.
#' @keywords internal
#' @noRd
fact_index <- function(n) {
  had_seed <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  if (had_seed) {
    old_seed <- get(".Random.seed", envir = globalenv(), inherits = FALSE)
  }
  on.exit({
    if (had_seed) {
      assign(".Random.seed", old_seed, envir = globalenv())  # nolint: object_name_linter.
    } else {
      suppressWarnings(rm(".Random.seed", envir = globalenv()))
    }
  }, add = TRUE)

  sample.int(n, 1L)
}

#' @export
print.platypus_fact <- function(x, ...) {
  cat(strwrap(
    paste0("Platypus fact nr ", x$number, ": ", x$fact),
    width = 0.9 * getOption("width", 80L)
  ), sep = "\n")
  cat(strwrap(paste0("-- ", x$source), width = 0.9 * getOption("width", 80L),
              prefix = "   ", initial = ""), sep = "\n")
  invisible(x)
}

#' Should a fact be printed when the package is attached?
#'
#' Three conditions, and each one is here because of what it prevents.
#'
#' Interactive only, so it stays out of `R CMD check` logs, CI output, knitr renders and
#' anybody's reverse-dependency check. A fact in a check log is the first thing a reviewer
#' notices and the thing nobody wants to defend.
#'
#' An option for the session and a help page that names it, and an environment variable for
#' the people who want it off for good without an `.Rprofile`. The option wins when both are
#' set, because it is the more specific of the two.
#'
#' `session_interactive` is an argument rather than a call to `interactive()` inside, and
#' that is for the tests rather than for callers: the real check short-circuits first, so
#' with it inlined every assertion about the option and the variable would pass for the one
#' reason that the suite is not interactive - a test that cannot see what it is named after.
#' @keywords internal
#' @noRd
facts_wanted <- function(session_interactive = interactive()) {
  if (!session_interactive) {
    return(FALSE)
  }
  option <- getOption("rplatypus.facts")
  if (!is.null(option)) {
    return(isTRUE(option))
  }
  env <- tolower(trimws(Sys.getenv("PLATYPUS_FACTS", unset = "")))
  !(env %in% c("0", "false", "no", "off"))
}

# `.onAttach` rather than `.onLoad`, which is where this package's other startup work lives
# (`R/bridge.R`). The difference matters here: `.onLoad` also runs for `rplatypus::fun()`,
# so a fact would appear in the middle of a script that never called `library()`.
# `packageStartupMessage` rather than `message` or `cat`, because it is the one
# `suppressPackageStartupMessages()` silences.
#' The startup line, built separately from being printed
#'
#' Factored out so a test can hold the wording to the fact it came from without needing an
#' interactive session or having to capture a condition.
#' @keywords internal
#' @noRd
fact_startup_message <- function(fact) {
  paste(
    c(
      strwrap(paste0("Platypus fact nr ", fact$number, ": ", fact$fact), width = 76L),
      "  (`platypus_fact()` for another, `options(rplatypus.facts = FALSE)` to stop)"
    ),
    collapse = "\n"
  )
}

.onAttach <- function(libname, pkgname) {
  if (!facts_wanted()) {
    return(invisible(NULL))
  }
  packageStartupMessage(fact_startup_message(platypus_fact()))
  invisible(NULL)
}
