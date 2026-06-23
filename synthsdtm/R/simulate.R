# Assemble a list of named row-lists into a data.frame with columns in spec
# field order (missing cells become ""). All character — numeric coercion happens
# at XPT export, mirroring the SDTM CSV contract.
rows_to_df <- function(rows, field_names) {
  if (length(rows) == 0) {
    df <- as.data.frame(matrix("", nrow = 0, ncol = length(field_names)),
                        stringsAsFactors = FALSE)
    names(df) <- field_names
    return(df)
  }
  cols <- lapply(field_names, function(nm) {
    vapply(rows, function(r) {
      val <- r[[nm]]
      if (is.null(val)) "" else if (is.numeric(val)) fmt_num(val) else as.character(val)
    }, character(1))
  })
  names(cols) <- field_names
  as.data.frame(cols, stringsAsFactors = FALSE, check.names = FALSE)
}

# --SEQ restarts at 1 within each USUBJID (gap-free) — the SDTM key rule.
seq_per_subject <- function(rows, col) {
  counts <- list()
  for (i in seq_along(rows)) {
    u <- rows[[i]]$USUBJID
    counts[[u]] <- (counts[[u]] %||% 0L) + 1L
    rows[[i]][[col]] <- counts[[u]]
  }
  rows
}

# Visit date for a subject = Day 1 + the encounter's day offset (ISO-8601).
vdate <- function(ctx, s, enc) {
  as.character(s$day1 + ctx$visit[[enc]]$dayOffset)
}

# Base identifier columns shared by every row.
row_base <- function(ctx, dom, s) {
  list(STUDYID = ctx$studyid, DOMAIN = dom, USUBJID = s$USUBJID)
}

# Build the subject backbone: cohorts, design-driven dosing, dates, disposition.
build_subjects <- function(config, n) {
  demo <- config$demographics
  sites <- config$sites %||% list("0001")
  start <- as.Date(config$studyStart)
  enroll_win <- config$enrollmentWindowDays %||% 120
  screen_lag <- config$screenLagDays %||% list(10, 14)
  design <- config$design %||% "parallel"
  periods <- config$periods
  knobs <- config$knobs %||% list()

  cohorts <- config$cohorts
  planned <- vapply(cohorts, function(c) c$n, numeric(1))
  sizes <- round(planned / sum(planned) * n)
  sizes[length(sizes)] <- sizes[length(sizes)] + (n - sum(sizes))  # fix rounding drift

  subjects <- list()
  sid <- 0L
  for (ci in seq_along(cohorts)) {
    c <- cohorts[[ci]]
    trts <- c$treatments
    for (k in seq_len(sizes[ci])) {
      sid <- sid + 1L
      subjid <- sprintf("%04d", sid)
      scr <- start + rint(0, enroll_win)
      day1 <- scr + rint(screen_lag[[1]], screen_lag[[2]])
      if (identical(design, "crossover") && length(trts) >= 2 && length(periods) >= 2) {
        seqlab <- rchoice(list("AB", "BA"))
        ordered <- if (seqlab == "AB") trts[1:2] else list(trts[[2]], trts[[1]])
      } else {
        seqlab <- "A"
        ordered <- list(trts[[1]])
      }
      dosing <- list()
      for (pi in seq_along(ordered)) {
        per <- periods[[pi]]
        dosing[[pi]] <- list(
          trt = ordered[[pi]], label = per$label, visitNum = per$visitNum,
          epoch = per$epoch %||% "TREATMENT",
          start = day1 + per$startOffset, end = day1 + per$endOffset)
      }
      subjects[[sid]] <- list(
        SUBJID = subjid, USUBJID = paste0(config$sponsorStudyId %||% config$studyId, "-", subjid),
        SITEID = rchoice(sites), armcd = c$armcd, arm = c$arm, seq = seqlab,
        treatments = trts, dosing = dosing,
        sex = rchoice(demo$sexes), age = rint(demo$ageRange[[1]], demo$ageRange[[2]]),
        race = rchoice(demo$races), ethnic = rchoice(demo$ethnicities),
        height = round(stats::runif(1, demo$heightCm[[1]], demo$heightCm[[2]]), 1),
        weight = round(stats::runif(1, demo$weightKg[[1]], demo$weightKg[[2]]), 1),
        scr = scr, day1 = day1)
    }
  }

  # Disposition: first round(rate * N) subjects discontinue early; the rest complete.
  disco_rate <- knobs$discontinuationRate %||% 0.05
  n_disco <- round(disco_rate * n)
  reason <- knobs$discoReason %||% list(decod = "ADVERSE EVENT", term = "Adverse event")
  disco_off <- knobs$discoEndOffsetDays %||% list(5, 30)
  compl_off <- knobs$completionOffsetDays %||% 61
  for (i in seq_along(subjects)) {
    s <- subjects[[i]]
    if (i <= n_disco) {
      s$dsdecod <- reason$decod; s$dsterm <- reason$term
      s$ds_end <- s$day1 + rint(disco_off[[1]], disco_off[[2]])
    } else {
      s$dsdecod <- "COMPLETED"; s$dsterm <- "Completed"
      s$ds_end <- s$day1 + compl_off
    }
    s$rfstdtc <- as.character(s$dosing[[1]]$start)
    s$rfxstdtc <- as.character(s$dosing[[1]]$start)
    s$rfxendtc <- as.character(s$dosing[[length(s$dosing)]]$end)
    s$rfendtc <- as.character(s$ds_end)
    subjects[[i]] <- s
  }
  subjects
}

