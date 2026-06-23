# Domain builders. Each takes (ctx, dom, dcfg) and returns
# list(rows = <list of named row-lists>, lineage = <list of lineage records>).
# Bespoke builders: dm, ie, mh, ex, cm, ae, ds. One generic `findings` builder
# serves VS/EG/LB (and any other Findings domain) driven by the config test panel.

# One lineage record: synthetic cell -> USDM activity -> BC -> protocol page.
trace_one <- function(ctx, dom, var, usubjid, value) {
  ds <- ctx$dom_src[[dom]]
  list(domain = dom, variable = var, usubjid = usubjid, value = value,
       usdmActivityId = ds$id %||% NULL, biomedicalConceptNcit = ds$bc %||% NULL,
       protocolPage = ds$page %||% NULL,
       ctPackage = ctx$spec$ctPackage, sdtmigVersion = ctx$spec$sdtmigVersion)
}

build_dm <- function(ctx, dom, dcfg) {
  rows <- list(); lineage <- list()
  age_unit <- ctx$demo$ageUnit %||% "YEARS"
  for (s in ctx$subjects) {
    byear <- as.integer(format(s$scr, "%Y")) - s$age
    brth <- sprintf("%04d-%02d-%02d", byear, rint(1, 12), rint(1, 28))
    r <- row_base(ctx, dom, s)
    r <- c(r, list(
      SUBJID = s$SUBJID, RFSTDTC = s$rfstdtc, RFENDTC = s$rfendtc,
      RFXSTDTC = s$rfxstdtc, RFXENDTC = s$rfxendtc, SITEID = s$SITEID, BRTHDTC = brth,
      AGE = s$age, AGEU = coded_choice(ctx$ct, "C66781", list(age_unit)), SEX = s$sex,
      RACE = s$race, ETHNIC = s$ethnic, ARMCD = s$armcd, ARM = s$arm,
      ACTARMCD = s$armcd, ACTARM = s$arm, COUNTRY = ctx$country))
    rows[[length(rows) + 1L]] <- r
    lineage[[length(lineage) + 1L]] <- trace_one(ctx, dom, "SEX", s$USUBJID, s$sex)
  }
  list(rows = rows, lineage = lineage)
}

build_ie <- function(ctx, dom, dcfg) {
  exceptions <- dcfg$exceptions %||% list()
  count <- ctx$knobs$ieExceptionCount %||% length(exceptions)
  count <- min(count, length(ctx$subjects))
  rows <- list()
  if (count > 0 && length(exceptions) > 0) {
    idx <- sample.int(length(ctx$subjects), count)
    for (j in seq_along(idx)) {
      s <- ctx$subjects[[idx[j]]]
      ex <- exceptions[[((j - 1) %% length(exceptions)) + 1L]]
      r <- row_base(ctx, dom, s)
      r <- c(r, list(
        IETESTCD = ex$testcd %||% "INCL01", IETEST = ex$test %||% "",
        IECAT = ex$cat %||% "INCLUSION", IEORRES = ex$orres %||% "",
        IESTRESC = ex$stresc %||% (ex$orres %||% ""),
        EPOCH = coded_choice(ctx$ct, "C99079", list("SCREENING"))))
      rows[[length(rows) + 1L]] <- r
    }
  }
  rows <- seq_per_subject(rows, "IESEQ")
  list(rows = rows, lineage = list())
}

build_mh <- function(ctx, dom, dcfg) {
  rows <- list(); lineage <- list()
  comorb <- dcfg$comorbidities %||% list()
  cc <- ctx$knobs$comorbidityCount %||% list(0, 2)
  po <- dcfg$primaryOnsetYearsAgo %||% list(1, 10)
  co <- dcfg$comorbidityOnsetYearsAgo %||% list(1, 8)
  for (s in ctx$subjects) {
    srows <- list()
    onset <- sprintf("%04d-%02d-%02d", as.integer(format(s$scr, "%Y")) - rint(po[[1]], po[[2]]),
                     rint(1, 12), rint(1, 28))
    r <- row_base(ctx, dom, s)
    r <- c(r, list(MHTERM = dcfg$primaryDiagnosis %||% "", MHCAT = "PRIMARY DIAGNOSIS",
                   EPOCH = coded_choice(ctx$ct, "C99079", list("SCREENING")),
                   MHDTC = onset, MHDY = study_day(onset, s$rfstdtc)))
    srows[[1]] <- r
    if (length(comorb) > 0) {
      k <- rint(cc[[1]], min(cc[[2]], length(comorb)))
      if (k > 0) {
        for (cm in comorb[sample.int(length(comorb), k)]) {
          o <- sprintf("%04d-%02d-%02d", as.integer(format(s$scr, "%Y")) - rint(co[[1]], co[[2]]),
                       rint(1, 12), rint(1, 28))
          rr <- row_base(ctx, dom, s)
          rr <- c(rr, list(MHTERM = cm, MHCAT = "GENERAL MEDICAL HISTORY",
                           EPOCH = coded_choice(ctx$ct, "C99079", list("SCREENING")),
                           MHDTC = o, MHDY = study_day(o, s$rfstdtc)))
          srows[[length(srows) + 1L]] <- rr
        }
      }
    }
    srows <- seq_per_subject(srows, "MHSEQ")
    rows <- c(rows, srows)
    lineage[[length(lineage) + 1L]] <- trace_one(ctx, dom, "MHTERM", s$USUBJID,
                                                 dcfg$primaryDiagnosis %||% "")
  }
  list(rows = rows, lineage = lineage)
}

