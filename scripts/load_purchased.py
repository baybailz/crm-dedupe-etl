#!/usr/bin/env python3
"""Land the next purchased company file so dbt can read it.

The ingest step. On a CDW this would be a stage: PUT the file, COPY it into a
landing table, models read that. Here a dbt seed plays the landing table.

Takes the next file off state/loaded_files.json, stamps every row with
source_file and row_num (together they make record_key), and rewrites the seed
from every file loaded so far. Rebuilding rather than appending is what makes a
re-run safe: the seed is a pure function of the state file.

  --action load_next   stage the next file in the queue (default)
  --action reset       clear the queue and empty the seed
"""

import argparse
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INCOMING = ROOT / "incoming"
STATE_FILE = ROOT / "state" / "loaded_files.json"
SEED_FILE = ROOT / "seeds" / "purchased_company.csv"

# The contract stg_purchased_company reads. Change this list and the seed,
# the record keys, and the staging model all follow from it.
STAMP_COLS = ["source_file", "row_num"]
PURCHASED_COLS = [
    "company_name", "address_1", "address_2", "address_3",
    "city", "state", "zip", "website", "primary_phone_number",
]


def stamped_rows(name: str) -> list[list[str]]:
    """One purchased file, every row tagged with its filename and line number."""
    with open(INCOMING / f"{name}.csv", newline="") as fh:
        return [[name, i] + [row.get(col, "") for col in PURCHASED_COLS]
                for i, row in enumerate(csv.DictReader(fh), start=1)]


def write_seed(loaded: list[str]) -> int:
    """Rebuild the seed from the state file. Never appends."""
    rows = [row for name in loaded for row in stamped_rows(name)]
    with open(SEED_FILE, "w", newline="") as fh:
        # Pin the line ending. Python's default is Windows-style, which would
        # rewrite every line of the seed on each run and show up in git as a
        # full-file change even when no data moved.
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(STAMP_COLS + PURCHASED_COLS)
        writer.writerows(rows)
    return len(rows)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--action", default="load_next", choices=["load_next", "reset"])
    args = ap.parse_args()

    loaded = json.loads(STATE_FILE.read_text()) if STATE_FILE.exists() else []

    if args.action == "reset":
        loaded = []
        print("[reset] queue cleared")
    else:
        queue = [f.stem for f in sorted(INCOMING.glob("*.csv")) if f.stem not in loaded]
        if queue:
            loaded.append(queue[0])
            print(f"[pickup] {queue[0]}.csv")
        else:
            print("[pickup] every file is already loaded")

    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(loaded, indent=2) + "\n")
    print(f"[seed] {write_seed(loaded)} records from {len(loaded)} file(s)")


if __name__ == "__main__":
    main()
