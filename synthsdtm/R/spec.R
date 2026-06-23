# SDTMIG 3.4 variable template + spec resolution.
#
# The variable-level metadata (order, label, role, dataType, codelist NCIt, Core)
# is a published-standard artifact, NOT study-specific. It is the single source of
# truth bundled as inst/extdata/sdtmig/sdtmig_3.4_variables.json, generated from the
# authoritative "SDTMIG v3.4 Classes and Columns.xlsx" by inst/scripts/
# build_sdtmig_reference.R. build_spec() emits a spec for exactly the domains the
# config declares in scope, pinning Controlled Terminology from the offline snapshot.

# Human-readable domain labels (the dataset description; not a column in the sheet).
.domain_labels <- c(
  DM = "Demographics", IE = "Inclusion/Exclusion Criteria Not Met",
  MH = "Medical History", VS = "Vital Signs", EG = "ECG Test Results",
  LB = "Laboratory Test Results", EX = "Exposure",
  CM = "Concomitant/Prior Medications", AE = "Adverse Events", DS = "Disposition",
  PC = "Pharmacokinetics Concentrations", PE = "Physical Examination")

# Emit policy: every Req and every Exp variable of an in-scope domain is emitted
# (Exp may be value-null but the column is always present, so an Expected variable
# is never "missing"). Permissible variables are emitted only when this engine
# populates them -- the per-domain allow-list below. Anything not listed here and
# not Req/Exp is a Perm column legitimately omitted (no data collected for it).
.emit_perm <- list(
  DM = c("BRTHDTC", "ETHNIC"),
  IE = c("EPOCH"),
  MH = c("MHCAT", "MHDY", "EPOCH", "MHDTC"),
  VS = c("VSPOS", "VSDY", "VISIT", "EPOCH"),
  EG = c("EGORRESU", "EGSTRESN", "EGSTRESU", "EGDY", "VISIT", "EPOCH"),
  LB = c("LBSPEC", "LBFAST", "LBDY", "VISIT", "EPOCH"),
  EX = c("EXROUTE", "EXSTDY", "EXENDY", "EPOCH"),
  CM = c("CMDOSE", "CMDOSU", "CMROUTE", "CMINDC", "CMSTDTC", "CMSTDY", "EPOCH"),
  AE = c("AESEV", "AEOUT", "AESTDY", "AEENDY", "EPOCH"),
  DS = c("EPOCH"),
  PC = c("PCCAT", "PCDY", "VISIT", "EPOCH"),
  PE = c("PECAT", "PEDY", "VISIT", "EPOCH"))

# Load the bundled SDTMIG 3.4 variable reference (cached per session).
.sdtmig_ref_cache <- new.env(parent = emptyenv())
sdtmig_reference <- function() {
  if (is.null(.sdtmig_ref_cache$ref)) {
    path <- system.file("extdata", "sdtmig", "sdtmig_3.4_variables.json",
                        package = "synthsdtm", mustWork = FALSE)
    if (!nzchar(path) || !file.exists(path)) {
      stop("Bundled SDTMIG reference not found; regenerate with ",
           "inst/scripts/build_sdtmig_reference.R.", call. = FALSE)
    }
    .sdtmig_ref_cache$ref <- jsonlite::read_json(path, simplifyVector = FALSE)
  }
  .sdtmig_ref_cache$ref
}

# Class of a domain, straight from the standard reference (e.g. "Findings").
domain_class <- function(dom) {
  ref <- sdtmig_reference()
  d <- ref$domains[[dom]]
  if (is.null(d)) NA_character_ else d$class
}

#' The SDTMIG 3.4 variable template for the templated domains
#'
#' For each domain this engine can generate, returns the ordered list of variables
#' to emit -- all Req + all Exp + the allow-listed Perm in `.emit_perm` -- with
#' metadata (label, role, dataType, Core, codelist NCIt) taken verbatim from the
#' bundled authoritative reference. This guarantees a Required/Expected variable is
#' never accidentally missing and a non-standard variable can never be emitted.
#'
#' @return Named list (domain -> ordered list of field metadata lists).
sdtmig_template <- function() {
  ref <- sdtmig_reference()
  out <- list()
  for (dom in names(.emit_perm)) {
    d <- ref$domains[[dom]]
    if (is.null(d)) {
      stop("Domain ", dom, " missing from the SDTMIG reference.", call. = FALSE)
    }
    allow <- .emit_perm[[dom]]
    fields <- list()
    for (vrec in d$variables) {
      keep <- vrec$core %in% c("Req", "Exp") || vrec$name %in% allow
      if (!keep) next
      fields[[length(fields) + 1L]] <- list(
        name = vrec$name, label = vrec$label, role = vrec$role,
        dataType = vrec$type, core = vrec$core,
        codelistNcit = vrec$codelistNcit %||% NULL)
    }
    out[[dom]] <- fields
  }
  out
}

