# The full SDTMIG 3.4 domain inventory (63 datasets across 8 classes), with the
# generation status of each in this package. A study populates only the subset
# its protocol/SoA implies; the rest are legitimately empty for that study. This
# registry lets the pipeline report intentional omissions vs. genuine gaps, and
# mirrors Part B.2 of SDTM-INPUTS-AND-TEST-CASES.md.

# Domains with a full variable template AND a builder today (generatable now).
# PC/PE are Findings-class and reuse the generic findings builder (numeric and
# categorical results respectively).
.supported <- c("DM", "IE", "MH", "VS", "EG", "LB", "EX", "CM", "AE", "DS", "PC", "PE")

.sdtm_inventory <- local({
  cls <- function(class, ...) {
    abbr <- c(...)
    data.frame(domain = abbr, class = class, stringsAsFactors = FALSE)
  }
  inv <- rbind(
    cls("Special-Purpose", "DM", "SE", "SV", "CO", "SM"),
    cls("Interventions", "EX", "CM", "EC", "SU", "PR", "AG", "ML"),
    cls("Events", "AE", "MH", "DS", "CE", "DV", "HO", "BE"),
    cls("Findings", "VS", "LB", "EG", "IE", "PC", "PP", "IS", "QS", "PE", "SC",
        "FT", "RE", "CV", "NV", "MK", "UR", "RP", "OE", "DA", "DD", "RS", "TU",
        "TR", "MI", "MB", "MS", "CP", "GF", "SS", "BS"),
    cls("Findings About", "FA", "SR"),
    cls("Trial Design", "TS", "TA", "TE", "TV", "TI", "TD", "TM"),
    cls("Study Reference", "OI"),
    cls("Relationship", "SUPPQUAL", "RELREC", "RELSUB", "RELSPEC"))
  inv
})

#' The full SDTM domain inventory with generation status
#'
#' Every SDTMIG 3.4 domain (63 datasets across 8 observation classes) and whether
#' this package can generate it today. `supported = TRUE` means the domain has a
#' variable template (`sdtmig_template()`) and a builder. `findings_ready = TRUE`
#' marks Findings-class domains the generic findings builder can produce as soon
#' as a template entry and a config test panel are added — no new builder needed.
#'
#' A study only populates the domains its protocol/SoA implies; every other domain
#' is correctly empty for that study (see `SDTM-INPUTS-AND-TEST-CASES.md`, B.2).
#'
#' @return A data.frame with columns `domain`, `class`, `supported`,
#'   `findings_ready`.
#' @export
sdtm_domains <- function() {
  inv <- .sdtm_inventory
  inv$supported <- inv$domain %in% .supported
  inv$findings_ready <- inv$class == "Findings" & !inv$supported
  inv[order(inv$class, inv$domain), ]
}

#' Domains this package can generate today
#'
#' @return Character vector of supported domain codes.
#' @export
supported_domains <- function() .supported