build_findings <- function(ctx, dom, dcfg) {
  rows <- list(); lineage <- list()
  P <- dom
  tests <- dcfg$tests
  for (s in ctx$subjects) {
    srows <- list()
    for (enc in names(ctx$visit)) {
      vinfo <- ctx$visit[[enc]]
      for (t in tests) {
        if (!(enc %in% unlist(t$occursAt))) next
        val <- if (!is.null(t$subjectAttr)) s[[t$subjectAttr]]
          else if (!is.null(t$choices)) rchoice(t$choices)  # categorical finding (e.g. PE)
          else gen_value(t$low, t$high, t$decimals)
        r <- row_base(ctx, dom, s)
        r[[paste0(P, "TESTCD")]] <- t$testcd
        r[[paste0(P, "TEST")]] <- t$test
        r[[paste0(P, "ORRES")]] <- val
        r[[paste0(P, "ORRESU")]] <- t$unit %||% ""
        r[[paste0(P, "STRESC")]] <- val
        r[[paste0(P, "STRESN")]] <- if (is_num(val)) val else ""
        r[[paste0(P, "STRESU")]] <- t$unit %||% ""
        r$VISITNUM <- vinfo$visitNum
        r$VISIT <- vinfo$label
        r$EPOCH <- coded_choice(ctx$ct, "C99079", list(vinfo$epoch))
        r[[paste0(P, "DTC")]] <- vdate(ctx, s, enc)
        r[[paste0(P, "DY")]] <- study_day(vdate(ctx, s, enc), s$rfstdtc)
        # Optional qualifiers, each emitted only when its config field is present, so the
        # builder serves VS (POS), LB (CAT/SPEC/ref-range/FAST), and PC (CAT/SPEC) alike.
        if (!is.null(t$pos)) r[[paste0(P, "POS")]] <- coded_choice(ctx$ct, "C71148", list(t$pos))
        if (!is.null(t$category)) r[[paste0(P, "CAT")]] <- t$category
        if (!is.null(t$specimen)) r[[paste0(P, "SPEC")]] <- coded_choice(ctx$ct, "C78734", list(t$specimen))
        if (!is.null(t$refLow) || !is.null(t$refHigh)) {
          r[[paste0(P, "ORNRLO")]] <- if (is.null(t$refLow)) "" else t$refLow
          r[[paste0(P, "ORNRHI")]] <- if (is.null(t$refHigh)) "" else t$refHigh
          # std-unit ref ranges == original (orig and std units coincide here)
          r[[paste0(P, "STNRLO")]] <- if (is.null(t$refLow)) "" else t$refLow
          r[[paste0(P, "STNRHI")]] <- if (is.null(t$refHigh)) "" else t$refHigh
          # reference range indicator, when the result is numeric and bounded both sides
          if (!is.null(t$refLow) && !is.null(t$refHigh) && is_num(val)) {
            nv <- as.numeric(val)
            r[[paste0(P, "NRIND")]] <- if (nv < t$refLow) "LOW" else if (nv > t$refHigh) "HIGH" else "NORMAL"
          }
        }
        if (!is.null(t$fast)) r[[paste0(P, "FAST")]] <- coded_choice(ctx$ct, "C66742", list(t$fast))
        srows[[length(srows) + 1L]] <- r
      }
    }
    # --LOBXFL: flag the last record before first study treatment, per test, "Y".
    # (Dropped at write time for domains whose template carries no --LOBXFL, e.g. PC/PE.)
    fl <- paste0(P, "LOBXFL"); dtcc <- paste0(P, "DTC"); tcc <- paste0(P, "TESTCD")
    catc <- paste0(P, "CAT")
    if (length(srows)) {
      keys <- vapply(srows, function(r) paste(r[[tcc]], r[[catc]] %||% ""), character(1))
      for (i in seq_along(srows)) srows[[i]][[fl]] <- ""
      for (k in unique(keys)) {
        idx <- which(keys == k)
        pre <- idx[vapply(idx, function(i) {
          d <- srows[[i]][[dtcc]]; !is.null(d) && d != "" && d < s$rfstdtc }, logical(1))]
        if (length(pre)) {
          dts <- vapply(pre, function(i) srows[[i]][[dtcc]], character(1))
          last <- pre[order(dts, decreasing = TRUE)[1]]  # ISO dates sort lexically
          srows[[last]][[fl]] <- "Y"
        }
      }
    }
    srows <- seq_per_subject(srows, paste0(P, "SEQ"))
    rows <- c(rows, srows)
    if (length(srows)) {
      lineage[[length(lineage) + 1L]] <- trace_one(ctx, dom, paste0(P, "ORRES"),
                                                   s$USUBJID, srows[[1]][[paste0(P, "ORRES")]])
    }
  }
  list(rows = rows, lineage = lineage)
}

