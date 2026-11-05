# cran-comments

**An update.** `rplatypus 0.2.1` is on CRAN, published 2026-11-04; this is `0.3.0`. The
previous version of this file described a first submission and is replaced rather than
amended, because every claim in it that began *"this is a first submission"* stopped being
true on that date.

`NEWS.md` is the record of what changed. The short form, measured against the published
tarball rather than remembered: **95 exported names to 120**, 17 S3 methods to 19, and **5
vignettes to 7**. Twenty-five new exported functions is why the version is `0.3.0` rather
than `0.2.2`.

## Test environments

- local: Ubuntu 24.04, R 4.5.3
- GitHub Actions, on every push: Ubuntu (R devel, release, oldrel-1), macOS (release),
  Windows (release)
- CRAN's own daily checks of `0.2.1`, read before preparing this submission: **OK on all
  six flavours that have reported** - both Fedora R-devels and four macOS - with no other
  status present on the page at all. The Windows and Linux r-release and r-oldrel flavours
  had not yet reported, which is the *"at least 48 hours after a publication"* the policy
  describes

## R CMD check results

`R CMD check --as-cran`, with the manual, on the maintainer's machine: **no ERRORs, no
WARNINGs, three NOTEs**, and none of the three is a finding about the package.

    * checking CRAN incoming feasibility ... NOTE
      Maintainer: 'Michal Maj <michalmaj116@gmail.com>'
      Days since last update: <n>
      Size of tarball: 6170691 bytes

    * checking for future file timestamps ... NOTE
      unable to verify current time

    * checking HTML version of manual ... NOTE
      Skipping checking HTML validation: no command 'tidy' found.

The first NOTE's first two lines are about the submission rather than the package, and the
*Days since last update* line is arithmetic against the day the check was run.

**The size line is worth a word, because it is new.** The published `0.2.1` tarball is
3,418,519 bytes and this one is 6,170,691, so this is the first version of this package to
pass the 5 MB the policy names. **No data is shipped.** It is documentation: seven vignettes,
each one precomputed from an `.Rmd.orig` so that no model is trained on a CRAN machine, and
`inst/doc`'s rendered HTML embeds the figures it shows, so each figure is carried once as a
file and once inside the page that displays it. Measured on this tarball: `inst/doc` 3.6 MB,
`vignettes/` 2.4 MB, `man/figures` 1.1 MB.

The second NOTE is this machine being unable to reach the time server the check consults, and
it does not fire on every run. The third is a local tool that is not installed here; it is
present on CRAN's machines, so the HTML validation will actually run there.

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

`SystemRequirements` names Python 3.10 for completeness, though it is not a prerequisite the
user installs.

## Downstream dependencies

**None.** Checked rather than assumed, and with a control, because a zero is the answer a
broken probe gives too: `tools::package_dependencies(reverse = TRUE)` over `Depends`,
`Imports`, `LinkingTo`, `Suggests` and `Enhances` across the 25,608 packages in the index
returns **0** for `rplatypus` and **354** for `reticulate`, with `rplatypus` confirmed
present in that index so the zero is not an unknown name.

So there is nobody the policy's two weeks' notice is owed to, and no maintainer has been
contacted because there is none to contact.
