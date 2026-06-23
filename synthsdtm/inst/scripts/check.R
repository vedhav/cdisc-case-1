#!/usr/bin/env Rscript
# Stage 3: run T1/T2/T3 accuracy checks on generated SDTM datasets.
# Usage: Rscript check.R --config <cfg> --spec <spec> [--ct-cache <ct>]
#                        --run <dir> [--subjects N] [--seed S]
suppressMessages(library(synthsdtm))
a <- parse_cli()
if (is.null(a$config) || is.null(a$spec) || is.null(a$run)) stop("--config, --spec, --run required")
ct <- if (!is.null(a[["ct-cache"]])) a[["ct-cache"]] else list()
n <- if (!is.null(a$subjects)) as.integer(a$subjects) else NULL
seed <- if (!is.null(a$seed)) as.integer(a$seed) else 1234L
rep <- check_sdtm(a$config, a$spec, ct = ct, run_dir = a$run, n_subjects = n, seed = seed)
quit(status = if (isTRUE(rep$allPass)) 0L else 1L)
