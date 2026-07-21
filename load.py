#!/usr/bin/env python3
"""
Land raw CSVs into DuckDB under a `raw` schema.

This stands in for the EL step (Airbyte / dlt) that would land raw source data
into Redshift in production. dbt sources point at these `raw.*` tables.

The warehouse file lives at dashboards/sources/telehealth/telehealth.duckdb so
that a single DuckDB file serves both dbt (which builds the marts) and Evidence
(whose connection.yaml expects the db beside it). This default matches the dev
target in profiles.yml, so `python load.py` and `dbt build` always agree.

Behaviour: full-refresh of the raw layer from the CSVs on every run. The CSVs
are the source of truth; `generate_data.py day` appends to them, so a reload
always reflects the full history. Incrementality is demonstrated in the
transform layer (see models/marts/core/fct_appointments.sql), not here.

Usage:
    python load.py                              # data/raw fixture -> subdir warehouse
    python load.py --data-dir data/generated    # large local set
    python load.py --db some/other.duckdb       # override target file
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

try:
    import duckdb
except ImportError:
    sys.exit("duckdb not installed. Run: pip install -r requirements.txt")

DATA_DIR = Path(__file__).parent / "data"
DEFAULT_DB = "dashboards/sources/telehealth/telehealth.duckdb"
REGISTRY_PATH = Path(__file__).parent / "seeds" / "phi_column_registry.csv"

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

# --- SYNTHEA CONFIGURATION (Phase 2) ---

# Table name -> filename. Prefixed `synthea_` so nothing collides with the
# SaaS generator's own `patients` table already in raw.
SYNTHEA_FILES = {
    "synthea_patients": "patients.csv",
    "synthea_encounters": "encounters.csv",
    "synthea_payer_transitions": "payer_transitions.csv",
    "synthea_payers": "payers.csv",
    "synthea_providers": "providers.csv",
    "synthea_organizations": "organizations.csv",
}


def get_phi_drop_columns(registry_path: Path) -> set:
    """
    Reads the central PHI registry to dynamically determine Tier 1 columns.
    Eliminates configuration drift between ingestion and dbt tests.
    """
    drop_cols = set()
    if not registry_path.exists():
        print(f"  ! Warning: Registry not found at {registry_path}. No PHI dropped.")
        return drop_cols

    with open(registry_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            col_name = row.get('column_name', '').strip().upper()
            tier = str(row.get('tier', '1')).strip()
            
            if col_name and tier == '1':
                drop_cols.add(col_name)
                
    return drop_cols


def load_synthea(con, synthea_dir: Path, schema: str = "raw") -> None:
    """
    Drop-in addition to land the Synthea CSV extract into the same
    `raw` schema as the SaaS domain, with tier-1 identifiers never written.
    Supports directory-based partitioning using DuckDB globbing.
    """
    if not synthea_dir.exists():
        print(f"  ! skipping Synthea: directory {synthea_dir} not found")
        return

    # 動態獲取需要被 Drop 的 Tier 1 欄位
    synthea_drop_columns = get_phi_drop_columns(REGISTRY_PATH)

    for table, filename in SYNTHEA_FILES.items():
        folder_name = filename.replace('.csv', '')
        folder_path = synthea_dir / folder_name

        if not folder_path.exists() or not any(folder_path.iterdir()):
            print(f"  ! [synthea] skip {folder_name}: directory not present or empty")
            continue

        csv_glob = (folder_path / "*.csv").as_posix()

        headers = [
            row[0]
            for row in con.execute(
                f"describe select * from read_csv_auto('{csv_glob}')"
            ).fetchall()
        ]

        keep = [h for h in headers if h.upper() not in synthea_drop_columns]
        dropped = [h for h in headers if h.upper() in synthea_drop_columns]

        col_list = ", ".join(f'"{c}"' for c in keep)
        col_list += ", now() AS _loaded_at"

        con.execute(f"drop table if exists {schema}.{table}")

        con.execute(
            f"create table {schema}.{table} as "
            f"select {col_list} "
            f"from read_csv_auto('{csv_glob}', sample_size=-1)"
        )

        rows = con.execute(f"select count(*) from {schema}.{table}").fetchone()[0]
        print(
            f"  loaded {schema}.{table:<24} {rows:>7} rows, "
            f"{len(keep)} cols kept, dropped {len(dropped) if dropped else 'none'} PHI cols"
        )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=DEFAULT_DB,
                    help=f"DuckDB file path (default: {DEFAULT_DB})")
    ap.add_argument("--data-dir", type=Path, default=DATA_DIR / "raw",
                    help="CSV input directory (default: data/raw)")
    args = ap.parse_args()

    csvs = sorted(args.data_dir.rglob("*.csv"))
    if not csvs:
        sys.exit(
            f"No CSVs in {args.data_dir}. Generate data first, e.g.:\n"
            f"  python generate_data.py backfill --start 2024-10-01 --end 2024-12-31 "
            f"--output-dir {args.data_dir}"
        )

    Path(args.db).parent.mkdir(parents=True, exist_ok=True)

    con = duckdb.connect(args.db)
    con.execute("CREATE SCHEMA IF NOT EXISTS raw;")

    print("--- Loading SaaS Core Data ---")
    for t in TABLES:
        path = args.data_dir / f"{t}.csv"
        if not path.exists():
            print(f"  ! skipping {t}: {path} not found")
            continue
        
        con.execute(
            f"""
            CREATE OR REPLACE TABLE raw.{t} AS
            SELECT *, now() AS _loaded_at
            FROM read_csv_auto('{path.as_posix()}', header=true, all_varchar=true, sample_size=-1);
            """
        )
        n = con.execute(f"SELECT count(*) FROM raw.{t}").fetchone()[0]
        print(f"  loaded raw.{t:<24} {n:>7} rows")

    print("\n--- Loading Synthea Clinical Data (with PHI filtering) ---")
    load_synthea(con, args.data_dir / "synthea", "raw")

    con.close()
    print(f"\nDone -> {args.db}")


if __name__ == "__main__":
    main()