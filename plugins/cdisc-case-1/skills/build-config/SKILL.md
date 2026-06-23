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
2. Map the record into a config. Keep it **simple and general** — a minimal valid
   config for any trial:
   - `studyId`: the NCT id (`protocolSection.identificationModule.nctId`).
   - `sponsorStudyId`: org study id if present.
   - `design`: `parallel`, `crossover`, or `single-group` — infer from
     `designModule` (allocation / interventionModel). Default `parallel`.
   - `cohorts`: one per arm in `armsInterventionsModule.armGroups` (use `armcd`
     from a short uppercase code, `arm` from the label, `n: 10`, `treatments`
     from the arm's interventions). If single-arm, one cohort.
   - `demographics`: derive `ageRange` from `eligibilityModule` min/max age
     (default `[18, 75]`), `sexes` from `sex` (`["M","F"]` if ALL), and sensible
     defaults for `races`, `ethnicities`, `heightCm` `[150,190]`, `weightKg` `[50,100]`.
   - `visitGrid`: a simple 3-visit grid — `ENC_SCR` (SCREENING, dayOffset -7),
     `ENC_D1` (DAY 1, dayOffset 1, TREATMENT), `ENC_FU` (FOLLOW-UP, dayOffset 14).
   - `domains`: a small in-scope set that is always safe — `DM` (`builder: dm`),
     `VS` (`builder: findings` with a couple of vitals tests occurring at all
     three visits), `EX` (`builder: ex`), `AE` (`builder: ae`), `DS` (`builder: ds`).
   - `knobs`: sensible defaults (e.g. `aeIncidence: 0.5`, `discontinuationRate: 0.0`).
   - `sourceActivities`: optional; you may set `bcNcit: null`.
3. Write the config to BOTH `/workspace/study_config.json` (for the next step)
   and `/output/study_config.json` (a downloadable Output File).
4. **Self-validate** — the config must be consumable by synthsdtm:
   ```bash
   Rscript -e 'synthsdtm::build_spec("/workspace/study_config.json", out_dir=tempfile())' && echo CONFIG_OK
   ```
   If it errors, read the message, fix the config, and repeat until it prints
   `CONFIG_OK`. Do not finish with an invalid config.

## Constraints

- Obey the schema exactly: only listed keys (`additionalProperties: false`), all
  `required` keys present, arrays like `ageRange`/`heightCm` are 2-element pairs.
- Keep subject counts small (`n: 10` per cohort) so generation is fast.
- Do not invent CT codes; leave `bcNcit` null. Do not generate SDTM here.
