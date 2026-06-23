#!/usr/bin/env python3
"""Step 2 (fetch): pull a ClinicalTrials.gov v2 study record by NCT id.

Reads {"nctId": ...} from /output/input.json (the human step's output), GETs the
public CT.gov API (no key), and writes the record to /workspace/study.json (for
the next step) and /output/study.json (downloadable).
"""

from __future__ import annotations

import json
import urllib.request
from pathlib import Path

OUTPUT_DIR = Path("/output")
WORKSPACE_DIR = Path("/workspace")
API = "https://clinicaltrials.gov/api/v2/studies"


def read_nct_id() -> str:
    input_path = OUTPUT_DIR / "input.json"
    step_input = json.loads(input_path.read_text(encoding="utf-8")) if input_path.exists() else {}
    nct = step_input.get("nctId")
    if not isinstance(nct, str) or not nct.strip():
        raise SystemExit("No 'nctId' found in /output/input.json — the human step must provide one.")
    nct = nct.strip().upper()
    if not nct.startswith("NCT"):
        raise SystemExit(f"Invalid NCT id '{nct}' (expected to start with 'NCT').")
    return nct


def main() -> None:
    nct = read_nct_id()
    url = f"{API}/{nct}?format=json"
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            record = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raise SystemExit(f"CT.gov returned HTTP {error.code} for {nct} — check the NCT id.") from None

    WORKSPACE_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(record, indent=2)
    (WORKSPACE_DIR / "study.json").write_text(payload, encoding="utf-8")
    (OUTPUT_DIR / "study.json").write_text(payload, encoding="utf-8")

    title = (
        record.get("protocolSection", {})
        .get("identificationModule", {})
        .get("briefTitle", "(no title)")
    )
    (OUTPUT_DIR / "result.json").write_text(
        json.dumps({"status": "success", "nctId": nct, "title": title}, indent=2),
        encoding="utf-8",
    )
    print(f"Fetched {nct}: {title}")


if __name__ == "__main__":
    main()
