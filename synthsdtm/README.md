# synthsdtm

Parametrized synthetic SDTM simulator — an R package. The **study is data, not
code**: one config-driven engine generates CDISC SDTMIG 3.4-shaped datasets for
any protocol, so adapting to a new study means writing a new `study_config.json`,
never editing R.

```
1. EXTRACT & PLAN   protocol PDF → study_config.json   +  build_spec() → spec + CT
2. GENERATE         simulate_sdtm(config, spec, ct, n, seed) → SDTM data.frames
3. CHECK            check_sdtm()  → T1 Shape · T2 Conformance · T3 Cross-domain  (gate)
                    export_xpt() + digest_core()  → XPT v5 + CDISC CORE          (optional)
```

Determinism contract: **`SDTM = simulate_sdtm(config, spec, ct, n, seed)`** — same
inputs + seed ⇒ identical output. Shape-domain row counts (DM, IE, EX, DS,
findings) are a closed-form function of the structural inputs and seed-independent;
value cells are seed-dependent but bounded. `check_sdtm()` recomputes the expected
shape from the config and asserts on it.

## Install / load

```r
# from the package directory
devtools::install(".")        # or devtools::load_all(".") during development
library(synthsdtm)
```

Requires `jsonlite`; `haven` for XPT export; `testthat`/`withr` for the tests.

## Use from R

```r
cfg   <- system.file("configs", "NCT04556760.json", package = "synthsdtm")
built <- build_spec(cfg, out_dir = "runs/ref/config")      # spec + pinned CT (offline)
res   <- simulate_sdtm(cfg, built$spec, built$ct_cache, n_subjects = 40, seed = 1234)
write_sdtm(res, "runs/ref/sdtm")
rep   <- check_sdtm(cfg, built$spec, built$ct_cache,
                    run_dir = "runs/ref/sdtm", n_subjects = 40, seed = 1234)
stopifnot(rep$allPass)
```

Expected (seed-independent, exact): `DM 40 · IE 2 · VS 720 · EG 640 · LB 2080 ·
EX 80 · DS 40`. Seed-dependent (MH/CM/AE) land within documented bounds.

## Use from the command line

Installed scripts under `inst/scripts/` (resolve with `system.file("scripts", ...)`):

```bash
Rscript build_spec.R --config <cfg.json> --out runs/ref/config
Rscript simulate.R   --config <cfg.json> --spec runs/ref/config/sdtm_spec.json \
    --ct-cache runs/ref/config/ct_cache.json --subjects 40 --seed 1234 --out runs/ref/sdtm
Rscript check.R      --config <cfg.json> --spec runs/ref/config/sdtm_spec.json \
    --ct-cache runs/ref/config/ct_cache.json --run runs/ref/sdtm --subjects 40 --seed 1234
```

## The study_config.json contract

Captures every structural driver and rate knob (see
`../SDTM-INPUTS-AND-TEST-CASES.md`):

| Section | Drives |
|---|---|
| `cohorts[]` (armcd, arm, n, treatments) | DM ARM/ARMCD, EX, cohort split (Σn scaled to `n_subjects`) |
| `design` + `periods[]` | EX rows/subject (crossover ⇒ N×periods, parallel ⇒ N), EPOCH |
| `visitGrid` (encounter → dayOffset, visitNum, epoch) | every `--DTC`/`VISIT`/`--DY` — the findings column axis |
| `demographics` | DM AGE/SEX/RACE/ETHNIC, height/weight |
| `domains.<D>.tests[]` (testcd, unit, low/high, occursAt, category/specimen/fast/refRange) | findings row count `N·Σ\|occursAt\|` + value ranges |
| `knobs` | discontinuation, AE incidence/events, conmed prevalence, comorbidity count, IE exceptions |
| `sourceActivities` | per-domain provenance (activity id + protocol page) for lineage |

Builders: `dm, ie, mh, ex, cm, ae, ds` (bespoke) + one generic `findings` builder
reused for VS/EG/LB.

## Domain coverage — why only some domains are generated

A study **does not** populate all 63 SDTMIG 3.4 domains, and it shouldn't. Each
study populates only the subset its protocol/Schedule-of-Activities implies; every
other domain is *legitimately empty* for that study (this is a CDISC principle, not
a limitation — see `../SDTM-INPUTS-AND-TEST-CASES.md` §B.2). The reference protocol
NCT04556760 implies exactly **10** domains, so 10 are generated — that is complete
coverage *for that protocol*, and test **G-03** asserts the omissions are intentional.

What the *package* can generate today (independent of any one protocol):

| Status | Domains | Notes |
|---|---|---|
| **Generated now** (template + builder) | `DM IE MH VS EG LB EX CM AE DS PC PE` | `supported_domains()` |
| **Findings-ready** (generic builder; just add a template entry + config panel) | every other Findings-class domain — `PP IS QS SC FT RE …` | no new builder needed; the generic builder handles numeric (PC) and categorical (PE, via a test `choices` list) results |
| **Needs a builder** | other Events / Interventions / Special-Purpose / Trial-Design / Relationship domains — e.g. `SU` (Substance Use, Interventions-class) | small bespoke builder + template |
| **Therapeutic-area-specific** | oncology `TU/TR/RS`, micro `MB/MS`, … | only meaningful with a TA config |

`sdtm_domains()` returns the **full 63-domain inventory** with each domain's class
and `supported`/`findings_ready` status, so scope decisions are explicit and
auditable rather than implicit. If a config declares a domain with no template yet,
`build_spec()` fails fast with a message pointing at `sdtm_domains()` and explaining
the Findings shortcut.

**To add a domain:** add its ordered variable list to `sdtmig_template()` in
`R/spec.R`, then give the config a `domains.<D>` block. Findings-class domains reuse
`build_findings` as-is; other classes get a short builder in `R/builders.R`.

## Tests & CT

`testthat::test_dir("tests/testthat")` (or `R CMD check`) builds the spec, runs the
full pipeline on the bundled reference and parallel-toy configs, and asserts the
exact shape + all T1/T2/T3 checks. CT is resolved from the pinned offline snapshot
(`inst/extdata/ct/sdtmct-2026-03-27.json`) — the canonical reproducible path. The
snapshot bundles **every codelist referenced by the supported domains** (so all
`<DOM>-CT-<var>` conformance checks resolve offline — no API key needed); a few codes
retired from the pinned CT package (RACE, ETHNIC, LBSTRESC) are carried from the most
recent prior package and tagged with `sourcePackage`. Regenerate or extend it with:

```bash
CDISC_API_KEY=... Rscript inst/scripts/build_ct_snapshot.R   # add --all for all 63 domains
```

If a config references a codelist the snapshot lacks, `build_spec()` warns and names it
(rather than silently skipping that variable's CT check).

## Optional: CDISC CORE conformance

```r
export_xpt("runs/ref/sdtm", built$spec, "runs/ref/sdtm_xpt")   # haven::write_xpt, v5
# run CORE on the XPT against SDTMIG 3.4 + pinned CT, then:
digest_core("runs/ref/core_report/core.json", "runs/ref/core_report/summary.json")
```

`digest_core()` classifies findings as `data_bug` (fix the config and regenerate),
`tabulation_gap`, or `harness`.
