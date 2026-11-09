# THE DOTS A GENERIC REQUIRES ARE NOT A PLACE TO PUT ARGUMENTS, and until
# `maju116/rplatypus#315` nothing here said so: eight exported functions and methods took
# `...` and no body read one, so `predict(fit, splt = "test")` predicted on the default
# split and said nothing. The wrong answer is a correct answer to a different question,
# which is why this is held as a CLASS rather than as eight assertions.
#
# The census below is the ratchet. The behavioural tests under it are what makes the census
# a reading rather than a grep: a function could satisfy it by naming `...` in a comment.
#
# `#314` is the same class with a real argument rather than a typo - `evaluate_cases()` had
# no `decode`, so an instance model's per-case table could only ever be the first
# decoding's and `decode = "watershed"` was swallowed.

# The exemptions, with a reason each, so that a list of things deliberately not covered
# cannot quietly become a list nobody re-reads. This is the shape `test-shared-param-census.R`
# uses for the same reason.
dots_are_the_generics <- c(
  "evaluate"         = "a generic: its body is UseMethod(), and dispatch forwards the dots",
  "evaluate_cases"   = "a generic, as above",
  "evaluate_classes" = "a generic, as above",
  "evaluate_images"  = "a generic, as above"
)

# R or its own machinery calls a `print` or `as.list` method, so a dots check there can fire
# on a call the user did not make. That is where the reviewer drew the line and it is the
# right one: the gain would be a typo caught and the cost is autoprint refusing.
#
# A RULE rather than a list, because the reason is universal and a list of names drifts -
# which this file demonstrated on its own first run: the first version named five print
# methods and the package has eleven.
printer_exempt <- function(names) grepl("^(print|format|as\\.list)\\.", names)
printers_reason <- paste("R or its own machinery calls these, so a check could fire on a",
                         "call the user did not make")

# ASKED OF THE NAMESPACE, NOT OF THE NAMESPACE FILE. The first version read `NAMESPACE`
# through `test_path("..", "..")`, which is a path that exists in a source tree and not in
# the checked tarball - so gates 1, 2 and 4 were green and `R CMD check` on the built
# package was the one that failed, with `cannot open the connection`. §4's *installed is not
# source is not a fresh checkout*, in the one gate that reproduces what ships.
#
# `getNamespaceInfo(ns, "S3methods")` is the namespace's own register of the methods it
# declares - 19 of them, which is the figure `CLAUDE.md` §1 counts - and it answers wherever
# the package is loaded from.
surfaces_with_dots <- function() {
  ns <- asNamespace("rplatypus")
  registered <- getNamespaceInfo(ns, "S3methods")
  methods <- if (is.null(dim(registered))) character(0) else registered[, 3]
  named <- unique(c(getNamespaceExports("rplatypus"), methods))
  named <- Filter(function(n) {
    exists(n, envir = ns, inherits = FALSE) && is.function(get(n, envir = ns))
  }, named)
  Filter(function(n) "..." %in% names(formals(get(n, envir = ns))), named)
}

test_that("the census finds the surfaces at all, or every assertion below is about nothing", {
  withdots <- surfaces_with_dots()
  # Two empty sets compare equal, which is the form this failure takes when nothing
  # controls it - and `print` methods alone guarantee the count cannot be zero.
  expect_gt(length(withdots), 8)
  expect_true("predict.platypus_fit" %in% withdots)
})

test_that("every surface taking `...` either reads them, checks them, or is exempt with a reason", {
  ns <- asNamespace("rplatypus")
  verdict <- vapply(surfaces_with_dots(), function(n) {
    source <- deparse(body(get(n, envir = ns)))
    if (any(grepl("check_dots_empty", source, fixed = TRUE))) "checked"
    else if ("..." %in% all.names(body(get(n, envir = ns)))) "read"
    else "SWALLOWED"
  }, character(1))

  swallowed <- names(verdict)[verdict == "SWALLOWED"]
  exempt <- c(names(dots_are_the_generics), swallowed[printer_exempt(swallowed)])
  expect_identical(
    setdiff(swallowed, exempt), character(0),
    info = paste(
      "these take `...` and neither read nor check them, so a misspelt argument to one is",
      "swallowed:", paste(setdiff(swallowed, exempt), collapse = ", "),
      "- either check the dots or add the name above with the reason it is exempt"
    )
  )
  # The other direction: an exemption naming something the census no longer finds is a list
  # drifting away from the code it is about.
  expect_identical(
    setdiff(names(dots_are_the_generics), names(verdict)), character(0),
    info = "an exemption names a surface the census no longer finds"
  )
  # And the printer rule has to match something, or it is exempting nothing and the
  # assertion above is weaker than it reads.
  expect_gt(sum(printer_exempt(names(verdict))), 5)
  expect_true(all(nzchar(dots_are_the_generics)) && nzchar(printers_reason))
})

