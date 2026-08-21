#!/usr/bin/env python3
"""Write docs/data/*.json for the web console. Run after dbt build.

    summary.json     queue state, row counts, scenario headline numbers
    tables.json      {table: rows} for every table in scenario.json export.tables
    next_file.json   preview of the next pending incoming file
    logs.json        run history (one entry per run) + raw step logs
    models.json      project source for the code browser (+ compiled Jinja)
    model_data.json  row samples behind every model, for the play button
    lineage.json     nodes + edges from the dbt manifest, for the DAG slide
"""

import argparse
import csv
import importlib.util
import json
import re
from datetime import datetime, timezone
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "data"
CFG = json.loads((ROOT / "docs" / "scenario.json").read_text())
DB = ROOT / "scenario.duckdb"
STATE_FILE = ROOT / "state" / "loaded_files.json"
INCOMING = ROOT / "incoming"
HISTORY_LIMIT = 12
SOURCE_GLOBS = ["scripts/*.py", ".github/workflows/*.yml", "dbt_project.yml",
                "profiles.yml", "seeds/*.yml", "seeds/*.csv", "macros/*.sql",
                "models/**/*.sql", "models/**/*.yml", "tests/*.sql", "tests/*.yml"]


def rows_of(con, sql: str) -> list[dict]:
    cur = con.execute(sql)
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def read_log(path: str | None) -> str:
    p = Path(path) if path else None
    return p.read_text(errors="replace").rstrip() if p and p.exists() else ""


def load_hooks():
    spec = importlib.util.spec_from_file_location("scenario", ROOT / "scripts" / "scenario.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def lineage() -> dict:
    """Nodes and edges from target/manifest.json, layered by folder/type."""
    mf = ROOT / "target" / "manifest.json"
    if not mf.exists():
        return {"nodes": [], "edges": []}
    m = json.loads(mf.read_text())
    nodes, edges = [], []
    layer_of = {}
    for uid, n in m["nodes"].items():
        if n["resource_type"] not in ("model", "seed"):
            continue
        if n["resource_type"] == "seed":
            layer = "seed"
        else:
            layer = Path(n["path"]).parts[0] if "/" in n["path"] else "models"
        layer_of[uid] = layer
        nodes.append({"id": n["name"], "layer": layer, "type": n["resource_type"],
                      "path": ("seeds/" if layer == "seed" else "models/") + n["path"]})
    for uid, n in m["nodes"].items():
        if uid not in layer_of:
            continue
        for dep in n.get("depends_on", {}).get("nodes", []):
            if dep in layer_of:
                edges.append([m["nodes"][dep]["name"], n["name"]])
    return {"nodes": nodes, "edges": edges, "layers": CFG["export"]["layers"]}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--python-log")
    ap.add_argument("--dbt-log")
    ap.add_argument("--action", default="load_next")
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    hooks = load_hooks()

    loaded = json.loads(STATE_FILE.read_text()) if STATE_FILE.exists() else []
    all_files = sorted(p.stem for p in INCOMING.glob("*.csv"))
    queue = [f for f in all_files if f not in loaded]
    next_file = queue[0] if queue else None
    next_rows = []
    if next_file:
        with open(INCOMING / f"{next_file}.csv", newline="") as fh:
            next_rows = list(csv.DictReader(fh))

    dbt_text = read_log(args.dbt_log)
    passed = failed = 0
    for tok in dbt_text.split():
        if tok.startswith("PASS="):
            passed = int(tok.split("=")[1])
        if tok.startswith("ERROR="):
            failed = int(tok.split("=")[1])

    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    ctx = {"action": args.action, "loaded": loaded, "queue": queue,
           "next_file": next_file, "passed": passed, "failed": failed, "cfg": CFG}

    con = duckdb.connect(str(DB), read_only=True)
    tables = {t: rows_of(con, f"select * from main.{t}") for t in CFG["export"]["tables"]}
    relations = [r[0] for r in con.execute(
        "select table_name from information_schema.tables where table_schema='main' "
        "order by table_name").fetchall()]
    model_data = {rel: rows_of(con, f"select * from main.{rel} order by all limit 120")
                  for rel in relations}
    audit = rows_of(con, "select * from audit.tbl_metadata_audit order by loaded_at desc limit 200") \
        if con.execute("select count(*) from information_schema.tables where table_schema='audit'").fetchone()[0] else []
    summary = {
        "generated_at": now,
        "files_loaded": loaded, "files_pending": queue, "next_file": next_file,
        "row_counts": {t: len(r) for t, r in tables.items()},
        **hooks.summary(con, ctx),
    }
    entry = {"at": now, "action": args.action, "passed": passed, "failed": failed,
             **hooks.history(con, ctx)}
    con.close()

    previous = []
    log_file = OUT / "logs.json"
    if args.action != "reset" and log_file.exists():
        try:
            previous = json.loads(log_file.read_text()).get("history", [])
        except (ValueError, OSError):
            previous = []
    logs = {"generated_at": now, "action": args.action, "passed": passed, "failed": failed,
            "history": (previous + [entry])[-HISTORY_LIMIT:],
            "python": read_log(args.python_log), "dbt": dbt_text}

    # Project source, published from the repo itself so the deck can never
    # drift from the code. Compiled SQL is included where Jinja changed it.
    files = sorted({p for g in SOURCE_GLOBS for p in ROOT.glob(g) if p.is_file()})
    compiled = {}
    for p in files:
        rel = p.relative_to(ROOT).as_posix()
        built = ROOT / "target" / "compiled" / CFG.get("dbt_project", "scenario") / rel
        if built.is_file() and rel.startswith("models/"):
            # Only models whose Jinja does more than ref()/source()/config():
            # those are the ones where "what does this compile to" is a question.
            src = re.sub(r"\{\{\s*config\([\s\S]*?\)\s*\}\}", "", p.read_text())
            src = re.sub(r"\{\{\s*(ref|source)\([^}]*\)\s*\}\}", "", src)
            if "{{" in src or "{%" in src:
                compiled[rel] = built.read_text().strip()
    models = {"files": [{"path": p.relative_to(ROOT).as_posix(), "sql": p.read_text()}
                        for p in files], "compiled": compiled}

    extra = hooks.extra(ctx) if hasattr(hooks, "extra") else {}
    for name, payload in [
        *extra.items(),
        ("summary.json", summary), ("tables.json", tables),
        ("next_file.json", {"name": next_file, "rows": next_rows}),
        ("logs.json", logs), ("models.json", models),
        ("model_data.json", model_data), ("lineage.json", lineage()),
        ("audit.json", audit),
    ]:
        (OUT / name).write_text(json.dumps(payload, indent=1, default=str) + "\n")
        print(f"wrote docs/data/{name}")


if __name__ == "__main__":
    main()
