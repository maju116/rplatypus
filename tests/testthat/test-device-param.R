# R's one sentence about `device`, held to the engine's own table of accelerators.
#
# `?platypus_fit`'s `@param device` is a hand-written copy of `pyplatypus.device.BACKENDS`,
# and until `rplatypus#336` it named one of the three. A reader who wanted the Apple GPU was
# offered `"cuda"` or `"cpu"`, on a machine where `platypus_device()` answers `mps` and
# `?platypus_device` explains, two paragraphs long, that this module exists because such a
# Mac once reported `cpu` with a working `mps` backend in the same installation. One of those
# two pages is the one somebody follows.
#
# WHY NOTHING COULD HAVE CAUGHT IT, which is what this file is for rather than the sentence:
# `device` is an argument of the engine's CONSTRUCTOR rather than a specification field, so
# it is not among the 117 names in `fixtures/field-prose.yml` and the ledger - the one
# mechanism here that ever asks whether R's prose still says the right thing - cannot see it.
# One function takes it and one topic documents it, so the shared-`@param` census of `#307`
# does not reach it either. The sentence was unheld prose about a table in another language.
#
# Read off the Rd rather than off `R/fit.R`, for the reason `helper-rd.R` gives: a roxygen
# comment that never regenerated passes a grep over the source and is still absent from the
# page a reader opens.
#
# BOTH DIRECTIONS, because one of them is this file's own subject. A backend the engine
# prefers and the sentence omits is the defect being fixed; a value the sentence offers that
# the engine does not know would send somebody to torch with a name nothing here resolves.
# The quoted values are the closed, parseable part of the sentence, so the comparison is over
# sets rather than over prose - and `"cpu"` is named here rather than read from the engine,
# because the processor is always a legal answer and is not an accelerator.
#
# THE EXTRACTION EXCLUDES ANYTHING WITH PARENTHESES, measured rather than assumed: the
# flattened Rd renders `[platypus_device()]` as `list("platypus_device()")`, so a plain
# "quoted string" reading picks the cross-reference up as a fifth device. A device name has
# no parentheses, which is what makes that exclusion a fact about the subject rather than a
# loosened check - and the cross-reference is asserted separately, so dropping it fails here.
#
# If an example like `"cuda:1"` is ever worth putting in the sentence, this test fails and
# the value is added below with its reason. That is the rule the field-prose ledger states
# for a name collision: one deliberate edit, rather than a check widened until it passes.

test_that("the sentence about `device` offers exactly the devices the engine takes", {
  skip_if_no_engine()

  texts <- argument_texts()
  sentence <- texts[["device"]]
  skip_if(is.null(sentence), "no Rd database reachable from here")

  # Controls first. A sentence that could not be read, or a table of backends that came back
  # empty, would make every comparison below pass by reaching nothing - two empty sets agree
  # about everything.
  expect_gt(nchar(sentence), 120)
  expect_true(grepl("platypus_device", sentence, fixed = TRUE))
  expect_true(grepl("NULL", sentence, fixed = TRUE))

  backends <- as.character(reticulate::py_run_string(
    "from pyplatypus.device import BACKENDS as _platypus_backends"
  )$`_platypus_backends`)
  expect_gte(length(backends), 2)
  expect_true("cuda" %in% backends)

  quoted <- regmatches(sentence, gregexpr('"[^"]+"', sentence))[[1]]
  quoted <- gsub('"', "", quoted, fixed = TRUE)
  offered <- unique(quoted[grepl("^[a-z][a-z0-9:._-]*$", quoted)])
  expect_gte(length(offered), 2)

  expect_setequal(offered, c(backends, "cpu"))
})
