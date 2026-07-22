#!/usr/bin/env python3
"""
EL layer: extract from the source systems, load into the warehouse `raw` schema.

This is what `load.py` stands in for, done properly. Three sync strategies, one
per table shape — the same three Airbyte offers (see extract/README.md):

  replace              providers            small reference data, cheap to redo
  merge + incremental  patients,            rows mutate in place; a cursor picks
                       appointments,        up changes, the primary key dedupes
                       subscriptions        so a retry can't duplicate
  append + incremental subscription_events, immutable logs; never rewritten, so
                       marketing_touchpoints  appending new rows is correct

dlt persists the cursor (`last_value`) as pipeline state between runs, so each
run only pulls what changed. On this dataset a daily run moves ~104 rows instead
of reloading ~11,900 — a ~99% reduction.

Usage:
    python extract/source_db.py     # build the source systems first
    python extract/pipeline.py      # run the EL
    python extract/pipeline.py      # run again: idempotent, no duplicates

Requires: pip install -r extract/requirements.txt
"""
from __future__ import annotations

import sys
from datetime import datetime
from pathlib import Path

try:
    import dlt
    import duckdb
except ImportError:
    sys.exit("Missing deps. Run: pip install -r extract/requirements.txt")

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DB = ROOT / "source_db.duckdb"
# Same warehouse file dbt builds into (see profiles.yml dev target), so dbt
# picks up whatever this loads with no extra wiring.
WAREHOUSE = ROOT / "dashboards" / "sources" / "telehealth" / "telehealth.duckdb"

EPOCH = datetime(1970, 1, 1)


def _query(sql: str, params: list, cursor_field: str | None = None):
    """Run a query against the source DB and yield dicts.

    Two things happen per record:
      * `_loaded_at` is stamped, because dbt's staging models select it (it also
        mirrors what an EL tool records as ingestion time).
      * the cursor column is parsed to a real datetime, so dlt compares
        timestamps rather than strings when tracking incremental state.
    """
    con = duckdb.connect(str(SOURCE_DB), read_only=True)
    try:
        cur = con.execute(sql, params)
        columns = [d[0] for d in cur.description]
        loaded_at = datetime.now()
        for row in cur.fetchall():
            record = dict(zip(columns, row))
            if cursor_field and record.get(cursor_field):
                record[cursor_field] = datetime.fromisoformat(record[cursor_field])
            record["_loaded_at"] = loaded_at
            yield record
    finally:
        con.close()


# ---------------------------------------------------------------------------
# Full refresh: tiny, slowly-changing reference data with no reliable cursor.
# ---------------------------------------------------------------------------
@dlt.resource(name="providers", write_disposition="replace")
def providers():
    yield from _query("select * from app.providers", [])


# ---------------------------------------------------------------------------
# Merge + incremental: the source row can be REWRITTEN in place (a subscription
# is cancelled, an appointment is rescheduled). The cursor finds the change; the
# primary key makes the load idempotent, so a retry after a partial failure
# updates the row instead of duplicating it.
# ---------------------------------------------------------------------------
@dlt.resource(name="patients", write_disposition="merge", primary_key="patient_id")
def patients(updated_at=dlt.sources.incremental("updated_at", initial_value=EPOCH)):
    # Filtering server-side (not just in dlt) is the point of the cursor: the
    # rows never leave the source system in the first place.
    yield from _query(
        "select * from app.patients where cast(updated_at as timestamp) > ?",
        [updated_at.last_value],
        cursor_field="updated_at",
    )


@dlt.resource(name="appointments", write_disposition="merge", primary_key="appointment_id")
def appointments(updated_at=dlt.sources.incremental("updated_at", initial_value=EPOCH)):
    yield from _query(
        "select * from app.appointments where cast(updated_at as timestamp) > ?",
        [updated_at.last_value],
        cursor_field="updated_at",
    )


@dlt.resource(name="subscriptions", write_disposition="merge", primary_key="subscription_id")
def subscriptions(updated_at=dlt.sources.incremental("updated_at", initial_value=EPOCH)):
    yield from _query(
        "select * from billing.subscriptions where cast(updated_at as timestamp) > ?",
        [updated_at.last_value],
        cursor_field="updated_at",
    )


# ---------------------------------------------------------------------------
# Append + incremental: immutable event logs. Rows are never updated, so there
# is nothing to merge on — appending what's new is both correct and cheapest.
# ---------------------------------------------------------------------------
@dlt.resource(name="subscription_events", write_disposition="append")
def subscription_events(event_at=dlt.sources.incremental("event_at", initial_value=EPOCH)):
    yield from _query(
        "select * from billing.subscription_events where cast(event_at as timestamp) > ?",
        [event_at.last_value],
        cursor_field="event_at",
    )


@dlt.resource(name="marketing_touchpoints", write_disposition="append")
def marketing_touchpoints(event_at=dlt.sources.incremental("event_at", initial_value=EPOCH)):
    yield from _query(
        "select * from marketing.marketing_touchpoints where cast(event_at as timestamp) > ?",
        [event_at.last_value],
        cursor_field="event_at",
    )


@dlt.source(name="telehealth")
def telehealth_source():
    return [
        providers(),
        patients(),
        appointments(),
        subscriptions(),
        subscription_events(),
        marketing_touchpoints(),
    ]


def _needs_refresh() -> bool:
    """Check if the warehouse has legacy raw tables (left by load.py) that lack
    dlt tracking columns. If so, the caller should use refresh='drop_sources' so
    dlt atomically drops both tables and pipeline state — avoiding the trap of
    dropping tables while leaving stale cursors in _dlt_pipeline_state."""
    con = duckdb.connect(str(WAREHOUSE), read_only=True)
    try:
        tables = con.execute(
            "select table_name from information_schema.tables "
            "where table_schema = 'raw' and table_name not like 'synthea_%'"
        ).fetchall()
        for (t,) in tables:
            if t.startswith("_dlt"):
                continue
            cols = con.execute(
                "select column_name from information_schema.columns "
                f"where table_schema = 'raw' and table_name = '{t}'"
            ).fetchall()
            col_names = {c[0].lower() for c in cols}
            if '_dlt_id' not in col_names:
                return True
        return False
    finally:
        con.close()


def main():
    if not SOURCE_DB.exists():
        sys.exit(
            f"{SOURCE_DB} not found. Build the source systems first:\n"
            f"  python extract/source_db.py"
        )

    refresh = "drop_sources" if WAREHOUSE.exists() and _needs_refresh() else None
    if refresh:
        print("  legacy tables detected — running with refresh='drop_sources'")

    pipeline = dlt.pipeline(
        pipeline_name="telehealth_el",
        destination=dlt.destinations.duckdb(str(WAREHOUSE)),
        # dlt calls the target schema a "dataset"; naming it `raw` puts tables
        # exactly where dbt's sources already look (source('raw', ...)).
        dataset_name="raw",
        progress="log",
    )

    info = pipeline.run(telehealth_source(), refresh=refresh)
    print(info)

    # Show what the cursors advanced to — this is the state that makes the next
    # run incremental. It lives in the destination (_dlt_pipeline_state) and in
    # ~/.dlt, so it survives across runs.
    print("\nCursor state after this run:")
    state = pipeline.state.get("sources", {}).get("telehealth", {}).get("resources", {})
    for resource, payload in sorted(state.items()):
        last = payload.get("incremental", {}).get("updated_at") or \
               payload.get("incremental", {}).get("event_at") or {}
        if last.get("last_value"):
            print(f"  {resource:<24} last_value = {last['last_value']}")


if __name__ == "__main__":
    main()
