# Read a generated SDTM CSV as an all-character data.frame (empty cells "").
load_sdtm_csv <- function(path) {
  if (!file.exists(path)) return(NULL)
  df <- utils::read.csv(path, colClasses = "character", check.names = FALSE,
                        na.strings = character(0))
  df[is.na(df)] <- ""
  df
}

# Number of dosing periods implied by the design (closed-form, seed-independent).
n_periods <- function(config) {
  crossover <- identical(config$design, "crossover")
  max_trts <- max(vapply(config$cohorts, function(c) length(c$treatments), integer(1)))
  if (crossover && max_trts >= 2 && length(config$periods) >= 2) length(config$periods) else 1L
}

# Expected row counts recomputed from the config: "exact" (seed-independent) or
# "bounds" (seed-dependent value domains).
expected_counts <- function(config, n) {
  knobs <- config$knobs %||% list()
  exp <- list()
  for (dom in names(config$domains)) {
    dc <- config$domains[[dom]]
    b <- dc$builder
    exp[[dom]] <- switch(b,
      dm = list("exact", n),
      ds = list("exact", n),
      ex = list("exact", n * n_periods(config)),
      ie = list("exact", min(knobs$ieExceptionCount %||% length(dc$exceptions %||% list()), n)),
      findings = list("exact", n * sum(vapply(dc$tests, function(t) length(t$occursAt), integer(1)))),
      mh = {
        cc <- knobs$comorbidityCount %||% list(0, 2)
        list("bounds", c(n, n + cc[[2]] * n))
      },
      cm = list("bounds", c(n, n + n)),
      ae = {
        eps <- knobs$aeEventsPerSubject %||% list(1, 3)
        list("bounds", c(0, eps[[2]] * round((knobs$aeIncidence %||% 0.55) * n)))
      },
      NULL)
  }
  exp
}

