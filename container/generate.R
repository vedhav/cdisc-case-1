#!/usr/bin/env Rscript
# Step 4 (generate): config -> synthetic SDTM datasets + CORE validation.
#
# Orchestrates the synthsdtm pipeline end to end:
#   build_spec -> simulate_sdtm -> write_sdtm -> check_sdtm
#   -> export_xpt -> `core validate` (best-effort) -> digest_core
# Everything lands under /output so the SDTM datasets are downloadable.
#
# Usage: Rscript generate.R [--config <cfg>] [--out <dir>] [--subjects N] [--seed S]
suppressMessages(library(synthsdtm))
a <- parse_cli()
config   <- if (!is.null(a$config)) a$config else "/workspace/study_config.json"
out      <- if (!is.null(a$out)) a$out else "/output"
seed     <- if (!is.null(a$seed)) as.integer(a$seed) else 1234L
subjects <- if (!is.null(a$subjects)) as.integer(a$subjects) else NULL

if (!file.exists(config)) stop(sprintf("config not found: %s (the build-config step must produce it)", config))
dir.create(out, recursive = TRUE, showWarnings = FALSE)
spec_dir <- file.path(out, "spec")
sdtm_dir <- file.path(out, "sdtm")
xpt_dir  <- file.path(out, "xpt")
core_dir <- file.path(out, "core_report")

message("[1/5] build_spec")
built <- build_spec(config, out_dir = spec_dir)

message("[2/5] simulate_sdtm")
res <- simulate_sdtm(config, built$spec, ct = built$ct_cache, n_subjects = subjects, seed = seed)

message("[3/5] write_sdtm -> ", sdtm_dir)
write_sdtm(res, sdtm_dir)

message("[4/5] check_sdtm")
rep <- tryCatch(
  check_sdtm(config, built$spec, ct = built$ct_cache, run_dir = sdtm_dir, n_subjects = subjects, seed = seed),
  error = function(e) { message("check_sdtm error: ", conditionMessage(e)); list(allPass = NA) }
)

message("[5/5] CORE validation (best-effort)")
core_ran <- tryCatch({
  export_xpt(sdtm_dir, built$spec, xpt_dir)
  dir.create(core_dir, recursive = TRUE, showWarnings = FALSE)
  system2("core",
    c("validate", "-s", "sdtmig", "-v", "3-4", "-d", xpt_dir,
      "-ct", "sdtmct-2026-03-27", "-ca", "resources/cache",
      "-o", file.path(core_dir, "core"), "-of", "JSON", "-l", "error"),
    stdout = TRUE, stderr = TRUE)
  reports <- list.files(core_dir, pattern = "\\.json$", full.names = TRUE)
  if (length(reports) > 0) digest_core(reports[[1]], file.path(core_dir, "summary.json"))
  length(reports) > 0
}, error = function(e) { message("CORE step skipped: ", conditionMessage(e)); FALSE })

summary <- list(
  status = "success",
  studyId = res$config$studyId,
  subjects = res$n,
  seed = res$seed,
  domains = res$summary,
  checkPass = rep$allPass,
  coreRan = core_ran
)
jsonlite::write_json(summary, file.path(out, "result.json"), auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\nGenerated %d SDTM domains, %d rows, %d subjects. check=%s core=%s\n",
            length(res$summary), sum(unlist(res$summary)), res$n,
            as.character(rep$allPass), as.character(core_ran)))
