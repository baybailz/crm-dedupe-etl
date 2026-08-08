#!/usr/bin/env python3
"""Export pipeline results to docs/data/*.json for the GitHub Pages console.

Run after `dbt build`. Reads the DuckDB file the demo target produces, plus
the loader state and the incoming/ directory, and writes:

    summary.json               KPIs, file queue, next file name, timestamp
    company.json               select * from company_post_import (final table)
    record_status.json         every vendor record + disposition
    potential_duplicates.json  the pair-level duplicate report
    next_file.json             raw preview of the next pending file
    logs.json                  captured stdout of the load + dbt steps
                               (--python-log / --dbt-log / --action)
"""

import argparse
import csv
import json
from datetime import datetime, timezone
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "data"
DB = ROOT / "crm_dedupe.duckdb"
STATE_FILE = ROOT / "state" / "loaded_files.json"
INCOMING = ROOT / "incoming"


def rows_of(con, sql: str) -> list[dict]:
    cur = con.execute(sql)
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def read_log(path: str | None) -> str:
    if path and Path(path).exists():
        return Path(path).read_text(errors="replace").rstrip()
    return ""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--python-log")
    ap.add_argument("--dbt-log")
    ap.add_argument("--action", default="load_next")
    args = ap.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(DB), read_only=True)

    company = rows_of(con, """
        select * from main.company_post_import order by company_id
    """)
    record_status = rows_of(con, """
        select * from main.record_status order by record_key
    """)
    dupes = rows_of(con, """
        select * from main.potential_duplicates order by record_key
    """)
    con.close()

    loaded = json.loads(STATE_FILE.read_text()) if STATE_FILE.exists() else []
    all_files = sorted(p.stem for p in INCOMING.glob("*.csv"))
    queue = [f for f in all_files if f not in loaded]
    next_file = queue[0] if queue else None

    next_rows = []
    if next_file:
        with open(INCOMING / f"{next_file}.csv", newline="") as fh:
            next_rows = list(csv.DictReader(fh))

    status_counts: dict[str, int] = {}
    for r in record_status:
        status_counts[r["status"]] = status_counts.get(r["status"], 0) + 1

    summary = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "companies_total": len(company),
        "companies_imported": sum(1 for c in company if c["record_source"] != "crm"),
        "records_processed": len(record_status),
        "duplicates_blocked": sum(
            v for k, v in status_counts.items() if k.startswith("duplicate")),
        "needs_review": status_counts.get("needs_review", 0),
        "status_counts": status_counts,
        "files_loaded": loaded,
        "files_pending": queue,
        "next_file": next_file,
    }

    logs = {
        "generated_at": summary["generated_at"],
        "action": args.action,
        "loaded_file": loaded[-1] if (args.action == "load_next" and loaded) else None,
        "python": read_log(args.python_log),
        "dbt": read_log(args.dbt_log),
    }

    for name, payload in [
        ("summary.json", summary),
        ("company.json", company),
        ("record_status.json", record_status),
        ("potential_duplicates.json", dupes),
        ("next_file.json", {"name": next_file, "rows": next_rows}),
        ("logs.json", logs),
    ]:
        (OUT / name).write_text(json.dumps(payload, indent=1, default=str) + "\n")
        print(f"wrote docs/data/{name}")


if __name__ == "__main__":
    main()
