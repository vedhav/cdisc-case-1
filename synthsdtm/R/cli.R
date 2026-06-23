# Minimal `--key value` / `--flag` command-line parser, so the installed scripts
# need no external dependency (optparse et al.).

#' Parse `--key value` command-line arguments
#'
#' @param args Character vector (defaults to [commandArgs()] trailing args).
#' @param flags Names of boolean flags that take no value.
#' @return A named list of parsed values (flags are `TRUE`/absent).
#' @export
parse_cli <- function(args = commandArgs(trailingOnly = TRUE), flags = character(0)) {
  out <- list()
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (startsWith(a, "--")) {
      key <- sub("^--", "", a)
      if (key %in% flags) {
        out[[key]] <- TRUE; i <- i + 1L
      } else {
        out[[key]] <- args[[i + 1L]]; i <- i + 2L
      }
    } else {
      i <- i + 1L
    }
  }
  out
}