# "AZD9567 72 mg" -> ("AZD9567", 72, "mg"); placebo/unparseable -> (NAME, 0, "mg").
# SDTM rule: EXTRT=PLACEBO => EXDOSE=0.
parse_dose <- function(trt) {
  parts <- strsplit(trt, " ", fixed = TRUE)[[1]]
  n <- length(parts)
  if (n >= 3 && parts[n] == "mg") {
    list(name = toupper(paste(parts[1:(n - 2)], collapse = " ")),
         dose = as.numeric(parts[n - 1]), unit = "mg")
  } else {
    list(name = toupper(trt), dose = 0, unit = "mg")
  }
}

build_ex <- function(ctx, dom, dcfg) {
  rows <- list(); lineage <- list()
  for (s in ctx$subjects) {
    srows <- list()
    for (d in s$dosing) {
      pd <- parse_dose(d$trt)
      r <- row_base(ctx, dom, s)
      r <- c(r, list(
        EXTRT = pd$name, EXDOSE = pd$dose,
        EXDOSU = coded_choice(ctx$ct, "C71620", list(pd$unit)),
        EXROUTE = coded_choice(ctx$ct, "C66729", list(ctx$route)),
        EPOCH = coded_choice(ctx$ct, "C99079", list(d$epoch)),
        EXSTDTC = as.character(d$start), EXENDTC = as.character(d$end),
        EXSTDY = study_day(as.character(d$start), s$rfstdtc),
        EXENDY = study_day(as.character(d$end), s$rfstdtc)))
      srows[[length(srows) + 1L]] <- r
    }
    srows <- seq_per_subject(srows, "EXSEQ")
    rows <- c(rows, srows)
    lineage[[length(lineage) + 1L]] <- trace_one(ctx, dom, "EXTRT", s$USUBJID, srows[[1]]$EXTRT)
  }
  list(rows = rows, lineage = lineage)
}

build_cm <- function(ctx, dom, dcfg) {
  rows <- list(); lineage <- list()
  bl <- dcfg$baseline
  extra <- dcfg$extra %||% list()
  prevalence <- ctx$knobs$conmedPrevalence %||% 0.40
  unit <- bl$unit %||% "mg"
  for (s in ctx$subjects) {
    srows <- list()
    bs <- bl$startDaysBeforeScreen
    start <- as.character(s$scr - rint(bs[[1]], bs[[2]]))
    r <- row_base(ctx, dom, s)
    r <- c(r, list(CMTRT = bl$name, CMDOSE = rchoice(bl$doses),
                   CMDOSU = coded_choice(ctx$ct, "C71620", list(unit)),
                   CMROUTE = coded_choice(ctx$ct, "C66729", list(ctx$route)),
                   CMINDC = bl$indication %||% "",
                   EPOCH = coded_choice(ctx$ct, "C99079", list("SCREENING")),
                   CMSTDTC = start, CMSTDY = study_day(start, s$rfstdtc)))
    srows[[1]] <- r
    if (length(extra$options) > 0 && stats::runif(1) < prevalence) {
      add <- rchoice(extra$options)
      es <- extra$startDaysBeforeScreen %||% list(30, 400)
      st <- as.character(s$scr - rint(es[[1]], es[[2]]))
      rr <- row_base(ctx, dom, s)
      rr <- c(rr, list(CMTRT = add$name, CMDOSE = add$dose,
                       CMDOSU = coded_choice(ctx$ct, "C71620", list(unit)),
                       CMROUTE = coded_choice(ctx$ct, "C66729", list(ctx$route)),
                       CMINDC = add$indication %||% "",
                       EPOCH = coded_choice(ctx$ct, "C99079", list("SCREENING")),
                       CMSTDTC = st, CMSTDY = study_day(st, s$rfstdtc)))
      srows[[2]] <- rr
    }
    srows <- seq_per_subject(srows, "CMSEQ")
    rows <- c(rows, srows)
    lineage[[length(lineage) + 1L]] <- trace_one(ctx, dom, "CMTRT", s$USUBJID, bl$name)
  }
  list(rows = rows, lineage = lineage)
}

