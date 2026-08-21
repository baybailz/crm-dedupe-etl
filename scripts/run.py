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

The landing seed and its columns are declared in docs/scenario.json, so the
seed, the record keys, and the stage model all follow from one list.
"""

import argparse
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CFG = json.loads((ROOT / "docs" / "scenario.json").read_text())
INCOMING = ROOT / "incoming"
STATE_FILE = ROOT / "state" / "loaded_files.json"
SEED_FILE = ROOT / "seeds" / f"{CFG['landing']['seed']}.csv"
STAMP_COLS = ["source_file", "row_num"]
COLS = CFG["landing"]["columns"]


def stamped_rows(name: str) -> list[list]:
    """One purchased file, every row tagged with its filename and line number."""
    with open(INCOMING / f"{name}.csv", newline="") as fh:
        return [[name, i] + [row.get(c, "") for c in COLS]
                for i, row in enumerate(csv.DictReader(fh), start=1)]


def write_seed(loaded: list[str]) -> int:
    """Rebuild the seed from the state file. Never appends."""
    rows = [r for name in loaded for r in stamped_rows(name)]
    with open(SEED_FILE, "w", newline="") as fh:
        # Pin the line ending. Python's default is Windows-style, which would
        # rewrite every line of the seed on each run and show up in git as a
        # full-file change even when no data moved.
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(STAMP_COLS + COLS)
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