# Path to the bundled study_config JSON Schema (the Stage-4 output contract).
config_schema_path <- function() {
  system.file("schema", "study_config.schema.json", package = "synthsdtm", mustWork = FALSE)
}

# Validate a parsed study config and stop() with an actionable message on the
# first problem. Uses jsonvalidate (full JSON Schema) when installed; always runs
# a lightweight structural fallback so a typo'd top-level/knob key fails fast even
# without the optional dependency.
validate_config <- function(config, config_path = NULL) {
  # ---- full JSON Schema validation (preferred, when jsonvalidate is present) ----
  schema <- config_schema_path()
  if (requireNamespace("jsonvalidate", quietly = TRUE) && nzchar(schema) && file.exists(schema)) {
    json <- if (!is.null(config_path) && is.character(config_path) && file.exists(config_path)) {
      paste(readLines(config_path, warn = FALSE), collapse = "\n")
    } else {
      jsonlite::toJSON(config, auto_unbox = TRUE, null = "null")
    }
    res <- jsonvalidate::json_validate(json, schema, engine = "ajv", verbose = TRUE, greedy = TRUE)
    if (!isTRUE(res)) {
      errs <- attr(res, "errors")
      msg <- if (!is.null(errs) && nrow(errs)) {
        paste(sprintf("  %s %s", errs$instancePath, errs$message), collapse = "\n")
      } else "schema validation failed"
      stop("study_config does not conform to study_config.schema.json:\n", msg, call. = FALSE)
    }
    return(invisible(TRUE))
  }

  # ---- lightweight structural fallback (always available) ----
  known_top <- c("studyId", "sponsorStudyId", "design", "studyStart", "country", "sites",
                 "route", "enrollmentWindowDays", "screenLagDays", "cohorts", "demographics",
                 "periods", "visitGrid", "knobs", "sourceActivities", "domains")
  unknown_top <- setdiff(names(config), known_top)
  if (length(unknown_top)) {
    stop("Unknown top-level config key(s): ", toString(unknown_top),
         ". Known keys: ", toString(known_top), ".", call. = FALSE)
  }
  required_top <- c("studyId", "design", "cohorts", "demographics", "visitGrid", "domains")
  missing_top <- setdiff(required_top, names(config))
  if (length(missing_top)) {
    stop("Missing required config key(s): ", toString(missing_top), ".", call. = FALSE)
  }
  if (!is.null(config$design) && !config$design %in% c("parallel", "crossover", "single-group")) {
    stop("config$design must be one of parallel/crossover/single-group; got '", config$design, "'.",
         call. = FALSE)
  }
  known_knobs <- c("discontinuationRate", "discoReason", "discoEndOffsetDays", "completionOffsetDays",
                   "aeIncidence", "aeEventsPerSubject", "aeSeverityWeights", "aeRelChoices",
                   "aeActnWeights", "conmedPrevalence", "comorbidityCount", "ieExceptionCount")
  unknown_knobs <- setdiff(names(config$knobs %||% list()), known_knobs)
  if (length(unknown_knobs)) {
    stop("Unknown knob(s): ", toString(unknown_knobs),
         " (a typo'd knob would silently use the default). Known knobs: ",
         toString(known_knobs), ".", call. = FALSE)
  }
  invisible(TRUE)
}

#' Default pinned CT package and the bundled snapshot path
#' @export
ct_package <- function() "sdtmct-2026-03-27"

#' Path to the bundled offline CT snapshot
#' @export
ct_snapshot_path <- function() {
  system.file("extdata", "ct", paste0(ct_package(), ".json"),
              package = "synthsdtm", mustWork = FALSE)
}

