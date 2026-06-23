#!/usr/bin/env Rscript
# Stage 3 optional: XPT v5 export + CORE report digest.
# Usage: Rscript export_core.R export --run <dir> --spec <spec> --out <xpt_dir>
#        Rscript export_core.R digest --report <core.json> --out <summary.json>
suppressMessages(library(synthsdtm))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) stop("subcommand required: 'export' or 'digest'")
cmd <- args[[1]]
a <- parse_cli(args[-1])
if (cmd == "export") {
  if (is.null(a$run) || is.null(a$spec) || is.null(a$out)) stop("--run, --spec, --out required")
  export_xpt(a$run, a$spec, a$out)
} else if (cmd == "digest") {
  if (is.null(a$report) || is.null(a$out)) stop("--report and --out required")
  digest_core(a$report, a$out)
} else {
  stop("unknown subcommand: ", cmd)
}
