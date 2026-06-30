---
name: build-config
description: "Turn a ClinicalTrials.gov v2 study record into a synthsdtm study_config.json. Use this when /workspace/study.json (a CT.gov record) exists and the next step needs a config the synthsdtm R package can consume. Maps design, arms, eligibility and a simple visit grid into the config schema, then self-validates by running build_spec. Triggers: 'build config', 'study config', 'map study to config', 'synthsdtm config'."
---

# Build synthsdtm study_config

## Purpose

Produce `study_config.json` — the single machine-readable input the `synthsdtm`
package needs to generate synthetic SDTM. You map the CT.gov record into the
config schema; you do NOT generate SDTM here (that is the next, deterministic step).

## Inputs

- `/workspace/study.json` — a ClinicalTrials.gov API v2 study record (from the fetch step).

## Reference (read these first, from the installed package)

```bash
SCHEMA=$(Rscript -e 'cat(system.file("schema/study_config.schema.json", package="synthsdtm"))')
EXAMPLE=$(Rscript -e 'cat(system.file("configs/toy_parallel.json", package="synthsdtm"))')
cat "$SCHEMA"     # the authoritative contract — obey `required` and `additionalProperties:false`
cat "$EXAMPLE"    # a minimal, valid config to mirror
```

## Workflow

1. Read `/workspace/study.json` and the schema + example above.
2. **Start from `toy_parallel.json` as the template and keep ALL of its
   structural fields** — `studyStart`, `screenLagDays`, `enrollmentWindowDays`,
   `periods`, `knobs`, and `sourceActivities`. These are required for generation:
   omitting `studyStart`/`screenLagDays`/`enrollmentWindowDays`/`periods` leaves
   subjects with no day-1 date and `simulate_sdtm` fails. Then change only the
   study-specific values below. Keep it simple and general:
   - `studyId`: the NCT id (`protocolSection.identificationModule.nctId`).
   - `sponsorStudyId`: org study id if present.
   - `design`: `parallel`, `crossover`, or `single-group` — infer from
     `designModule` (allocation / interventionModel). Default `parallel`.
   - `cohorts`: one per arm in `armsInterventionsModule.armGroups` (use `armcd`
     from a short uppercase code, `arm` from the label, `treatments`
     from the arm's interventions). If single-arm, one cohort. Set each cohort's
     `n` by distributing the **trial's real enrollment** across the arms so the
     synthetic study reflects *this* trial, not a fixed template:
     - Read `enrollment` from `protocolSection.designModule.enrollmentInfo.count`.
     - `target = min(enrollment, 100)` — cap at 100 so generation + CORE stay fast.
       If `enrollmentInfo.count` is missing or smaller than the number of arms,
       use `target = 10 × (number of arms)` as a fallback.
     - Split `target` as evenly as possible across the arms, every cohort `n ≥ 1`,
       and give the remainder to the first cohort(s) so `Σ n == target`.
       (e.g. enrollment 246, 3 arms → target 100 → `n` = 34, 33, 33.)
   - `demographics`: derive `ageRange` from `eligibilityModule` min/max age
     (default `[18, 75]`), `sexes` from `sex` (`["M","F"]` if ALL), and sensible
     defaults for `races`, `ethnicities`, `heightCm` `[150,190]`, `weightKg` `[50,100]`.
   - `visitGrid`: a simple 3-visit grid — `ENC_SCR` (SCREENING, dayOffset -7),
     `ENC_D1` (DAY 1, dayOffset 1, TREATMENT), `ENC_FU` (FOLLOW-UP, dayOffset 14).
   - `domains`: a small in-scope set that is always safe — `DM` (`builder: dm`),
     `VS` (`builder: findings` with a couple of vitals tests occurring at all
     three visits), `EX` (`builder: ex`), `AE` (`builder: ae`), `DS` (`builder: ds`).
     **Every `findings` test MUST set numeric `low` and `high` and a `unit`** (e.g.
     SYSBP 100–150 mmHg, PULSE 55–95 beats/min). Never leave `low`/`high` null and
     never use an empty array for any field — the generator needs real bounds.
   - `knobs`: sensible defaults (e.g. `aeIncidence: 0.5`, `discontinuationRate: 0.0`).
   - `sourceActivities`: optional; you may set `bcNcit: null`.
3. Write the config to BOTH `/workspace/study_config.json` (for the next step)
   and `/output/study_config.json` (a downloadable Output File).
4. **Self-validate** — the config must both resolve a spec AND generate without
   error (build_spec alone is not enough — generation can still fail on, e.g., a
   findings test with missing bounds):
   ```bash
   Rscript -e 'cfg<-"/workspace/study_config.json"; b<-synthsdtm::build_spec(cfg,out_dir=tempfile()); synthsdtm::simulate_sdtm(cfg,b$spec,ct=b$ct_cache,n_subjects=4); cat("CONFIG_OK\n")'
   ```
   If it errors, read the message, fix the config, and repeat until it prints
   `CONFIG_OK`. Do not finish with a config that fails this check.

## Constraints

- Obey the schema exactly: only listed keys (`additionalProperties: false`), all
  `required` keys present, arrays like `ageRange`/`heightCm` are 2-element pairs.
- Cohort `n` comes from the trial's enrollment (`enrollmentInfo.count`), capped at
  100 total and split across arms — never a fixed per-cohort number. The cap keeps
  generation fast while letting subject counts vary by trial.
- Do not invent CT codes; leave `bcNcit` null. Do not generate SDTM here.
