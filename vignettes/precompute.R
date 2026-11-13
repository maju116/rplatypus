# The vignettes that run something are precomputed.
#
# `configuration.Rmd` is not among them and has no `.Rmd.orig`: it is prose, YAML and R chunks
# with `eval = FALSE`, so there is nothing to run and nothing to keep in step. Its claims are
# checked by tests/testthat/test-guide.R instead, which validates every configuration it shows
# through the engine and asserts every function it names exists.
#
# R CMD check builds vignettes, and one of these trains two models on 5.6 GB of images that a
# CRAN machine does not have and would not want. So the real documents are the .Rmd.orig files,
# knitted here into the .Rmd that ship - which means every number and every figure in a vignette
# came from a real run, rather than being described in prose and hoped for.
#
# Run from the package root:
#
#     PLATYPUS_DSBOWL=/path/to/data_science_bowl \
#     PLATYPUS_BCCD=/path/to/BCCD \
#     PLATYPUS_FIVES=/path/to/fives Rscript vignettes/precompute.R
#
# The volume vignette generates its own data, so it needs nothing but a working engine. Name
# one or more vignettes as arguments to knit only those.
#
# The instance one trains for 40 epochs at 256x256 and borrows published weights for the
# comparison it opens with - about 15 minutes on a GTX 1070, with `num_workers = 4`, which
# is the difference between 17.5 seconds an epoch and 49.6.
#
# The blood-cell one trains a 61.5-million-parameter detector for 150 epochs - about 37
# minutes on a GTX 1070. The retinal one is slower still: 600 fundus photographs at 2048,
# each cut into sixteen tiles, for 15 epochs. Both want the CUDA 12 line of PyTorch on that
# card, which is why every document here calls platypus_use_torch("pascal") - and why that
# function had to start working before this one could be built at all.
#
# The classification one is the cheapest that runs something - the detector is loaded
# rather than trained, and the three classifiers it fits are two minutes each on the same
# card. What it costs instead is disk: it writes about 5,300 crops into `tempdir()`.
#
# The fetal-head one fills 999 drawn annotations into masks before it can start - about 70
# seconds, in R, with no dependency beyond `png` - and then trains at 544x800 for up to 40
# epochs, which is roughly half an hour on the same card. It is the only document here whose
# answer is a length rather than a score, so it is also the only one where the number that
# matters is computed after the engine has finished.

which <- commandArgs(trailingOnly = TRUE)
if (!length(which)) which <- c("data-science-bowl", "instances", "volumes", "blood-cells",
                               "retinal-vessels", "fetal-head", "classification")

if ("data-science-bowl" %in% which) {
  stopifnot(nzchar(Sys.getenv("PLATYPUS_DSBOWL")))
}
if ("instances" %in% which) {
  # The same directory as the one above: this document reads the per-nucleus masks as
  # identities rather than uniting them, so it needs no data the other one does not.
  stopifnot(nzchar(Sys.getenv("PLATYPUS_DSBOWL")))
}
if ("blood-cells" %in% which) {
  stopifnot(nzchar(Sys.getenv("PLATYPUS_BCCD")))
}
if ("classification" %in% which) {
  # The same data as the detection one: it cuts that detector's boxes out and classifies
  # the pieces, so it needs no images the other does not.
  stopifnot(nzchar(Sys.getenv("PLATYPUS_BCCD")))
}
if ("retinal-vessels" %in% which) {
  stopifnot(nzchar(Sys.getenv("PLATYPUS_FIVES")))
}
if ("fetal-head" %in% which) {
  stopifnot(nzchar(Sys.getenv("PLATYPUS_HC18")))
}

# Against the sources, not whatever is installed. The first run of the volume vignette knitted
# happily against platypus 0.2.0 from the user library: half the functions did not exist yet, and
# knitr pasted "could not find function" into the document instead of failing.
pkgload::load_all(".", quiet = TRUE)

