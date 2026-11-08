# One `@param` serving two constructors is one sentence making two claims, and nothing read
# either of them. `maju116/rplatypus#304`.
#
# `?losses` documented `gamma` once for `loss_focal()` and `loss_focal_tversky()`, and said
# *"0 is plain cross-entropy and 2 is the usual value"*. Measured against the running engine:
# that is right for `loss_focal()` - `focal(gamma = 0)` and `cross_entropy()` agree to ten
# decimals, and its default IS 2 - and WRONG IN BOTH HALVES for `loss_focal_tversky()`, whose
# default is 1 and whose field is declared `gt=0`, so 0 is refused rather than meaning
# anything. The two gammas are different parameters sharing a name and a help entry.
#
# It was found by the field-prose ledger - the engine rewrote `gamma`'s description in
# `0.8.0a78`, the ledger named the topic, and re-reading the topic is the whole of what that
# step is for. This is the second time that ledger's FIRST answer has produced a finding
# rather than a formality.
#
# What this test holds is the half a reader acts on: a default stated in prose against the
# default the constructor actually has, read off `formals()`. It cannot read the rest of the
# sentence and does not pretend to - the ledger is what guarantees somebody was asked.

test_that("the defaults `?losses` states for gamma are the defaults the constructors have", {
  rd <- test_path("..", "..", "man", "losses.Rd")
  skip_if_not(file.exists(rd), "man/ is not in the installed package")

  text <- paste(readLines(rd, warn = FALSE), collapse = "\n")
  item <- regmatches(text, regexpr("(?s)\\\\item\\{gamma\\}\\{.*?\\}\n\n", text, perl = TRUE))
  # Control: a regex that finds nothing reports no disagreement and passes by looking at
  # nothing, which is this project's commonest instrument failure.
  expect_length(item, 1L)
  expect_gt(nchar(item), 200)

  # Both constructors have to be NAMED in it, or the sentence is about one of them and
  # silently wrong about the other - which is exactly what it was.
  expect_true(grepl("loss_focal()", item, fixed = TRUE))
  expect_true(grepl("loss_focal_tversky()", item, fixed = TRUE))

  # And the numbers. `formals()` is the constructor's own answer rather than a second copy.
  focal_default <- eval(formals(loss_focal)$gamma)
  tversky_default <- eval(formals(loss_focal_tversky)$gamma)
  expect_identical(focal_default, 2)
  expect_identical(tversky_default, 1)

  # The sentence has to say each one somewhere after naming its constructor. Split on the
  # second constructor so each half is checked against its own default rather than against
  # "the prose contains a 2 somewhere", which any wrong sentence satisfies.
  halves <- strsplit(item, "loss_focal_tversky()", fixed = TRUE)[[1]]
  expect_length(halves, 2L)

  # ASKING FOR THE NUMBER THE PROSE CALLS THE DEFAULT, not for a digit anywhere in the half.
  # The first version of this test asked `grepl("\\b1\\b", half)` and SURVIVED the real
  # defect - the half ends "The two agree only at 1", so a bare 1 was there whatever the
  # sentence claimed. §4's check calibrated loosely enough to admit the failure it was
  # written to prevent, found by mutating the thing being fixed rather than something
  # nearby.
  # THE PROSE IS WRITTEN IN A FORM A MACHINE CAN READ, rather than the pattern being bent
  # until it fits the prose. Three earlier versions of this extractor each failed in a
  # different direction on sentences that were correct: a literal space missed "the\ndefault"
  # across an Rd line break, a tight lookahead missed "1 is plain Tversky and is the
  # default", and a loose one picked up the 0 in "0 is plain cross-entropy ... and 2 is the
  # default". A check that has to guess where a number is claimed will keep doing that, so
  # the claim has one phrasing - `the default is N` - and this reads exactly it.
  stated_default <- function(half) {
    flat <- gsub("\\s+", " ", half)
    claimed <- "(?<=the default is )[0-9]+(\\.[0-9]+)?"
    hits <- regmatches(flat, gregexpr(claimed, flat, perl = TRUE))[[1]]
    unique(as.numeric(hits))
  }

  expect_identical(
    stated_default(halves[1]), focal_default,
    info = "?losses's gamma names a default for `loss_focal()` that the constructor does not have"
  )
  expect_identical(
    stated_default(halves[2]), tversky_default,
    info = paste(
      "?losses's gamma names a default for `loss_focal_tversky()` that is not", tversky_default,
      "- it said 2 until maju116/rplatypus#304, which is loss_focal()'s and not this one's"
    )
  )
})

test_that("the two gammas really are different parameters, asked of the engine", {
  skip_if_not(nzchar(Sys.getenv("PLATYPUS_TEST_ENGINE")), "needs the engine")

  # The premise the help text now rests on, measured rather than asserted: one accepts 0 and
  # the other refuses it. If this ever stopped being true the prose above would be wrong in
  # a way no amount of reading it would show.
  invisible(rplatypus:::shim())
  components <- reticulate::import("pyplatypus.spec.components")

  expect_silent(components$FocalLoss(gamma = 0))
  expect_error(components$FocalTverskyLoss(gamma = 0))

  expect_identical(components$FocalLoss()$gamma, 2)
  expect_identical(components$FocalTverskyLoss()$gamma, 1)
})
