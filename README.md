# cdisc-case-1 — NCT id → synthetic SDTM

A simplified mediforce workflow: from a ClinicalTrials.gov NCT id, generate
synthetic SDTM datasets with the `synthsdtm` R package and validate them with
CDISC CORE. Datasets land in `/output` for download.

## Steps

| # | Step | executor / plugin | What it does |
|---|------|-------------------|--------------|
| 1 | Provide NCT id | `human` | enter an NCT id |
| 2 | Fetch Study Record | `script` | GET the CT.gov v2 record (deterministic, no key) → `study.json` |
| 3 | Build Study Config | `agent` + `build-config` skill | map the record into a `synthsdtm` `study_config.json` (self-validates with `build_spec`) |
| 4 | Generate + Validate SDTM | `script` (R) | `build_spec → simulate_sdtm → write_sdtm → check_sdtm → export_xpt → core validate → digest_core` |

This collapses the original 6-stage pipeline (extract-USDM → match-BC → human
review → build-config) into **one** `build-config` agent step, because
`synthsdtm` only needs a `study_config.json` — it does not fetch CT.gov or do
USDM/BC mapping itself.

## Layout

```
synthsdtm/                       the R package (installed in the image)
container/fetch.py               step 2 (CT.gov fetch)
container/generate.R             step 4 (synthsdtm pipeline + CORE)
plugins/cdisc-case-1/skills/build-config/SKILL.md   step 3 skill
Dockerfile                       golden + synthsdtm + CORE (as `core`)
src/cdisc-case-1.wd.json         the workflow definition
```

## Key wiring (lessons baked in)

- **Image** is built lazily from each step's `repo`+`commit`+`dockerfile`+`repoAuth`
  (HTTPS-token clone, avoids the staging SSH deploy-key issue).
- **Skill** is read at run time from the top-level **`externalSkillsRepo`**
  (url + commit + auth) via `skillsDir` — not the per-step image repo.
- **Downloadable artifacts** are written to **`/output`** (the SDTM CSVs go to
  `/output/sdtm/`, XPT to `/output/xpt/`, CORE report to `/output/core_report/`).
  `/workspace` is only for passing data between steps.
- **CORE** is installed from `cdisc-rules-engine` and exposed as the `core`
  command; it runs offline against the engine's bundled cache (no `CDISC_API_KEY`).

## Secrets (namespace, on the target instance)

| Secret | Used by |
| ------ | ------- |
| `GITHUB_TOKEN` | image build + skill clone (all container/agent steps) |
| `OPENROUTER_API_KEY` | the `build-config` agent step |

## Runbook

Run the CLI from a mediforce checkout **on `main`**.

```bash
cd /Users/vedha/Repo/cdisc-case-1
git init && git add -A && git commit -m "cdisc-case-1: NCT id -> synthetic SDTM"
gh repo create cdisc-case-1 --public --source=. --push
git rev-parse HEAD          # set this SHA into every commit field + externalSkillsRepo in src/cdisc-case-1.wd.json

BASE=https://staging.mediforce.ai/
MEDIFORCE_API_KEY=$(cat ~/.config/mediforce/staging-key) \
pnpm exec mediforce workflow register --file=src/cdisc-case-1.wd.json --namespace=vedha --base-url=$BASE

MEDIFORCE_API_KEY=$(cat ~/.config/mediforce/staging-key) \
pnpm exec mediforce run start --workflow=cdisc-case-1 --namespace=vedha --base-url=$BASE
```

Then complete **Provide NCT id** in the UI (e.g. `NCT04556760`). Steps 2–4 run
automatically; the SDTM datasets appear as downloads on the **Generate + Validate
SDTM** step.
