#' @keywords internal
"_PACKAGE"

# Null-coalescing helper.
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

#' SDTM study day (`--DY`)
#'
#' Days from the subject reference start date, with **no day 0**: dates on or
#' after the reference are `+1`, dates before are negative. Returns `""` when
#' either date is missing or unparseable.
#'
#' @param dtc ISO-8601 date/time string (the event/collection date).
#' @param rfst ISO-8601 reference start date (`RFSTDTC`).
#' @return Integer study day, or `""`.
#' @export
study_day <- function(dtc, rfst) {
  if (is.null(dtc) || is.null(rfst) || identical(dtc, "") || identical(rfst, "")) {
    return("")
  }
  d0 <- suppressWarnings(as.Date(substr(rfst, 1, 10)))
  d1 <- suppressWarnings(as.Date(substr(dtc, 1, 10)))
  if (is.na(d0) || is.na(d1)) {
    return("")
  }
  delta <- as.integer(d1 - d0)
  if (delta >= 0) delta + 1L else delta
}

# TRUE when `v` parses as a finite number.
is_num <- function(v) {
  if (is.null(v) || length(v) != 1 || is.na(v) || identical(v, "")) {
    return(FALSE)
  }
  suppressWarnings(!is.na(as.numeric(v)))
}

# TRUE when the first 10 chars parse as an ISO-8601 date.
iso_ok <- function(v) {
  if (is.null(v) || identical(v, "")) {
    return(TRUE)
  }
  !is.na(suppressWarnings(as.Date(substr(v, 1, 10))))
}

# Random integer in [lo, hi] (safe for lo == hi, unlike base sample()).
rint <- function(lo, hi) {
  lo <- as.integer(round(lo))
  hi <- as.integer(round(hi))
  if (lo >= hi) lo else sample(lo:hi, 1L)
}

# Pick one element of a list/vector by position (avoids the sample(n) trap).
rchoice <- function(x) {
  x[[sample.int(length(x), 1L)]]
}

#' Sample a numeric result within a range
#'
#' Integer when `decimals` is `NULL`/`0`, otherwise a value rounded to
#' `decimals` places. The backbone of seed-dependent-but-bounded result values.
#'
#' @param lo,hi Inclusive bounds.
#' @param decimals Number of decimal places, or `NULL` for integer.
#' @return A numeric scalar.
#' @export
gen_value <- function(lo, hi, decimals = NULL) {
  if (is.null(decimals) || decimals == 0) {
    return(rint(lo, hi))
  }
  round(stats::runif(1, lo, hi), decimals)
}

# Format a number for a CSV cell: integers without a trailing ".0".
fmt_num <- function(v) {
  if (is.null(v) || identical(v, "")) {
    return("")
  }
  if (is.numeric(v) && v == round(v)) {
    return(format(as.integer(v), scientific = FALSE))
  }
  format(v, scientific = FALSE, trim = TRUE)
}