build_ae <- function(ctx, dom, dcfg) {
  rows <- list(); lineage <- list()
  incidence <- ctx$knobs$aeIncidence %||% 0.55
  eps <- ctx$knobs$aeEventsPerSubject %||% list(1, 3)
  sev_w <- unlist(ctx$knobs$aeSeverityWeights %||% list(6, 3, 1))
  rel_ch <- ctx$knobs$aeRelChoices %||% list("Y", "N")
  acn_w <- unlist(ctx$knobs$aeActnWeights %||% list(8, 1, 1))
  pool <- dcfg$pool
  outcomes <- dcfg$outcomes
  open_out <- dcfg$openOutcome %||% "NOT RECOVERED/NOT RESOLVED"
  actions <- dcfg$actions
  onset_win <- dcfg$onsetWindowDays %||% list(0, 30)
  end_lag <- dcfg$endLagDays %||% list(1, 7)
  sev_vals <- ct_values(ctx$ct, "C66769")
  if (length(sev_vals) == 0) sev_vals <- c("MILD", "MODERATE", "SEVERE")
  for (s in ctx$subjects) {
    if (stats::runif(1) >= incidence) next
    srows <- list()
    for (e in seq_len(rint(eps[[1]], eps[[2]]))) {
      onset <- s$day1 + rint(onset_win[[1]], onset_win[[2]])
      # An AE cannot start after the subject has left the study (CORE-000717):
      # clamp onset to the disposition date.
      if (!is.null(s$ds_end) && onset > s$ds_end) onset <- s$ds_end
      outcome <- coded_choice(ctx$ct, "C66768", outcomes)
      endtc <- ""
      if (!identical(outcome, open_out)) {
        end_date <- onset + rint(end_lag[[1]], end_lag[[2]])
        if (!is.null(s$ds_end) && end_date > s$ds_end) end_date <- s$ds_end
        endtc <- as.character(end_date)
      }
      r <- row_base(ctx, dom, s)
      term <- rchoice(pool)
      r <- c(r, list(
        AETERM = term,
        # AEDECOD is Required. True coding needs MedDRA; absent a dictionary we pass the
        # verbatim term through (documented stopgap). The MedDRA hierarchy variables
        # (AEBODSYS/AESOC/AELLT/...) stay present-but-null until a dictionary is wired in.
        AEDECOD = term,
        AESEV = sample(sev_vals, 1L, prob = sev_w[seq_along(sev_vals)]),
        AESER = "N", AEREL = rchoice(rel_ch), AEOUT = outcome,
        AEACN = sample(unlist(actions), 1L, prob = acn_w[seq_along(actions)]),
        EPOCH = coded_choice(ctx$ct, "C99079", list("TREATMENT")),
        AESTDTC = as.character(onset), AEENDTC = endtc,
        AESTDY = study_day(as.character(onset), s$rfstdtc),
        AEENDY = study_day(endtc, s$rfstdtc)))
      srows[[length(srows) + 1L]] <- r
    }
    srows <- seq_per_subject(srows, "AESEQ")
    rows <- c(rows, srows)
    if (length(srows)) {
      lineage[[length(lineage) + 1L]] <- trace_one(ctx, dom, "AETERM", s$USUBJID,
                                                   srows[[length(srows)]]$AETERM)
    }
  }
  list(rows = rows, lineage = lineage)
}

build_ds <- function(ctx, dom, dcfg) {
  rows <- list()
  for (s in ctx$subjects) {
    ep <- if (identical(s$dsdecod, "COMPLETED")) "FOLLOW-UP" else "TREATMENT"
    r <- row_base(ctx, dom, s)
    r <- c(r, list(DSCAT = coded_choice(ctx$ct, "C74558", list("DISPOSITION EVENT")),
                   DSTERM = s$dsterm, DSDECOD = s$dsdecod,
                   EPOCH = coded_choice(ctx$ct, "C99079", list(ep)),
                   DSSTDTC = as.character(s$ds_end), DSSTDY = study_day(as.character(s$ds_end), s$rfstdtc)))
    rows[[length(rows) + 1L]] <- r
  }
  rows <- seq_per_subject(rows, "DSSEQ")
  list(rows = rows, lineage = list())
}
