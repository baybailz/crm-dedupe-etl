#!/usr/bin/env python3
"""Extract the full-load snapshot the presentation renders.

The demo runs incrementally, so its published tables reflect however many
files are loaded right now. The deck needs the complete picture, so this
loads every incoming file, builds, extracts, then restores the state it
found and rebuilds. Nothing on a slide is hand-written: every row comes
from a real run of the same models.

Writes docs/data/presentation.json. Run it in CI after export_json.py.
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
STATE_FILE = ROOT / "state" / "loaded_files.json"
SEED_FILE = ROOT / "seeds" / "vendor_records.csv"
INCOMING = ROOT / "incoming"
OUT = ROOT / "docs" / "data" / "presentation.json"

UNION_SQL = """
select * from (
    select
        stg_company.company_name,
        stg_company.address,
        stg_company.city,
        stg_company.state,
        stg_company.zip,
        stg_company.phone_number,
        'crm_company'            as source,
        stg_company.name_match   as cluster_key
    from main.stg_company

    union all

    select
        stg_purchased_company.company_name,
        stg_purchased_company.address_1,
        stg_purchased_company.city,
        stg_purchased_company.state,
        stg_purchased_company.zip,
        stg_purchased_company.primary_phone_number,
        stg_purchased_company.source_file || '.csv' as source,
        stg_purchased_company.name_match
    from main.stg_purchased_company
) as unioned
order by cluster_key,
         case when source = 'crm_company' then 0 else 1 end,
         source
"""


def run(*args: str) -> None:
    subprocess.run(args, cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)


def dbt_build() -> None:
    dbt = shutil.which("dbt") or str(Path(sys.executable).parent / "dbt")
    run(dbt, "build", "--select", "tag:master_data", "--full-refresh")


def stage(action: str) -> None:
    run(sys.executable, str(ROOT / "scripts" / "stage_for_dbt.py"),
        "--action", action)


def main() -> None:
    saved_state = STATE_FILE.read_text() if STATE_FILE.exists() else "[]\n"
    saved_seed = SEED_FILE.read_text() if SEED_FILE.exists() else ""
    try:
        for _ in sorted(INCOMING.glob("*.csv")):
            stage("load_next")
        dbt_build()

        with duckdb.connect(str(ROOT / "crm_dedupe.duckdb"),
                            read_only=True) as con:
            cur = con.execute(UNION_SQL)
            cols = [d[0] for d in cur.description]
            rows = [dict(zip(cols, r)) for r in cur.fetchall()]
        master = sum(1 for r in rows if r["source"] == "crm_company")

        relations = [
            "crm_company", "vendor_records", "company_name_aliases",
            "stg_company", "stg_purchased_company", "trn_scored_pairs",
            "dim_company_duplicates", "dim_record_status",
            "dim_company_purchased", "dim_company",
        ]
        model_data = {}
        with duckdb.connect(str(ROOT / "crm_dedupe.duckdb"),
                            read_only=True) as con:
            for rel in relations:
                cur = con.execute(f"select * from main.{rel} order by all limit 120")
                cols = [d[0] for d in cur.description]
                model_data[rel] = [dict(zip(cols, r)) for r in cur.fetchall()]

        seen: dict[str, int] = {}
        for r in rows:
            seen[r["cluster_key"]] = seen.get(r["cluster_key"], 0) + 1
        for r in rows:
            r["in_cluster"] = seen[r["cluster_key"]] > 1

        OUT.write_text(json.dumps({
            "rows": rows,
            "total": len(rows),
            "master": master,
            "purchased": len(rows) - master,
            "model_data": model_data,
        }, indent=1, default=str) + "\n")
        print(f"wrote {OUT.relative_to(ROOT)}: {len(rows)} rows "
              f"({master} master + {len(rows) - master} purchased)")
    finally:
        STATE_FILE.write_text(saved_state)
        SEED_FILE.write_text(saved_seed)
        dbt_build()
        print("restored the demo state")


if __name__ == "__main__":
    main()
