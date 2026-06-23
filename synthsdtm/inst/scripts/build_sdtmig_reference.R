#!/usr/bin/env Rscript
# Convert the authoritative "SDTMIG v3.4 Classes and Columns.xlsx" into the bundled
# JSON variable reference that synthsdtm's sdtmig_template() reads.
#
# This is the single source of truth for SDTMIG 3.4 variable metadata: one entry per
# domain, every column in published order, each carrying its label, type, role, Core
# status (Req/Exp/Perm), and CDISC CT codelist NCIt code(s). Regenerate whenever the
# spreadsheet is updated:
#
#   Rscript inst/scripts/build_sdtmig_reference.R \
#       "../SDTMIG v3.4 Classes and Columns.xlsx" \
#       inst/extdata/sdtmig/sdtmig_3.4_variables.json
#
# Requires the 'readxl' and 'jsonlite' packages.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("usage: build_sdtmig_reference.R <classes-and-columns.xlsx> <out.json>", call. = FALSE)
}
xlsx_path <- args[[1]]
out_path  <- args[[2]]

if (!requireNamespace("readxl", quietly = TRUE)) {
  stop("This script needs the 'readxl' package.", call. = FALSE)
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a)) b else a

# Trim + treat blank/NA as "" so cell types (numeric, date, logical) never break str ops.
cell <- function(x) {
  if (length(x) == 0 || is.na(x)) "" else trimws(as.character(x))
}

sheets <- readxl::excel_sheets(xlsx_path)
domains <- list()
for (sheet in sheets) {
  m <- regmatches(sheet, regexec("- ([A-Z]+) \\(", sheet))[[1]]
  if (length(m) < 2) next
  dom <- m[[2]]

  df <- readxl::read_excel(xlsx_path, sheet = sheet, col_types = "text", .name_repair = "minimal")
  need <- c("Variable Order", "Class", "Variable Name", "Variable Label",
            "Type", "CDISC CT Codelist Code(s)", "Role", "Core")
  missing <- setdiff(need, names(df))
  if (length(missing)) stop("sheet '", sheet, "' missing columns: ", toString(missing), call. = FALSE)

  cls <- NA_character_
  vars <- list()
  for (i in seq_len(nrow(df))) {
    name <- cell(df[["Variable Name"]][i])
    if (name == "") next
    if (is.na(cls)) cls <- cell(df[["Class"]][i])
    codelist <- cell(df[["CDISC CT Codelist Code(s)"]][i])
    codes <- regmatches(codelist, gregexpr("C[0-9]+", codelist))[[1]]
    vars[[length(vars) + 1L]] <- list(
      order = as.integer(cell(df[["Variable Order"]][i])),
      name = name,
      label = cell(df[["Variable Label"]][i]),
      type = cell(df[["Type"]][i]),
      role = cell(df[["Role"]][i]),
      core = cell(df[["Core"]][i]),                 # Req | Exp | Perm
      codelistNcit = if (length(codes)) codes[[1]] else NULL,
      codelistNcitAll = as.list(codes))
  }
  ord <- order(vapply(vars, function(v) v$order, integer(1)))
  domains[[dom]] <- list(class = cls, variables = vars[ord])
}

out <- list(sdtmigVersion = "3.4",
            source = "SDTMIG v3.4 Classes and Columns.xlsx",
            domains = domains)

dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
jsonlite::write_json(out, out_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
n_var <- sum(vapply(domains, function(d) length(d$variables), integer(1)))
cat(sprintf("wrote %s: %d domains, %d variables\n", out_path, length(domains), n_var))