#' Resolve the SDTM variable spec + Controlled Terminology
#'
#' Given a study config, produce a per-domain SDTMIG 3.4 variable spec for the
#' in-scope domains and pin Controlled Terminology from the offline snapshot.
#'
#' @param config Parsed study config (a list), or a path to its JSON.
#' @param ct_snapshot Path to the CT snapshot JSON; defaults to the bundled pin.
#' @param out_dir Optional directory; when given, writes `sdtm_spec.json`,
#'   `ct_cache.json`, and `coverage.json`.
#' @return A list with `spec`, `ct_cache`, and `coverage`.
#' @export
build_spec <- function(config, ct_snapshot = ct_snapshot_path(), out_dir = NULL) {
  config_path <- if (is.character(config)) config else NULL
  if (is.character(config)) config <- jsonlite::read_json(config, simplifyVector = FALSE)
  validate_config(config, config_path)
  template <- sdtmig_template()
  in_scope <- names(config$domains)
  unknown <- setdiff(in_scope, names(template))
  if (length(unknown)) {
    fr <- intersect(unknown, sdtm_domains()$domain[sdtm_domains()$findings_ready])
    hint <- if (length(fr)) {
      paste0(" ", paste(fr, collapse = "/"), " are Findings-class: add the domain to ",
             ".emit_perm in R/spec.R and a config test panel; the generic 'findings' builder ",
             "covers them with no new builder. ")
    } else " "
    stop("No SDTMIG template for domain(s): ", paste(unknown, collapse = ", "), ".", hint,
         "See supported_domains() for what is generatable today and sdtm_domains() for the ",
         "full inventory.", call. = FALSE)
  }

  snapshot <- if (nzchar(ct_snapshot) && file.exists(ct_snapshot)) {
    jsonlite::read_json(ct_snapshot, simplifyVector = FALSE)
  } else {
    list()
  }
  ct_cache <- list()
  missing_ct <- character(0)
  fetch <- function(ncit) {
    if (is.null(ncit)) return(NULL)
    if (!is.null(ct_cache[[ncit]])) return(ct_cache[[ncit]])
    rec <- snapshot[[ncit]]
    if (!is.null(rec)) {
      rec$package <- ct_package()
      rec$source <- "offline_snapshot"
      ct_cache[[ncit]] <<- rec
    } else {
      missing_ct <<- union(missing_ct, ncit)   # referenced but absent from the snapshot
    }
    rec
  }

  src_acts <- config$sourceActivities %||% list()
  domains <- list()
  for (dom in in_scope) {
    out_fields <- list()
    for (f in template[[dom]]) {
      cl <- if (!is.null(f$codelistNcit)) fetch(f$codelistNcit) else NULL
      out_fields[[length(out_fields) + 1L]] <- list(
        name = f$name, label = f$label, order = length(out_fields) + 1L,
        role = f$role, dataType = f$dataType, core = f$core,
        codelistNcit = f$codelistNcit %||% NULL,
        codelistName = if (!is.null(cl)) cl$name else NULL)
    }
    domains[[dom]] <- list(
      label = unname(.domain_labels[dom]), class = domain_class(dom),
      sourceActivities = src_acts[[dom]] %||% list(),
      fieldCount = length(out_fields), fields = out_fields)
  }

  if (length(missing_ct)) {
    warning("build_spec: ", length(missing_ct), " referenced CT codelist(s) absent from ",
            "the bundled snapshot (", ct_package(), "); their <DOM>-CT-<var> conformance ",
            "checks will be skipped: ", toString(sort(missing_ct)),
            ". Regenerate the snapshot with inst/scripts/build_ct_snapshot.R.", call. = FALSE)
  }

  spec <- list(studyId = config$studyId, sdtmigVersion = "3.4",
               ctPackage = ct_package(), ctSource = "sdtmig_template_offline",
               domains = domains)
  coverage <- list(studyId = config$studyId, populated = as.list(in_scope),
                   ctPackagePinned = ct_package(), sdtmigVersion = "3.4",
                   ctSource = spec$ctSource)

  if (!is.null(out_dir)) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    write_json_pretty(spec, file.path(out_dir, "sdtm_spec.json"))
    write_json_pretty(ct_cache, file.path(out_dir, "ct_cache.json"))
    write_json_pretty(coverage, file.path(out_dir, "coverage.json"))
  }
  list(spec = spec, ct_cache = ct_cache, coverage = coverage)
}

# Write a list as pretty JSON, preserving {} for empty named lists.
write_json_pretty <- function(x, path) {
  jsonlite::write_json(x, path, auto_unbox = TRUE, pretty = TRUE, null = "null")
}
