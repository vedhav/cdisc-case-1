#!/usr/bin/env Rscript
# Build the bundled offline Controlled Terminology snapshot that synthsdtm reads.
#
# This is the single source of truth for the CT codelists the engine pins. It fetches,
# from the CDISC Library, every codelist referenced by the SDTMIG 3.4 variable reference
# (inst/extdata/sdtmig/sdtmig_3.4_variables.json) for the domains synthsdtm can generate,
# normalizes each to the compact shape ct.R consumes (terms[].submissionValue/decode), and
# writes inst/extdata/ct/<package>.json. Re-run when the pinned CT package changes:
#
#   CDISC_API_KEY=... Rscript inst/scripts/build_ct_snapshot.R \
#       [--package sdtmct-2026-03-27] [--all] [--out inst/extdata/ct/<package>.json]
#
#   --all   include codelists referenced by ALL 63 SDTMIG domains (default: only the
#           domains in SUPPORTED below, i.e. what supported_domains() can generate today).
#
# Retired-codelist fallback: a few codelist conceptIds referenced by the SDTMIG 3.4
# spreadsheet (e.g. RACE C74457, ETHNIC C66790, LBSTRESC C102580) were renumbered/removed
# in later CT packages and are absent from the pinned package. For those, the script falls
# back to the most recent PRIOR package that still defines the code, and records that
# provenance in the entry's `sourcePackage`, so the snapshot is complete and conformant
# without a disruptive global re-pin. Anything still unresolved is reported, never guessed.
#
# Requires 'httr' and 'jsonlite', and the CDISC_API_KEY environment variable.

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

# Domains synthsdtm can generate today -- keep in sync with .supported in R/domains.R.
SUPPORTED <- c("DM", "IE", "MH", "VS", "EG", "LB", "EX", "CM", "AE", "DS", "PC", "PE")
BASE <- "https://library.cdisc.org/api"

## ---- args -------------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
get_opt <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[[i + 1L]]
}
package  <- get_opt("--package", "sdtmct-2026-03-27")
scope_all <- "--all" %in% args
out_path <- get_opt("--out", file.path("inst", "extdata", "ct", paste0(package, ".json")))
ref_path <- file.path("inst", "extdata", "sdtmig", "sdtmig_3.4_variables.json")

if (!requireNamespace("httr", quietly = TRUE)) stop("This script needs the 'httr' package.", call. = FALSE)
api_key <- Sys.getenv("CDISC_API_KEY")
if (!nzchar(api_key)) stop("Set CDISC_API_KEY to fetch from the CDISC Library.", call. = FALSE)
if (!file.exists(ref_path)) stop("SDTMIG reference not found at ", ref_path, "; run from the package root.", call. = FALSE)

## ---- which codelists do we need? --------------------------------------------------------
ref <- jsonlite::read_json(ref_path, simplifyVector = FALSE)
doms <- if (scope_all) names(ref$domains) else intersect(SUPPORTED, names(ref$domains))
ids <- character(0)
for (dom in doms) {
  for (v in ref$domains[[dom]]$variables) {
    ids <- c(ids, v$codelistNcit %||% character(0),
             unlist(v$codelistNcitAll %||% list(), use.names = FALSE))
  }
}
ids <- sort(unique(ids[nzchar(ids)]))
cat(sprintf("Need %d distinct codelists across %d domain(s) [%s scope].\n",
            length(ids), length(doms), if (scope_all) "all" else "supported"))

## ---- CDISC Library fetch helpers --------------------------------------------------------
get_json <- function(path) {
  resp <- httr::GET(paste0(BASE, path),
                    httr::add_headers(`api-key` = api_key), httr::accept_json())
  if (httr::status_code(resp) == 200L) {
    return(jsonlite::fromJSON(httr::content(resp, as = "text", encoding = "UTF-8"),
                              simplifyVector = FALSE))
  }
  if (httr::status_code(resp) == 404L) return(NULL)
  stop("HTTP ", httr::status_code(resp), " for ", path, call. = FALSE)
}

# Normalize a CDISC Library codelist payload to the compact bundled shape.
normalize <- function(cl, pkg) {
  terms <- lapply(cl$terms %||% list(), function(t) list(
    submissionValue = t$submissionValue %||% "",
    conceptId = t$conceptId %||% "",
    decode = t$preferredTerm %||% (t$decode %||% "")))
  list(conceptId = cl$conceptId, name = cl$name %||% "",
       extensible = cl$extensible %||% "false", package = pkg, terms = terms)
}

# Most recent package href (<= pinned date) from the version-agnostic root view.
prior_version_path <- function(id, pinned_pkg) {
  root <- get_json(sprintf("/mdr/root/ct/sdtmct/codelists/%s", id))
  if (is.null(root)) return(NULL)
  vs <- vapply(root$`_links`$versions %||% list(), function(v) v$href %||% "", character(1))
  vs <- vs[nzchar(vs)]
  pkgs <- sub(".*/packages/([^/]+)/.*", "\\1", vs)
  ok <- pkgs[pkgs <= pinned_pkg]                       # lexical compare works for sdtmct-YYYY-MM-DD
  if (!length(ok)) return(NULL)
  newest <- ok[order(ok, decreasing = TRUE)][[1]]
  list(path = sprintf("/mdr/ct/packages/%s/codelists/%s", newest, id), pkg = newest)
}

## ---- fetch ------------------------------------------------------------------------------
snapshot <- list()
fetched <- character(0); fallback <- list(); unresolved <- character(0)
for (id in ids) {
  cl <- get_json(sprintf("/mdr/ct/packages/%s/codelists/%s", package, id))
  if (!is.null(cl)) {
    snapshot[[id]] <- normalize(cl, package)
    fetched <- c(fetched, id)
    next
  }
  pv <- prior_version_path(id, package)               # retired in pinned pkg -> prior version
  if (!is.null(pv) && !is.null(cl2 <- get_json(pv$path))) {
    entry <- normalize(cl2, package)                  # keep pinned pkg label for the snapshot key...
    entry$sourcePackage <- pv$pkg                     # ...but record where it actually came from
    snapshot[[id]] <- entry
    fallback[[id]] <- pv$pkg
    next
  }
  unresolved <- c(unresolved, id)
}

## ---- write + report ---------------------------------------------------------------------
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
jsonlite::write_json(snapshot, out_path, auto_unbox = TRUE, pretty = TRUE, null = "null")

n_terms <- sum(vapply(snapshot, function(c) length(c$terms), integer(1)))
cat(sprintf("\nwrote %s\n  %d codelists, %d terms\n", out_path, length(snapshot), n_terms))
cat(sprintf("  fetched from %s: %d\n", package, length(fetched)))
if (length(fallback)) {
  cat(sprintf("  fallback to prior package (retired in %s): %d\n", package, length(fallback)))
  for (id in names(fallback)) cat(sprintf("    %s <- %s\n", id, fallback[[id]]))
}
if (length(unresolved)) {
  cat(sprintf("  UNRESOLVED (no package defines these): %d\n", length(unresolved)))
  for (id in unresolved) cat(sprintf("    %s\n", id))
} else {
  cat("  unresolved: 0\n")
}