# ---------------------------------------------------------------- the behaviour
# A stub is enough, and that is the point of putting the check FIRST in each body: it fires
# before any refusal the method makes about the task, so a typo is reported as a typo rather
# than sending the reader to a sentence about classification.
stub_fit <- function(task = "semantic_segmentation") {
  structure(list(task = task, models = "m", engine = NULL), class = "platypus_fit")
}

test_that("a misspelt argument is refused by every method that takes the dots for a generic", {
  fit <- stub_fit()
  expect_error(evaluate(fit, splt = "test"), "splt")
  expect_error(evaluate_cases(fit, splt = "test"), "splt")
  expect_error(evaluate_classes(fit, splt = "test"), "splt")
  expect_error(evaluate_images(fit, splt = "test"), "splt")
  expect_error(predict(fit, splt = "test"), "splt")
  expect_error(plot(fit, metricz = "dice"), "metricz")
  expect_error(summary(structure(data.frame(x = 1), class = c("platypus_cases", "data.frame")),
                       digitz = 2), "digitz")
})

test_that("a misspelling that is a PREFIX of a real argument still binds, and that is R", {
  # The limit of this whole repair, measured rather than reasoned about, and it is what made
  # the first draft of the test above fail: R matches a supplied name to a formal it is a
  # prefix of, BEFORE anything reaches `...`. So `plot(fit, metric = )` sets `metrics` and
  # the dots are empty, and no check anywhere can see it.
  #
  # `splt` is not a prefix of `split`, which is why the typos above do reach the dots. The
  # rule a reader needs is therefore narrower than *a misspelt argument is refused*: a
  # misspelling that is not a prefix of a formal is refused, and one that is becomes the
  # argument it prefixes. Held here so that the promise in the help pages is not read wider
  # than it is.
  probe <- function(metrics = NULL, ...) list(metrics = metrics, dots = ...length())
  expect_identical(probe(metric = "dice")$metrics, "dice")
  expect_identical(probe(metric = "dice")$dots, 0L)
  expect_identical(probe(metricz = "dice")$dots, 1L)
})

test_that("`detection_crops()` refuses one through R's own `unused argument`", {
  # It is a plain export rather than a method, so nothing requires the dots and R's own
  # message is better than any check. Asserted because dropping an argument from a released
  # signature is a decision, not a tidy-up.
  expect_false("..." %in% names(formals(detection_crops)))
  # `nonesuch` rather than `siz`, because `siz` is a prefix of `size` and R would bind it.
  expect_error(detection_crops(stub_fit("object_detection"), nonesuch = 32), "unused argument")
})

test_that("`decode` is refused by name off an instance fit, rather than ignored", {
  # `#314`. `predict.platypus_fit` carries the same refusal for the same reason, and its
  # comment records that the detection branch used to return before reaching it.
  expect_error(evaluate_cases(stub_fit("object_detection"), decode = "watershed"),
               "only an instance model")
  expect_error(evaluate_cases(stub_fit("semantic_segmentation"), decode = "watershed"),
               "This fit is semantic_segmentation")
})

test_that("`decode` crosses the bridge, and a wrong name is the ENGINE's refusal", {
  # The end-to-end half, and the only one that can show the forward landed: R's own refusal
  # fires for non-instance tasks ONLY, so on an instance fit a bad decoding name can be
  # refused by nothing but the engine. A test that stopped at R's side would pass with the
  # argument still dropped on the floor.
  skip_if_no_engine()
  root <- tiny_instance_dataset()
  spec <- tiny_instance_spec(
    root,
    decode = list(decode_nearest_seed(), decode_connected_components())
  )
  fit <- platypus_fit(spec, num_workers = 0)

  # The default is the model's first decoding, which is the engine's own default.
  expect_s3_class(evaluate_cases(fit), "platypus_cases")
  # The second decoding is now askable, which is the whole of `#314`.
  expect_s3_class(evaluate_cases(fit, decode = "connected_components"), "platypus_cases")
  # And a name the model does not have is refused by the engine, naming it - which is what
  # proves the string reached the other side rather than being swallowed here.
  expect_error(evaluate_cases(fit, decode = "nonsense"), "nonsense")
})
