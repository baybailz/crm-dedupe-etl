"""Scenario hooks for export_json.py.

summary(con, ctx)  -> dict merged into summary.json (the headline numbers)
history(con, ctx)  -> dict: one cell per pipeline step key in scenario.json,
                      plus anything else the console's log row wants.
extra(ctx)         -> {"name.json": payload} for anything else the page wants.
ctx has: action, loaded, queue, next_file, passed, failed, cfg
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# The project as it stood before this request, for the deck's V1/V2 toggle.
# Left value is where the file sits in the project; right is what to read.
V1_FILES = [
    ("dbt_project.yml", "baseline/dbt_project.yml"),
    ("profiles.yml", "profiles.yml"),
    ("macros/normalize.sql", "baseline/macros/normalize.sql"),
    ("seeds/schema.yml", "baseline/seeds/schema.yml"),
    ("seeds/crm_company.csv", "seeds/crm_company.csv"),
    ("models/stage/schema.yml", "baseline/models/stage/schema.yml"),
    ("models/stage/stg_company.sql", "baseline/models/stage/stg_company.sql"),
    ("models/conformed/schema.yml", "baseline/models/conformed/schema.yml"),
    ("models/conformed/dim_company.sql", "baseline/models/conformed/dim_company.sql"),
]
V1_NODES = [
    {"id": "crm_company", "layer": "seed"},
    {"id": "stg_company", "layer": "stage"},
    {"id": "dim_company", "layer": "conformed"},
]
V1_EDGES = [["crm_company", "stg_company"], ["stg_company", "dim_company"]]


def summary(con, ctx) -> dict:
    total, imported = con.execute(
        "select count(*), count(*) filter (where source <> 'crm_company') "
        "from main.dim_company").fetchone()
    status_counts = dict(con.execute(
        "select status, count(*) from main.dim_record_status group by status").fetchall())
    return {
        "companies_total": total,
        "companies_imported": imported,
        "records_processed": sum(status_counts.values()),
        "duplicates_blocked": sum(v for k, v in status_counts.items()
                                  if k.startswith("duplicate")),
        "status_counts": status_counts,
    }


def history(con, ctx) -> dict:
    """One row of the console's pipeline log, in the operator's words."""
    reset = ctx["action"] == "reset"
    last = None if reset else (ctx["loaded"][-1] if ctx["loaded"] else None)
    total = con.execute("select count(*) from main.dim_company").fetchone()[0]
    added = con.execute(
        "select count(*) from main.dim_record_status "
        "where status = 'new' and source_file = ?", [last]).fetchone()[0] if last else 0

    if reset:
        python, out = "reset · queue cleared", f"dim_company → {total} records"
    elif last:
        python, out = f"loaded {last}.csv", f"dim_company → added {added} records"
    else:
        python, out = "nothing left to load", "—"
    dbt = (f"dbt build --select {ctx['cfg']['dbt_select']} · PASS={ctx['passed']}"
           if ctx["passed"] else "—")
    return {"python": python, "dbt": dbt, "out": out,
            "loaded_file": last, "added": added, "companies_total": total}


def extra(ctx) -> dict:
    """v1.json: the project before this request, files and lineage."""
    return {"v1.json": {
        "files": [{"path": shown, "sql": (ROOT / src).read_text()}
                  for shown, src in V1_FILES],
        "nodes": V1_NODES,
        "edges": V1_EDGES,
    }}