#' Run the three-tier accuracy checks
#'
#' Recomputes the expected shape from the config and asserts on the generated
#' data: T1 Shape (row counts, key uniqueness, coverage, variable set), T2
#' Conformance (CT membership, numeric types, mandatory population, value ranges,
#' ISO dates), T3 Cross-domain (referential integrity, `--DY` no-day-0, RF*
#' reconciliation, EPOCH CT, placebo rule, open-AE rule, reproducibility).
#'
#' @param config Parsed study config (list) or path.
#' @param spec Resolved spec (list) or path.
#' @param ct CT cache (list) or path.
#' @param run_dir Directory containing the generated `<DOMAIN>.csv` files.
#' @param n_subjects Subject count used to generate (for expected counts).
#' @param seed Seed used to generate (for the reproducibility check).
#' @return A report list (also written to `run_dir/check_report.json`), invisibly.
#' @export
check_sdtm <- function(config, spec, ct = list(), run_dir, n_subjects = NULL, seed = 1234) {
  if (is.character(config)) config <- jsonlite::read_json(config, simplifyVector = FALSE)
  if (is.character(spec)) spec <- jsonlite::read_json(spec, simplifyVector = FALSE)
  if (is.character(ct)) ct <- jsonlite::read_json(ct, simplifyVector = FALSE)
  if (is.null(n_subjects)) n_subjects <- sum(vapply(config$cohorts, function(c) c$n, numeric(1)))

  data <- list()
  for (dom in names(spec$domains)) data[[dom]] <- load_sdtm_csv(file.path(run_dir, paste0(dom, ".csv")))
  dm_rfst <- if (!is.null(data$DM)) stats::setNames(data$DM$RFSTDTC, data$DM$USUBJID) else character(0)

  results <- list()
  add <- function(id, tier, desc, ok, detail = "") {
    results[[length(results) + 1L]] <<- list(id = id, tier = tier, desc = desc,
      status = if (ok) "PASS" else "FAIL", detail = detail)
  }

  ## ---- T1 Shape --------------------------------------------------------------------------
  exp <- expected_counts(config, n_subjects)
  for (dom in names(exp)) {
    e <- exp[[dom]]
    actual <- if (is.null(data[[dom]])) 0L else nrow(data[[dom]])
    if (e[[1]] == "exact") {
      add(paste0(dom, "-COUNT"), "T1", paste(dom, "row count"), actual == e[[2]],
          sprintf("expected %d, got %d", as.integer(e[[2]]), actual))
    } else {
      lo <- e[[2]][1]; hi <- e[[2]][2]
      add(paste0(dom, "-COUNT"), "T1", paste(dom, "row count (bounds)"),
          actual >= lo && actual <= hi, sprintf("expected [%d,%d], got %d", lo, hi, actual))
    }
  }
  for (dom in names(data)) {
    df <- data[[dom]]; seqc <- paste0(dom, "SEQ")
    if (is.null(df) || !(seqc %in% names(df)) || nrow(df) == 0) next
    ok <- TRUE; detail <- ""
    for (u in unique(df$USUBJID)) {
      seqs <- sort(as.integer(df[[seqc]][df$USUBJID == u]))
      if (!identical(seqs, seq_len(length(seqs)))) { ok <- FALSE; detail <- paste(u, toString(seqs)); break }
    }
    add(paste0(dom, "-SEQ"), "T1", paste(dom, seqc, "unique + gap-free"), ok, detail)
  }
  produced <- names(data)[vapply(data, function(d) !is.null(d) && nrow(d) > 0, logical(1))]
  scope <- names(config$domains)
  add("COVERAGE", "T1", "populated domains == config scope", setequal(produced, scope),
      sprintf("missing=%s extra=%s", toString(setdiff(scope, produced)), toString(setdiff(produced, scope))))
  for (dom in names(data)) {
    df <- data[[dom]]; if (is.null(df) || nrow(df) == 0) next
    spec_fields <- vapply(spec$domains[[dom]]$fields, function(f) f$name, character(1))
    add(paste0(dom, "-VARS"), "T1", paste(dom, "header == spec fields"),
        identical(names(df), spec_fields), if (identical(names(df), spec_fields)) "" else "header mismatch")
  }

  ## ---- T2 Conformance --------------------------------------------------------------------
  for (dom in names(data)) {
    df <- data[[dom]]; if (is.null(df) || nrow(df) == 0) next
    fields <- spec$domains[[dom]]$fields
    fmap <- stats::setNames(fields, vapply(fields, function(f) f$name, character(1)))
    for (nm in names(fmap)) {
      ncit <- fmap[[nm]]$codelistNcit
      if (is.null(ncit)) next
      allowed <- ct_set(ct, ncit)
      if (length(allowed) == 0 || !(nm %in% names(df))) next
      vals <- df[[nm]][df[[nm]] != ""]
      # --ORRES/--STRESC result fields hold a numeric result OR a coded categorical
      # one; the codelist constrains only the categorical case, so numeric values are
      # conformant and excluded from the membership test.
      if (grepl("(ORRES|STRESC)$", nm)) vals <- vals[!vapply(vals, is_num, logical(1))]
      bad <- sort(unique(vals[!(vals %in% allowed)]))
      add(paste0(dom, "-CT-", nm), "T2", sprintf("%s.%s in CT %s", dom, nm, ncit),
          length(bad) == 0, if (length(bad)) paste("violations:", toString(bad)) else "")
    }
    for (nm in names(fmap)) {
      if (!identical(fmap[[nm]]$dataType, "Num") || !(nm %in% names(df))) next
      vals <- df[[nm]][df[[nm]] != ""]
      bad <- vals[!vapply(vals, is_num, logical(1))]
      add(paste0(dom, "-NUM-", nm), "T2", sprintf("%s.%s numeric parses", dom, nm),
          length(bad) == 0, if (length(bad)) paste(length(bad), "non-numeric") else "")
    }
    # Required (Core=Req) variables must be populated; Expected may be present-but-null.
    mand <- names(fmap)[vapply(fmap, function(f) identical(f$core, "Req"), logical(1))]
    empty <- vapply(mand, function(nm) if (nm %in% names(df)) sum(df[[nm]] == "") else 0L, integer(1))
    empty <- empty[empty > 0]
    add(paste0(dom, "-MAND"), "T2", paste(dom, "Required (Core=Req) populated"),
        length(empty) == 0, if (length(empty)) paste("empty:", toString(names(empty))) else "")
    for (nm in names(df)) {
      if (!grepl("DTC$", nm)) next
      bad <- sum(df[[nm]] != "" & !vapply(df[[nm]], iso_ok, logical(1)))
      add(paste0(dom, "-ISO-", nm), "T2", sprintf("%s.%s valid ISO-8601", dom, nm),
          bad == 0, if (bad) paste(bad, "invalid") else "")
    }
  }
  for (dom in names(config$domains)) {
    dc <- config$domains[[dom]]
    if (!identical(dc$builder, "findings") || is.null(data[[dom]])) next
    rng <- list()
    for (t in dc$tests) if (!is.null(t$low)) rng[[paste(t$testcd, t$category %||% "")]] <- c(t$low, t$high)
    df <- data[[dom]]; P <- dom; bad <- character(0)
    catcol <- paste0(P, "CAT"); tccol <- paste0(P, "TESTCD"); sncol <- paste0(P, "STRESN")
    for (i in seq_len(nrow(df))) {
      tc <- df[[tccol]][i]; cat <- if (catcol %in% names(df)) df[[catcol]][i] else ""
      sn <- df[[sncol]][i]; key <- paste(tc, cat)
      if (!is.null(rng[[key]]) && is_num(sn)) {
        lo <- rng[[key]][1]; hi <- rng[[key]][2]
        if (!(as.numeric(sn) >= lo && as.numeric(sn) <= hi)) bad <- c(bad, sprintf("%s[%s]=%s", tc, cat, sn))
      }
    }
    add(paste0(dom, "-RANGE"), "T2", paste(dom, "results within configured range"),
        length(bad) == 0, if (length(bad)) toString(utils::head(bad, 5)) else "")
  }

  ## ---- T3 Cross-domain -------------------------------------------------------------------
  dm_subjects <- names(dm_rfst)
  orphans <- character(0)
  for (dom in names(data)) {
    if (dom == "DM" || is.null(data[[dom]])) next
    miss <- setdiff(unique(data[[dom]]$USUBJID), dm_subjects)
    if (length(miss)) orphans <- c(orphans, sprintf("%s:%d", dom, length(miss)))
  }
  add("REF-INTEGRITY", "T3", "every USUBJID exists in DM", length(orphans) == 0, toString(orphans))

  dy_bad <- character(0)
  for (dom in names(data)) {
    df <- data[[dom]]; if (is.null(df) || nrow(df) == 0) next
    for (nm in names(df)) {
      if (!grepl("DY$", nm)) next
      dtc <- paste0(substr(nm, 1, nchar(nm) - 2), "DTC")
      if (!(dtc %in% names(df))) next
      for (i in seq_len(nrow(df))) {
        if (df[[nm]][i] == "" || df[[dtc]][i] == "") next
        rfst <- dm_rfst[[df$USUBJID[i]]] %||% ""
        e <- study_day(df[[dtc]][i], rfst)
        if (df[[nm]][i] == "0") dy_bad <- c(dy_bad, sprintf("%s.%s day0", dom, nm))
        else if (!identical(e, "") && as.character(e) != df[[nm]][i])
          dy_bad <- c(dy_bad, sprintf("%s.%s %s!=%s", dom, nm, df[[nm]][i], e))
      }
    }
  }
  add("DY-NODAY0", "T3", "--DY recomputes from RFSTDTC with no day 0",
      length(dy_bad) == 0, toString(utils::head(dy_bad, 5)))

  rf_bad <- character(0)
  if (!is.null(data$DM)) {
    ex <- data$EX; ds <- data$DS
    for (i in seq_len(nrow(data$DM))) {
      u <- data$DM$USUBJID[i]
      if (!is.null(ex)) {
        exs <- ex[ex$USUBJID == u, , drop = FALSE]
        if (nrow(exs)) {
          if (data$DM$RFXSTDTC[i] != min(exs$EXSTDTC)) rf_bad <- c(rf_bad, paste(u, "RFXSTDTC"))
          if (data$DM$RFXENDTC[i] != max(exs$EXENDTC)) rf_bad <- c(rf_bad, paste(u, "RFXENDTC"))
        }
      }
      if (!is.null(ds)) {
        dsr <- ds[ds$USUBJID == u, , drop = FALSE]
        if (nrow(dsr) && data$DM$RFENDTC[i] != dsr$DSSTDTC[1]) rf_bad <- c(rf_bad, paste(u, "RFENDTC"))
      }
    }
  }
  add("RF-RECONCILE", "T3", "DM RF* reconcile with EX/DS", length(rf_bad) == 0,
      toString(utils::head(rf_bad, 5)))

  epoch_bad <- character(0); allowed <- ct_set(ct, "C99079")
  if (length(allowed)) {
    for (dom in names(data)) {
      df <- data[[dom]]
      if (!is.null(df) && nrow(df) && "EPOCH" %in% names(df)) {
        b <- setdiff(unique(df$EPOCH[df$EPOCH != ""]), allowed)
        if (length(b)) epoch_bad <- c(epoch_bad, sprintf("%s:%s", dom, toString(b)))
      }
    }
  }
  add("EPOCH-CT", "T3", "EPOCH in CT C99079 everywhere", length(epoch_bad) == 0, toString(epoch_bad))

  plac_bad <- 0L
  if (!is.null(data$EX)) {
    ex <- data$EX
    plac_bad <- sum(toupper(ex$EXTRT) == "PLACEBO" & !(ex$EXDOSE %in% c("0", "0.0")))
  }
  add("PLACEBO", "T3", "EXTRT=PLACEBO => EXDOSE=0", plac_bad == 0,
      if (plac_bad) paste(plac_bad, "violations") else "")

  ae_bad <- 0L
  if (!is.null(data$AE)) {
    open_out <- (config$domains$AE$openOutcome) %||% "NOT RECOVERED/NOT RESOLVED"
    ae <- data$AE
    ae_bad <- sum((ae$AEENDTC == "") != (ae$AEOUT == open_out))
  }
  add("OPEN-AE", "T3", "AEENDTC empty <=> AEOUT=NOT RECOVERED/NOT RESOLVED", ae_bad == 0,
      if (ae_bad) paste(ae_bad, "violations") else "")

  # reproducibility: regenerate with same inputs+seed, compare data frames.
  repro <- regenerate_matches(config, spec, ct, data, n_subjects, seed)
  add("REPRODUCIBLE", "T1", "same inputs+seed => identical datasets", length(repro) == 0,
      if (length(repro)) paste("differ:", toString(repro)) else "")

  # lineage completeness
  lin_path <- file.path(run_dir, "lineage.json")
  if (file.exists(lin_path)) {
    lin <- jsonlite::read_json(lin_path, simplifyVector = FALSE)
    samples <- lin$samples %||% list()
    bad <- sum(vapply(samples, function(s) is.null(s$usdmActivityId) || is.null(s$protocolPage), logical(1)))
    add("LINEAGE", "T2", "every lineage sample -> activity + protocol page", bad == 0,
        sprintf("%d/%d incomplete", bad, length(samples)))
  } else {
    add("LINEAGE", "T2", "lineage provenance complete", FALSE, "lineage.json missing")
  }

  build_report(results, config, n_subjects, seed, run_dir)
}

