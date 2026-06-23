#!/usr/bin/env Rscript
# Stage 2: generate synthetic SDTM datasets from a config + spec.
# Usage: Rscript simulate.R --config <cfg> --spec <spec> [--ct-cache <ct>]
#                           [--subjects N] [--seed S] [--domains D1,D2] --out <dir>
suppressMessages(library(synthsdtm))
a <- parse_cli()
if (is.null(a$config) || is.null(a$spec) || is.null(a$out)) stop("--config, --spec, --out required")
ct <- if (!is.null(a[["ct-cache"]])) a[["ct-cache"]] else list()
n <- if (!is.null(a$subjects)) as.integer(a$subjects) else NULL
seed <- if (!is.null(a$seed)) as.integer(a$seed) else 1234L
doms <- if (!is.null(a$domains)) strsplit(a$domains, ",")[[1]] else NULL
res <- simulate_sdtm(a$config, a$spec, ct = ct, n_subjects = n, seed = seed, domains = doms)
write_sdtm(res, a$out)
cat(sprintf("\nGenerated %d SDTM datasets, %d total rows, %d subjects (seed %d).\n",
            length(res$summary), sum(unlist(res$summary)), res$n, res$seed))
