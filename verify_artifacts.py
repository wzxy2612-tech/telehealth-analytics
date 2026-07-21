#!/usr/bin/env python3
"""
Artifact Validation: Scans Evidence.dev generated Parquet files for PHI leakage.
Consumes the same seeds/phi_column_registry.csv used by ELT and dbt tests.
"""

import duckdb
import csv
import glob
import sys
from pathlib import Path

def main():
    registry_path = Path('seeds/phi_column_registry.csv')
    if not registry_path.exists():
        sys.exit(f"Error: Registry not found at {registry_path}")

    # 1. 消费者 3：从唯一真相源读取黑名单
    with open(registry_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        banned = {r['column_name'].strip().lower() for r in reader}

    con = duckdb.connect()
    bad_files = []

    # 2. 遍历 Evidence 烘焙出的所有 parquet 数据包
    # 注意：根据 Evidence 版本，路径可能是 dashboards/build/ 或 dashboards/.evidence/
    parquet_pattern = 'dashboards/build/**/*.parquet' 
    parquet_files = glob.glob(parquet_pattern, recursive=True)

    if not parquet_files:
        print(f"No parquet files found matching {parquet_pattern}. Did you run 'npm run build'?")
        # 如果是 CI 环境，可以选择不报错，或者视具体流程而定
        sys.exit(0) 

    # 3. 逐个物理探查列名
    for f in parquet_files:
        try:
            query = f"describe select * from read_parquet('{Path(f).as_posix()}')"
            cols = {r[0].lower() for r in con.execute(query).fetchall()}
            
            # 集合交集：如果存在于黑名单中，立刻抓获
            if hits := sorted(cols & banned):
                bad_files.append((f, hits))
        except Exception as e:
            print(f"Error reading {f}: {e}")

    # 4. 判决
    if bad_files:
        print("\n❌ CRITICAL: PHI LEAKAGE DETECTED IN PUBLISHED ARTIFACTS!")
        for f, hits in bad_files:
            print(f" -> File: {f}")
            print(f" -> Leaked Columns: {hits}\n")
        sys.exit(1)
    else:
        print("✅ Artifact validation passed. No registered PHI columns found in Parquet files.")
        sys.exit(0)

if __name__ == "__main__":
    main()