# Regenerate and return domains whose CSV differs (reproducibility check).
regenerate_matches <- function(config, spec, ct, data, n, seed) {
  sim <- simulate_sdtm(config, spec, ct, n_subjects = n, seed = seed, domains = names(config$domains))
  mismatches <- character(0)
  for (dom in names(config$domains)) {
    a <- data[[dom]]
    b <- sim$domains[[dom]]
    if (is.null(a) || is.null(b)) next
    # compare as written CSV text (character) — order + values must match exactly
    if (!isTRUE(all.equal(a, b, check.attributes = FALSE))) mismatches <- c(mismatches, dom)
  }
  mismatches
}

build_report <- function(results, config, n, seed, run_dir) {
  tiers <- c("T1", "T2", "T3")
  fails <- Filter(function(r) r$status == "FAIL", results)
  by_tier <- lapply(tiers, function(t) {
    rs <- Filter(function(r) r$tier == t, results)
    list(total = length(rs), failed = sum(vapply(rs, function(r) r$status == "FAIL", logical(1))))
  })
  names(by_tier) <- tiers
  report <- list(studyId = config$studyId, subjects = n, seed = seed,
                 total = length(results), passed = length(results) - length(fails),
                 failed = length(fails), allPass = length(fails) == 0,
                 byTier = by_tier, failures = fails, checks = results)
  write_json_pretty(report, file.path(run_dir, "check_report.json"))
  cat(sprintf("\nAccuracy checks: %d/%d passed\n", report$passed, report$total))
  for (t in tiers) cat(sprintf("  %s: %d/%d pass\n", t, by_tier[[t]]$total - by_tier[[t]]$failed, by_tier[[t]]$total))
  if (length(fails)) {
    cat("\nFAILURES:\n")
    for (r in fails) cat(sprintf("  [%s] %s: %s -- %s\n", r$tier, r$id, r$desc, r$detail))
  }
  cat(sprintf("\nOVERALL: %s\n", if (report$allPass) "ALL PASS" else paste(length(fails), "FAIL")))
  invisible(report)
}
