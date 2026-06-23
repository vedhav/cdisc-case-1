# CORE rule-id -> category. Extend as new rule ids appear for a new protocol.
.core_category <- c(
  "CORE-000005" = "data_bug",        # EXTRT=PLACEBO but EXDOSE != 0
  "CORE-000657" = "data_bug",        # AEENDTC populated when AEOUT = NOT RECOVERED/NOT RESOLVED
  "CORE-000717" = "data_bug",        # AESTDTC after the last DSSTDTC (AE onset past disposition)
  "CORE-000001" = "data_bug",        # IEORRES != 'N' when IECAT = INCLUSION
  "CORE-000272" = "tabulation_gap",  # MHCAT equals DOMAIN (category convention)
  "CORE-000701" = "tabulation_gap", "CORE-000321" = "tabulation_gap",
  "CORE-000328" = "tabulation_gap", "CORE-000776" = "tabulation_gap",
  "CORE-000793" = "tabulation_gap", "CORE-000852" = "tabulation_gap",
  "CORE-000334" = "tabulation_gap", "CORE-000355" = "tabulation_gap",
  "CORE-001082" = "tabulation_gap", "CORE-000365" = "tabulation_gap",
  "CORE-000767" = "tabulation_gap",
  "CORE-001081" = "harness", "CORE-000929" = "harness",
  "CORE-000238" = "harness", "CORE-000239" = "harness")

#' Export generated SDTM CSVs to SAS Transport (XPT v5)
#'
#' Serialises each `<DOMAIN>.csv` to XPT v5 (what CDISC CORE consumes), coercing
#' numeric variables per the spec dataType and attaching variable labels. Uses
#' [haven::write_xpt()].
#'
#' @param run_dir Directory with the generated `<DOMAIN>.csv`.
#' @param spec Resolved spec (list) or path to `sdtm_spec.json`.
#' @param out_dir Output directory for the `.xpt` files.
#' @return `out_dir`, invisibly.
#' @export
export_xpt <- function(run_dir, spec, out_dir) {
  if (!requireNamespace("haven", quietly = TRUE)) {
    stop("export_xpt() needs the 'haven' package.", call. = FALSE)
  }
  if (is.character(spec)) spec <- jsonlite::read_json(spec, simplifyVector = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  n <- 0L
  for (dom in names(spec$domains)) {
    csv_path <- file.path(run_dir, paste0(dom, ".csv"))
    if (!file.exists(csv_path)) next
    fields <- spec$domains[[dom]]$fields
    num_vars <- vapply(fields, function(f) f$name, character(1))[
      vapply(fields, function(f) identical(f$dataType, "Num"), logical(1))]
    labels <- stats::setNames(vapply(fields, function(f) f$label, character(1)),
                              vapply(fields, function(f) f$name, character(1)))
    df <- utils::read.csv(csv_path, colClasses = "character", check.names = FALSE,
                          na.strings = character(0))
    df[is.na(df)] <- ""
    for (col in names(df)) {
      if (col %in% num_vars) {
        x <- df[[col]]; x[x == ""] <- NA
        df[[col]] <- suppressWarnings(as.numeric(x))
      }
      attr(df[[col]], "label") <- unname(labels[col])
    }
    out_path <- file.path(out_dir, paste0(tolower(dom), ".xpt"))
    haven::write_xpt(df, out_path, version = 5, name = tolower(dom))
    n <- n + 1L
    cat(sprintf("  %s.xpt  %d rows x %d vars\n", tolower(dom), nrow(df), ncol(df)))
  }
  cat(sprintf("\nExported %d SDTM datasets to %s (XPT v5).\n", n, out_dir))
  invisible(out_dir)
}

#' Digest a CDISC CORE JSON report
#'
#' Classifies each rule-finding as `data_bug` (genuine generator inconsistency
#' to fix in the config), `tabulation_gap` (SDTM derivation not implemented), or
#' `harness` (artifact of validating XPT without a Define-XML), and writes a
#' `summary.json`.
#'
#' @param report_path Path to the CORE JSON report.
#' @param out_path Path to write the digest `summary.json`.
#' @return The summary list, invisibly.
#' @export
digest_core <- function(report_path, out_path) {
  rep <- jsonlite::read_json(report_path, simplifyVector = FALSE)
  issues <- rep$Issue_Summary %||% list()
  by_cat <- list()
  findings <- lapply(issues, function(r) {
    cat <- unname(.core_category[r$core_id]); if (is.na(cat)) cat <- "other"
    by_cat[[cat]] <<- (by_cat[[cat]] %||% 0L) + 1L
    list(dataset = r$dataset, coreId = r$core_id, issues = as.integer(r$issues),
         category = cat, message = r$message)
  })
  ord <- order(vapply(findings, function(f) f$category != "data_bug", logical(1)),
               -vapply(findings, function(f) f$issues, integer(1)))
  findings <- findings[ord]
  cd <- rep$Conformance_Details %||% list()
  summary <- list(
    standard = paste(cd$Standard, cd$Version), engineVersion = cd$CORE_Engine_Version,
    rulesWithIssues = length(issues), findingsByCategory = by_cat,
    interpretation = list(
      data_bug = "Genuine generator inconsistency -- fix in the study config and regenerate.",
      tabulation_gap = "SDTM derivation not yet implemented (coding, extra variables, ordering).",
      harness = "Artifact of validating XPT without a Define-XML; not a data-quality issue."),
    findings = findings)
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  write_json_pretty(summary, out_path)
  cat(sprintf("Standard %s  engine %s\n", summary$standard, summary$engineVersion %||% "?"))
  cat("Findings by category:", paste(names(by_cat), unlist(by_cat), sep = "=", collapse = " "), "\n")
  invisible(summary)
}