#' Generate synthetic SDTM datasets
#'
#' The study-agnostic engine: the study lives entirely in `config`, the standard
#' in `spec`/`ct`. Deterministic and seeded — same inputs and seed yield
#' identical output, and shape-domain row counts are seed-independent.
#'
#' @param config Parsed study config (list) or path to its JSON.
#' @param spec Resolved spec (list) or path to `sdtm_spec.json`.
#' @param ct Controlled Terminology cache (list) or path to `ct_cache.json`.
#' @param n_subjects Subject count; defaults to the summed cohort sizes.
#' @param seed Integer RNG seed.
#' @param domains Optional character vector restricting which domains to build.
#' @return A `sdtm_sim` list: `domains` (named list of data.frames), `lineage`,
#'   `summary`, `datasets`, `variables`, plus the inputs for reproducibility.
#' @export
simulate_sdtm <- function(config, spec, ct = list(), n_subjects = NULL,
                          seed = 1234, domains = NULL) {
  if (is.character(config)) config <- jsonlite::read_json(config, simplifyVector = FALSE)
  if (is.character(spec)) spec <- jsonlite::read_json(spec, simplifyVector = FALSE)
  if (is.character(ct)) ct <- jsonlite::read_json(ct, simplifyVector = FALSE)
  if (is.null(n_subjects)) n_subjects <- sum(vapply(config$cohorts, function(c) c$n, numeric(1)))

  set.seed(seed)
  subjects <- build_subjects(config, n_subjects)

  src <- config$sourceActivities %||% list()
  dom_src <- list()
  for (d in names(config$domains)) {
    acts <- src[[d]]
    dom_src[[d]] <- if (length(acts)) {
      list(id = acts[[1]]$activityId, page = acts[[1]]$protocolPage, bc = acts[[1]]$bcNcit)
    } else {
      list(id = NULL, page = NULL, bc = NULL)
    }
  }

  ctx <- list(
    config = config, spec = spec, ct = ct, subjects = subjects,
    visit = config$visitGrid, knobs = config$knobs %||% list(),
    studyid = config$sponsorStudyId %||% config$studyId,
    country = config$country %||% "USA", route = config$route %||% "ORAL",
    demo = config$demographics, dom_src = dom_src)

  builders <- list(dm = build_dm, ie = build_ie, mh = build_mh, findings = build_findings,
                   ex = build_ex, cm = build_cm, ae = build_ae, ds = build_ds)

  result <- list(domains = list(), lineage = list(), summary = list(),
                 datasets = list(), variables = list(),
                 config = config, spec = spec, ct = ct, n = n_subjects, seed = seed)

  for (dom in names(config$domains)) {
    if (!is.null(domains) && !(dom %in% domains)) next
    if (is.null(spec$domains[[dom]])) {
      message(sprintf("  [skip] %s: no spec resolved", dom)); next
    }
    dcfg <- config$domains[[dom]]
    fn <- builders[[dcfg$builder]]
    if (is.null(fn)) stop("Unknown builder '", dcfg$builder, "' for domain ", dom, call. = FALSE)
    out <- fn(ctx, dom, dcfg)
    field_names <- vapply(spec$domains[[dom]]$fields, function(f) f$name, character(1))
    df <- rows_to_df(out$rows, field_names)
    result$domains[[dom]] <- df
    result$summary[[dom]] <- nrow(df)
    result$lineage <- c(result$lineage, out$lineage)
    result$datasets[[length(result$datasets) + 1L]] <-
      list(Filename = paste0(tolower(dom), ".xpt"), Label = spec$domains[[dom]]$label)
    for (f in spec$domains[[dom]]$fields) {
      result$variables[[length(result$variables) + 1L]] <- list(
        dataset = tolower(dom), variable = f$name, label = f$label,
        type = if (identical(f$dataType, "Num")) "Num" else "Char",
        length = if (identical(f$dataType, "Num")) 8L else 200L)
    }
    message(sprintf("  %s: %d rows", dom, nrow(df)))
  }
  class(result) <- "sdtm_sim"
  result
}

