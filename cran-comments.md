# cran-comments

Resubmission of `rplatypus` as `0.2.1`, after Konstanze Lauseker's review of `0.2.0`. Still
a new submission - nothing of this package has been accepted - so the *New submission* NOTE
below is expected.

## What changed, and nothing else did

Both points from the review, and only those two. The version is increased as the policy
asks even though `0.2.0` was not accepted.

**Software names in single quotes in `Title` and `Description`.** `Description` now writes
`'PyTorch'` and `'Python'`; `'pyplatypus'` already carried them. `Title` names no software.
`R` itself is left unquoted, following CRAN's own cookbook, whose Title Case example is
*Web Application Framework for R*.

**`\value` in `colormaps.Rd`.** That page documents four exported objects rather than
functions - two colormaps and their label vectors - so it had `\format` and no `\value`.
It now says what each object is structurally and what it means: that `binary_colormap` and
`voc_colormap` are lists of integer vectors of length three, one RGB triple per class, 2
and 21 of them, with position in the list the class index counting from 1; and that
`binary_labels` and `voc_labels` are character vectors of the matching names, the same
length and in the same order, so the nth label names the class the nth triple draws. The
tag is written in the roxygen source, so the `.Rd` file and the code cannot drift apart.

Worth reporting rather than hiding: **`R CMD check --as-cran` here never flagged the missing
tag**, on R 4.5.3 with the manual built, and neither did `tools:::checkRdContents()`. The
two other pages in the package without `\value` - `encoders.Rd` and
`platypus_conditions.Rd` - are topic pages with no `\usage` at all, which is why the review
named one file and not three. A check that reproduces the rule, rather than any tool here,
now reports zero pages with `\usage` and no `\value`.

## Test environments

- local: Ubuntu 24.04, R 4.5.3
- GitHub Actions, on every push: Ubuntu (R devel, release, oldrel-1), macOS (release),
  Windows (release)

## R CMD check results

`R CMD check --as-cran`, with the manual, on the maintainer's machine: **no ERRORs, no
WARNINGs, three NOTEs**, and none of the three is a finding about the package.

    * checking CRAN incoming feasibility ... NOTE
      Maintainer: 'Michal Maj <michalmaj116@gmail.com>'
      New submission

    * checking for future file timestamps ... NOTE
      unable to verify current time

    * checking HTML version of manual ... NOTE
      Skipping checking HTML validation: no command 'tidy' found.

The first is expected of a first submission. The second is this machine being unable to
reach the time server the check consults. The third is a local tool that is not installed
here; it is present on CRAN's machines, so the HTML validation will actually run there.

The run was made with the manual built (`R_RD4PDF='times,hyper'`, which drops the
`inconsolata` font this machine does not carry). That matters rather than being a detail:
with `--no-manual` LaTeX never reads the `.Rd` files, and LaTeX is the only reader strict
enough to catch, for instance, a Unicode minus sign where a hyphen belongs. One such
character shipped undetected for six releases before a run like this one found it.

## The package name

This file previously described a conflict and promised to resubmit under another name if it
could not be resolved. **That is what this name is.** The package was called `platypus` on
GitHub from 2020 until 2026-10-14; `R CMD check --as-cran` reported a conflict with
`Platypus`, archived from CRAN on 2026-02-02 - unrelated work in immunology, last released
2024-10-18 - and the two differed only in case, which the policy treats as a conflict and
which archiving does not release. Rather than ask for an exception or wait on a name that is
still reserved, the package was renamed.

`rplatypus` appears in neither the current index nor the archive, checked against both. The
name also says what the package is: the computation lives in a Python package, `pyplatypus`,
and this is its R surface - one name per language rather than one name reused.

The GitHub repository was renamed with it, so the URLs in `DESCRIPTION` are the current ones
and the former addresses redirect.

## This package calls Python, and provisions it itself

The computation lives in a Python package, `pyplatypus`, reached through `reticulate`. A
reviewer will reasonably want to know what that does on a machine with no Python and no
network, so:

- **`library(rplatypus)` starts nothing.** The import is wrapped in `reticulate`'s
  `delay_load`, so attaching the package is instant, works offline, and works where no Python
  exists. The engine starts on the first call that needs it.
- **No system Python is touched.** `reticulate::py_require()` declares one exact version of
  `pyplatypus` and `uv` builds an isolated ephemeral environment for it. Nothing is installed
  into a user's Python, and no `PATH` Python is modified or required.
- **Every test that needs the engine skips without it.** On a machine where the engine cannot
  start, the tests that need it skip and the rest pass; `checking tests ... OK` in the run
  above was produced exactly that way, with the engine never started. No assertion count is
  quoted here on purpose - this file is outside the package and nothing holds a number in it
  to a measurement, and the one it used to quote had been wrong for several releases.
- **The vignettes do not compute.** Each one that trains a model is precomputed from an
  `.Rmd.orig` on the maintainer's machine and ships as a static `.Rmd`, so building the
  vignettes on a CRAN machine renders prose and runs no model. `vignettes/precompute.R`
  documents how they are regenerated.
- **Examples that need the engine are wrapped in `\dontrun{}`**, which was verified by making
  Python unavailable rather than by it happening to be absent: with
  `RETICULATE_PYTHON=/nonexistent/python`, every expression that runs in an example still
  returns - the specification constructors, the colormap and mask helpers, `drawing_style()`,
  `ct_windows()` - and the one function that does need the engine, `available_weights()`, is
  inside `\dontrun{}` already. `checking examples ... OK` on a machine that *has* Python does
  not establish that; this does.

Nothing in `R CMD check` therefore reaches the network or starts Python. The one thing worth
stating plainly because it would surprise a *user* rather than a check: the first real call
downloads a PyTorch wheel of a few gigabytes, which is documented in `?platypus_status` and in
the README, together with how to point the package at an existing install instead.

`SystemRequirements` names Python 3.10 for completeness, though it is not a prerequisite the
user installs.

## Downstream dependencies

None. `rplatypus` has no reverse dependencies: nothing of it is on CRAN yet.
