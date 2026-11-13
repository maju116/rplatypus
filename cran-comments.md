# cran-comments

**A resubmission.** `0.3.0` was submitted on 2026-11-13 and the incoming checks returned
**1 ERROR on r-devel-windows**, with r-devel-linux OK. Two tests of `save_class_volumes()`
expected a refusal that the Python engine raises, and did not declare that they need the
engine - so on a machine with a Python and no `pyplatypus` they got
`ModuleNotFoundError: No module named 'pyplatypus'` instead of a message about class names.
They now carry the same skip their neighbours do, and the whole suite was re-run with the
engine made unreachable in order to count whether any other test was in that state: these
two were the only ones, `FAIL 2` before and `FAIL 0` after, with the two moving into the
skip count. Nothing about the package's behaviour changed - the diff is two test lines, one
line of CI configuration so that those jobs are genuinely without Python with a test holding
it there, the version and this file.

**An update.** `rplatypus 0.2.1` is on CRAN, published 2026-11-04; this is `0.3.1`. The
previous version of this file described a first submission and is replaced rather than
amended, because every claim in it that began *"this is a first submission"* stopped being
true on that date.

`NEWS.md` is the record of what changed. The short form, counted inside CRAN's own `0.2.1`
tarball rather than remembered: **95 exported names to 120**, 17 S3 methods to 19, 59 help
pages to 72, and **5 vignettes to 8**. Twenty-five new exported functions is why the minor
version moved rather than the patch one; the patch digit is the resubmission above.

## Test environments

- local: Ubuntu 24.04, R 4.5.3
- GitHub Actions, on every push: Ubuntu (R devel, release, oldrel-1), macOS (release),
  Windows (release)
- CRAN's own daily checks of `0.2.1`, read the day this submission was prepared: **OK on
  all 13 flavours**, with no other status present on the page at all. Enumerated rather
  than counted - four R-devel Linux, R-devel Windows, patched Linux, release Linux, two
  release macOS, release Windows, two oldrel macOS and oldrel Windows - because the last
  time this file described that page only six flavours had reported and the sentence said
  so; they all have now

## R CMD check results

`R CMD check --as-cran`, with the manual, on the maintainer's machine: **no ERRORs, no
WARNINGs, one NOTE**, and it is about this machine rather than about the package.

    * checking HTML version of manual ... NOTE
      Skipping checking HTML validation: no command 'tidy' found.

`tidy` is not installed here and is present on CRAN's machines, so that validation will
actually run there.

Two NOTEs that an earlier draft of this file described are gone, and both absences are a
measurement rather than luck. **`checking CRAN incoming feasibility` now reports nothing at
all.** It carried `Size of tarball: 6170691 bytes` while the documentation outgrew the 5 MB
the policy names; this one is **about 4.5 MB** - comfortably under it - against the
published `0.2.1`'s 3,418,519 bytes, and the difference is how the vignette figures are
stored rather than what they show - each is kept in whichever of PNG, 8-bit PNG or JPEG is
smaller for that picture, which halved them. And **`checking for future file timestamps`**
fires only when this machine cannot reach the time server the check consults; it did not on
this run, and it does not on every run.

The run was made with the manual built (`R_RD4PDF='times,hyper'`, which drops the
`inconsolata` font this machine does not carry). That matters rather than being a detail:
with `--no-manual` LaTeX never reads the `.Rd` files, and LaTeX is the only reader strict
enough to catch, for instance, a Unicode minus sign where a hyphen belongs. One such
character shipped undetected for six releases before a run like this one found it.

## The package name

Kept here because it may become a question again rather than because it is open. The package
was called `platypus` on GitHub from 2020 until 2026-10-14, and `R CMD check --as-cran`
reported a conflict with `Platypus` — unrelated work in immunology, archived from CRAN on
2026-02-02, differing only in case, which archiving does not release. It was renamed rather
than asking for an exception, and `rplatypus` was accepted under that name.

Its former maintainer has since said they intend to return `Platypus` to CRAN. When that
happens, a `--as-cran` run here will report it as a *current* package rather than an archive
entry. The name of this package does not change either way: one name per language, beside the
`pyplatypus` engine on PyPI.

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

  Measured on 2026-10-14, **with the lever controlled in both directions**: under that
  variable `available_weights()` refuses by name, and without it the same call returns three
  rows. So the `OK` is the examples not reaching Python, rather than the variable having had
  no effect - which is the other thing an `OK` there is consistent with.

Nothing in `R CMD check` therefore reaches the network or starts Python. The one thing worth
stating plainly because it would surprise a *user* rather than a check: the first real call
downloads a PyTorch wheel of a few gigabytes, which is documented in `?platypus_status` and in
the README, together with how to point the package at an existing install instead.

`SystemRequirements` names Python (>= 3.11), raised from 3.10 in this version because the
engine's own `requires-python` moved and this package now passes that floor to
`reticulate::py_require()` instead of letting it pick the first interpreter on a candidate
list. It is still not a prerequisite the user installs: it describes the environment the
package provisions for itself.

## Downstream dependencies

**None.** Checked rather than assumed, and with a control, because a zero is the answer a
broken probe gives too: `tools::package_dependencies(reverse = TRUE)` over `Depends`,
`Imports`, `LinkingTo`, `Suggests` and `Enhances` across the 25,696 packages in the index
returns **0** for `rplatypus` and **356** for `reticulate`, with `rplatypus` confirmed
present in that index so the zero is not an unknown name.

So there is nobody the policy's two weeks' notice is owed to, and no maintainer has been
contacted because there is none to contact.