#' Write a simulation result to disk
#'
#' Emits one `<DOMAIN>.csv` per domain plus CORE metadata sidecars
#' (`_datasets.csv`, `_variables.csv`), `lineage.json`, and
#' `datasets_summary.json`.
#'
#' @param result A `sdtm_sim` object from [simulate_sdtm()].
#' @param out_dir Output directory (created if needed).
#' @return `out_dir`, invisibly.
#' @export
write_sdtm <- function(result, out_dir) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  for (dom in names(result$domains)) {
    utils::write.csv(result$domains[[dom]], file.path(out_dir, paste0(dom, ".csv")),
                     row.names = FALSE, na = "")
  }
  ds <- do.call(rbind, lapply(result$datasets, function(d)
    data.frame(Filename = d$Filename, Label = d$Label, stringsAsFactors = FALSE)))
  utils::write.csv(ds, file.path(out_dir, "_datasets.csv"), row.names = FALSE)
  vars <- do.call(rbind, lapply(result$variables, function(v)
    data.frame(dataset = v$dataset, variable = v$variable, label = v$label,
               type = v$type, length = v$length, stringsAsFactors = FALSE)))
  utils::write.csv(vars, file.path(out_dir, "_variables.csv"), row.names = FALSE)

  write_json_pretty(list(
    note = paste("Representative cell-level lineage: synthetic value -> USDM activity ->",
                 "biomedical concept -> protocol page."),
    studyId = result$config$studyId, subjects = result$n, seed = result$seed,
    samples = result$lineage), file.path(out_dir, "lineage.json"))
  write_json_pretty(list(
    studyId = result$config$studyId, sponsorStudyId = result$config$sponsorStudyId,
    subjects = result$n, seed = result$seed, sdtmigVersion = result$spec$sdtmigVersion,
    ctPackage = result$spec$ctPackage, design = result$config$design,
    rowCounts = result$summary, totalRows = sum(unlist(result$summary))),
    file.path(out_dir, "datasets_summary.json"))
  invisible(out_dir)
}
