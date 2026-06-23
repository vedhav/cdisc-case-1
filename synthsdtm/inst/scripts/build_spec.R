#!/usr/bin/env Rscript
# Stage 1 tail: resolve sdtm_spec.json + ct_cache.json from a study config.
# Usage: Rscript build_spec.R --config <cfg.json> --out <dir> [--ct-snapshot <ct.json>]
suppressMessages(library(synthsdtm))
a <- parse_cli()
if (is.null(a$config) || is.null(a$out)) stop("--config and --out are required")
snap <- if (!is.null(a[["ct-snapshot"]])) a[["ct-snapshot"]] else ct_snapshot_path()
build_spec(a$config, ct_snapshot = snap, out_dir = a$out)
