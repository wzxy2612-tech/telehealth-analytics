#!/usr/bin/env python3
"""
Land raw CSVs into DuckDB under a `raw` schema.

This stands in for the EL step (Airbyte / dlt) that would land raw source data
into Redshift in production. dbt sources point at these `raw.*` tables.

Behaviour: full-refresh of the raw layer from the CSVs on every run. The CSVs
are the source of truth; `generate_data.py day` appends to them, so a reload
always reflects the full history. Incrementality is demonstrated in the
transform layer (see models/marts/core/fct_appointments.sql), not here.

Usage:
    python load.py                              # data/raw fixture -> telehealth.duckdb
    python load.py --data-dir data/generated    # large local set
    python load.py --db telehealth_ci.duckdb
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import duckdb
except ImportError:
    sys.exit("duckdb not installed. Run: pip install -r requirements.txt")

DATA_DIR = Path(__file__).parent / "data"

# Tables to land. `loaded_at_col` gets stamped so dbt source freshness has a
# real timestamp to measure against.
TABLES = [
    "providers",
    "patients",
    "appointments",
    "subscriptions",
    "subscription_events",
    "marketing_touchpoints",
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="telehealth.duckdb", help="DuckDB file path")
    ap.add_argument("--data-dir", type=Path, default=DATA_DIR / "raw",
                    help="CSV input directory (default: data/raw)")
    args = ap.parse_args()

    csvs = sorted(args.data_dir.glob("*.csv"))
    if not csvs:
        sys.exit(
            f"No CSVs in {args.data_dir}. Generate data first, e.g.:\n"
            f"  python generate_data.py backfill --start 2024-10-01 --end 2024-12-31 "
            f"--output-dir {args.data_dir}"
        )

    con = duckdb.connect(args.db)
    con.execute("CREATE SCHEMA IF NOT EXISTS raw;")

    for t in TABLES:
        path = args.data_dir / f"{t}.csv"
        if not path.exists():
            print(f"  ! skipping {t}: {path} not found")
            continue
        # read_csv_auto handles typing + header detection; all_varchar keeps the
        # raw layer faithful (staging is where we cast), which mirrors how EL
        # tools land data as-is.
        con.execute(
            f"""
            CREATE OR REPLACE TABLE raw.{t} AS
            SELECT *, now() AS _loaded_at
            FROM read_csv_auto('{path.as_posix()}', header=true, all_varchar=true);
            """
        )
        n = con.execute(f"SELECT count(*) FROM raw.{t}").fetchone()[0]
        print(f"  loaded raw.{t:<24} {n:>7} rows")

    con.close()
    print(f"\nDone -> {args.db}")


if __name__ == "__main__":
    main()
