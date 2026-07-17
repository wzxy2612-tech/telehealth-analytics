.PHONY: help setup deps load build test freshness docs all clean day \
        generate-big load-big clean-big regen-fixture dash dash-build

export DBT_PROFILES_DIR := .

help:
	@echo "Targets (default path builds from the committed fixture in data/raw):"
	@echo "  setup      pip install + dbt deps"
	@echo "  load       land data/raw fixture into DuckDB"
	@echo "  build      dbt build (run + test all models)"
	@echo "  test       dbt test only"
	@echo "  freshness  dbt source freshness"
	@echo "  docs       generate + serve dbt docs at :8080"
	@echo "  dash       run the Evidence dashboards at :3000 (needs npm)"
	@echo "  dash-build build the static Evidence site"
	@echo "  all        setup -> load -> build (from fixture; no regeneration)"
	@echo "  day D=YYYY-MM-DD   append one day to data/generated + reload + build"
	@echo "                     (run generate-big first to seed data/generated)"
	@echo "  clean      remove warehouse + dbt artifacts"
	@echo ""
	@echo "  --- Big-data path (gitignored, local dev/large-scale) ---"
	@echo "  generate-big   backfill to data/generated/ (Jun-Dec 2024)"
	@echo "  load-big       load data/generated/ CSVs into DuckDB"
	@echo "  clean-big      rm -rf data/generated/"
	@echo ""
	@echo "  --- Fixture maintenance (deterministic, committed) ---"
	@echo "  regen-fixture   regenerate data/raw/ with --seed 42"

setup deps:
	pip install -r requirements.txt
	dbt deps

load:
	python load.py --db dashboards/sources/telehealth/telehealth.duckdb

build:
	dbt build

test:
	dbt test

freshness:
	dbt source freshness

docs:
	dbt docs generate
	dbt docs serve --port 8080

# ---- Evidence dashboards (require Node 18+) ----
dash:
	cd dashboards && npm install && npm run sources && npm run dev

dash-build:
	cd dashboards && npm install && npm run sources && npm run build

# Build from the committed fixture (data/raw). No regeneration: the fixture is
# versioned and deterministic, so a fresh clone builds identically.
all: setup load build

# Simulate a scheduled increment against the MUTABLE generated set (never the
# committed fixture). Run `make generate-big` first to seed data/generated,
# otherwise this starts from an almost-empty dir.
# e.g. `make day D=2025-01-02`
day:
	python generate_data.py day --date $(D) --output-dir data/generated
	python load.py --data-dir data/generated --db dashboards/sources/telehealth/telehealth.duckdb
	dbt build

# ---- Big-data path (gitignored; larger synthetic set for local dev) ----
# NOTE: this range starts 2024-06-01, before the fixture's mrr_start_date
# (2024-10-01). To see full MRR history on this set, override the var:
#   dbt build --vars 'mrr_start_date: 2024-06-01'
generate-big:
	python generate_data.py backfill --start 2024-06-01 --end 2024-12-31 \
	    --output-dir data/generated

load-big:
	python load.py --data-dir data/generated --db dashboards/sources/telehealth/telehealth.duckdb

clean-big:
	rm -rf data/generated

# ---- Fixture maintenance ----
regen-fixture:
	python generate_data.py backfill --start 2024-10-01 --end 2024-12-31 \
	    --seed 42 --output-dir data/raw

clean:
	rm -f dashboards/sources/telehealth/telehealth.duckdb dashboards/sources/telehealth/telehealth_ci.duckdb
	rm -rf target dbt_packages logs
