# Controlled Terminology helpers. CT is a named list keyed by NCIt code; each
# entry has a `terms` list of records carrying `submissionValue`.

# All submission values for a codelist (character(0) if absent / unresolved).
ct_values <- function(ct, ncit) {
  if (is.null(ncit) || is.null(ct[[ncit]])) {
    return(character(0))
  }
  vapply(ct[[ncit]]$terms, function(t) t$submissionValue %||% "", character(1))
}

# Set of submission values (for membership checks).
ct_set <- function(ct, ncit) unique(ct_values(ct, ncit))

# Pick a CT submission value, restricted to `subset` when given (and present in
# the codelist). Falls back to the declared subset if the codelist is unresolved,
# so the engine still produces sensible coded values offline.
coded_choice <- function(ct, ncit, subset = NULL) {
  allowed <- ct_values(ct, ncit)
  if (!is.null(subset)) {
    inter <- subset[vapply(subset, function(s) length(allowed) == 0 || s %in% allowed, logical(1))]
    pool <- if (length(inter)) inter else subset
  } else {
    pool <- allowed
  }
  if (length(pool) == 0) "" else rchoice(as.list(pool))
}
