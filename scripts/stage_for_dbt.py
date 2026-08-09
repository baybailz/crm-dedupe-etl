#!/usr/bin/env python3
"""Stage one vendor CSV as the dbt seed (demo path).

Takes the next file from incoming/, stamps every row with its source file
and line number, and writes seeds/vendor_records.csv from every file loaded
so far. state/loaded_files.json is the record of what is loaded, in order.

Rebuilding the seed from that state, rather than appending to it, is what
makes the step safe to repeat: the seed is always a pure function of the
state file, so a re-run cannot double-load anything.
"""

import argparse
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INCOMING = ROOT / "incoming"
STATE_FILE = ROOT / "state" / "loaded_files.json"
SEED_FILE = ROOT / "seeds" / "vendor_records.csv"

VENDOR_COLS = [
    "company_name", "address_1", "address_2", "address_3",
    "city", "state", "zip", "website", "primary_phone_number",
]


def stamped_rows(name: str) -> list[list[str]]:
    """One vendor file, every row tagged with its filename and line number."""
    with open(INCOMING / f"{name}.csv", newline="") as fh:
        return [[name, i] + [row.get(col, "") for col in VENDOR_COLS]
                for i, row in enumerate(csv.DictReader(fh), start=1)]


def write_seed(loaded: list[str]) -> int:
    rows = [row for name in loaded for row in stamped_rows(name)]
    with open(SEED_FILE, "w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["source_file", "row_num"] + VENDOR_COLS)
        writer.writerows(rows)
    return len(rows)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--action", default="load_next",
                    choices=["load_next", "reset"])
    action = ap.parse_args().action

    loaded = json.loads(STATE_FILE.read_text()) if STATE_FILE.exists() else []

    if action == "reset":
        loaded = []
        print("[reset] queue cleared")
    else:
        queue = [f.stem for f in sorted(INCOMING.glob("*.csv"))
                 if f.stem not in loaded]
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
