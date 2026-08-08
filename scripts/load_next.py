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


def log(label: str, msg: str) -> None:
    print(f"[{label}] {msg:<0}", flush=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--action", default="load_next",
                    choices=["load_next", "reset", "rebuild"])
    args = ap.parse_args()

    loaded = read_state()
    all_files = sorted(p.stem for p in INCOMING.glob("*.csv"))
    log("scan", f"incoming/ has {len(all_files)} vendor files: "
                + ", ".join(f + ".csv" for f in all_files))
    log("state", f"{len(loaded)} loaded, {len(pending(loaded))} pending "
                 f"({STATE_FILE.relative_to(ROOT)})")

    if args.action == "reset":
        log("reset", "clearing load state — CRM demo returns to its original companies")
        loaded = []
    elif args.action == "load_next":
        queue = pending(loaded)
        if not queue:
            log("pickup", "nothing to do: every incoming file is already loaded")
        else:
            name = queue[0]
            with open(INCOMING / f"{name}.csv", newline="") as fh:
                n_rows = sum(1 for _ in csv.DictReader(fh))
            log("pickup", f"next in queue: {name}.csv ({n_rows} records)")
            loaded = loaded + [name]

    write_state(loaded)
    n = rebuild_seed(loaded)
    log("seed", f"rebuilt {SEED_FILE.relative_to(ROOT)}: {n} vendor records "
                f"from {len(loaded)} file(s), stamped with source_file + row_num")
    log("done", "handing off to dbt build for dedupe + tests")


if __name__ == "__main__":
    main()