# The figures ARE the tarball, and each one ships TWICE: once under `vignettes/figures/` and
# once as a base64 copy inside the self-contained `inst/doc/<name>.html`, which is why every
# row of the per-vignette table reads `html ~ 1.45 x figures`. So a byte saved here is saved
# twice, and on 2026-11-13 that was the difference between `R CMD check --as-cran` reporting
# `Size of tarball: 7770967 bytes` and reporting nothing: R emits that NOTE above
# `_R_CHECK_CRAN_INCOMING_TARBALL_THRESHOLD_`, default 5e6, and CRAN's policy puts
# documentation under the same 5 MB.
#
# This runs HERE rather than over the files once, because knitr writes `figures/*.png` and the
# `![](figures/...)` lines that point at them - so a shrink applied to the shipped `.Rmd` alone
# is undone by the next run of this script, silently, and the next `--as-cran` is what would
# say so.
#
# THE FORMAT IS CHOSEN PER FIGURE BY UNIQUE COLOUR COUNT, NOT BY A QUALITY FLOOR. A PSNR floor
# of 40 dB was tried first and passed a conversion that spoils a figure: `instances-agreement-1`
# as PNG8 scores 40.2 dB while going from 12911 colours to 237, and its dark field turns
# mottled - on microscopy that artefact reads as noise in the data. Colour count splits these
# files cleanly, measured over all 24: 248..3822 for plots and flat overlays against
# 10868..89228 for photographs and microscopy. PNG8 is near-free on the first group and
# posterises the second; JPEG is the other way round - it is BIGGER than PNG on a line plot
# (`volumes-plot-1` 22832 -> 62879) and much smaller on a photograph.
#
# Lossless recompression alone was measured and is not enough: `optipng -o7` over all 28 PNGs
# took the tarball from 7770967 to 7131065, still 1.43x the threshold.
#
# A candidate is kept only when it is SMALLER, so a figure that neither format helps stays the
# lossless PNG - two of the 24 are in that state.
flat_colours <- 4096

shrink_figures <- function(name) {
  tools <- c(identify = "identify", convert = "convert", optipng = "optipng")
  missing <- tools[!nzchar(Sys.which(tools))]
  if (length(missing)) {
    stop("shrink_figures needs ", paste(names(missing), collapse = ", "),
         " on PATH - install ImageMagick and optipng, or the vignettes will knit to a tarball ",
         "CRAN reports as oversized", call. = FALSE)
  }

  knitted <- paste0(name, ".Rmd")
  text <- readLines(knitted, warn = FALSE)
  # Only the figures THIS vignette points at: knitting one document must not rewrite another's.
  refs <- unique(unlist(regmatches(
    text, gregexpr("figures/[A-Za-z0-9._-]+\\.png", text)
  )))
  refs <- refs[file.exists(refs)]
  if (!length(refs)) return(invisible(FALSE))

  renamed <- character(0)
  for (ref in refs) {
    system2("optipng", c("-quiet", "-o7", "-strip", "all", shQuote(ref)))
    before <- file.size(ref)
    colours <- suppressWarnings(as.integer(
      system2("identify", c("-format", "%k", shQuote(ref)), stdout = TRUE)[1]
    ))
    if (is.na(colours)) stop("could not read the colour count of ", ref, call. = FALSE)

    if (colours <= flat_colours) {
      candidate <- paste0(ref, ".png8")
      system2("convert", c(shQuote(ref), "-strip", "-colors", "256", "+dither",
                           shQuote(paste0("PNG8:", candidate))))
      if (file.exists(candidate)) system2("optipng", c("-quiet", "-o7", "-strip", "all",
                                                       shQuote(candidate)))
      if (file.exists(candidate) && file.size(candidate) < before) {
        file.rename(candidate, ref)
      } else if (file.exists(candidate)) {
        unlink(candidate)
      }
    } else {
      candidate <- sub("\\.png$", ".jpg", ref)
      system2("convert", c(shQuote(ref), "-strip", "-quality", "92", shQuote(candidate)))
      if (file.exists(candidate) && file.size(candidate) < before) {
        unlink(ref)
        renamed[ref] <- candidate
      } else if (file.exists(candidate)) {
        unlink(candidate)
      }
    }
  }

  # The references last, so a failure above leaves a document pointing at files that exist.
  if (length(renamed)) {
    for (from in names(renamed)) text <- gsub(from, renamed[[from]], text, fixed = TRUE)
    writeLines(text, knitted)
  }
  message("  figures: ", length(refs), " kept at ",
          format(sum(file.size(c(setdiff(refs, names(renamed)), unname(renamed))))),
          " bytes, ", length(renamed), " as jpeg")
  invisible(TRUE)
}

withr::with_dir("vignettes", {
  for (name in which) {
    message("knitting ", name)
    knitr::knit(paste0(name, ".Rmd.orig"), paste0(name, ".Rmd"))
    shrink_figures(name)
  }
})
