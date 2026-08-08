#!/usr/bin/env python3
"""Pick up the next pending vendor file, one at a time.

Vendor CSVs sit in incoming/. state/loaded_files.json records which ones have
been loaded, in order. Each run of --action load_next appends the next pending
file (alphabetical) to the state, then regenerates seeds/vendor_records.csv:
the concatenation of every loaded file, stamped with source_file and the
original file row number. dbt models read only that seed, so "what has been
loaded so far" is fully described by the state file and reproducible from it.

    python scripts/load_next.py --action load_next   # load one more file
    python scripts/load_next.py --action reset       # back to zero files
    python scripts/load_next.py --action rebuild     # regenerate seed only
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
SEED_COLS = ["source_file", "row_num"] + VENDOR_COLS


def read_state() -> list[str]:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return []


def write_state(loaded: list[str]) -> None:
    STATE_FILE.parent.mkdir(exist_ok=True)
    STATE_FILE.write_text(json.dumps(loaded, indent=2) + "\n")


def pending(loaded: list[str]) -> list[str]:
    all_files = sorted(p.stem for p in INCOMING.glob("*.csv"))
    return [f for f in all_files if f not in loaded]


def rebuild_seed(loaded: list[str]) -> int:
    rows_out = []
    for name in loaded:
        with open(INCOMING / f"{name}.csv", newline="") as fh:
            for i, row in enumerate(csv.DictReader(fh), start=1):
                rows_out.append([name, i] + [row.get(c, "") for c in VENDOR_COLS])
    with open(SEED_FILE, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(SEED_COLS)
        w.writerows(rows_out)
    return len(rows_out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--action", default="load_next",
                    choices=["load_next", "reset", "rebuild"])
    args = ap.parse_args()

    loaded = read_state()
    if args.action == "reset":
        loaded = []
    elif args.action == "load_next":
        queue = pending(loaded)
        if not queue:
            print("nothing to load: all incoming files already loaded")
        else:
            loaded = loaded + [queue[0]]
            print(f"picked up: {queue[0]}.csv")

    write_state(loaded)
    n = rebuild_seed(loaded)
    print(f"loaded files: {loaded or 'none'} -> {n} vendor records in "
          f"{SEED_FILE.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
