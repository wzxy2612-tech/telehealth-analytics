#!/usr/bin/env python3
"""
Materialise the CSVs into `source_db.duckdb` — a stand-in for the SOURCE
SYSTEMS the EL layer extracts from.

Why this exists: `load.py` reads files. Real EL reads *databases and APIs*. This
script builds a queryable source with three schemas, mirroring the three systems
in the brief:

    app        <- MySQL on AWS RDS (patients, providers, appointments)
    billing    <- Chargebee        (subscriptions, subscription_events)
    marketing  <- Customer.io/ads  (marketing_touchpoints)

Columns are kept as VARCHAR, exactly like `load.py` does, so the raw layer stays
faithful and all casting continues to happen in dbt staging.

Usage:
    python extract/source_db.py                          # from data/raw fixture
    python extract/source_db.py --data-dir data/generated
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import duckdb
except ImportError:
    sys.exit("duckdb not installed. Run: pip install -r requirements.txt")

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE_DB = ROOT / "source_db.duckdb"

# table -> source schema (which upstream system it belongs to)
SYSTEMS = {
    "providers": "app",
    "patients": "app",
    "appointments": "app",
    "subscriptions": "billing",
    "subscription_events": "billing",
    "marketing_touchpoints": "marketing",
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", type=Path, default=ROOT / "data" / "raw",
                    help="CSV input directory (default: data/raw)")
    ap.add_argument("--source-db", type=Path, default=DEFAULT_SOURCE_DB,
                    help=f"output DuckDB file (default: {DEFAULT_SOURCE_DB.name})")
    args = ap.parse_args()

    if not sorted(args.data_dir.glob("*.csv")):
        sys.exit(f"No CSVs in {args.data_dir}.")

    con = duckdb.connect(str(args.source_db))
    for schema in sorted(set(SYSTEMS.values())):
        con.execute(f"create schema if not exists {schema}")

    for table, schema in SYSTEMS.items():
        path = args.data_dir / f"{table}.csv"
        if not path.exists():
            print(f"  ! skipping {table}: {path} not found")
            continue
        con.execute(
            f"""
            create or replace table {schema}.{table} as
            select * from read_csv_auto('{path.as_posix()}', header=true, all_varchar=true);
            """
        )
        n = con.execute(f"select count(*) from {schema}.{table}").fetchone()[0]
        print(f"  {schema}.{table:<24} {n:>7} rows")

    con.close()
    print(f"\nSource systems ready -> {args.source_db}")


if __name__ == "__main__":
    main()
