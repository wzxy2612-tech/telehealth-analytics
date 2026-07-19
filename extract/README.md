# EL layer

Extract from the source systems, load into the warehouse's `raw` schema. Then
dbt takes over.

`load.py` bulk-loads CSVs — fine as a deterministic fixture loader, but it isn't
EL: it reads files, rewrites everything every time, and has no concept of state.
This layer does the real thing.

```
source_db.duckdb                          telehealth.duckdb
┌──────────────────────────┐              ┌──────────────────┐
│ app        (MySQL/RDS)   │   dlt        │ raw.*            │   dbt
│ billing    (Chargebee)   │  ────────►   │                  │  ────►  staging → marts
│ marketing  (Customer.io) │  incremental │ + _dlt_* state   │
└──────────────────────────┘   + merge    └──────────────────┘
```

## Run it

```bash
pip install -r extract/requirements.txt

python extract/source_db.py     # build the simulated source systems
python extract/pipeline.py      # extract + load (first run = full history)
python extract/pipeline.py      # run again: 0 new rows, no duplicates
dbt build                       # transform as usual
```

To see incremental loading actually do something, append a day to the source and
re-run:

```bash
python generate_data.py day --date 2025-01-02 --output-dir data/generated
python extract/source_db.py --data-dir data/generated
python extract/pipeline.py      # moves ~100 rows, not ~12,000
```

## Three sync strategies, and their Airbyte equivalents

The tables don't all behave the same way, so they aren't loaded the same way.
This is the core design decision of any EL layer — and it's the same decision
you make in Airbyte's UI when you pick a sync mode per stream.

| Tables | Why | dlt | Airbyte equivalent |
|---|---|---|---|
| `providers` | Tiny, slowly-changing, no reliable cursor | `write_disposition="replace"` | **Full Refresh \| Overwrite** |
| `patients`, `appointments`, `subscriptions` | Rows are **rewritten in place** (a subscription is cancelled, an appointment rescheduled) | `write_disposition="merge"` + `primary_key` + `incremental("updated_at")` | **Incremental \| Append + Deduped** (cursor `updated_at`, PK) |
| `subscription_events`, `marketing_touchpoints` | Immutable logs — rows are only ever added | `write_disposition="append"` + `incremental("event_at")` | **Incremental \| Append** (cursor `event_at`) |

### Why merge, specifically

In this dataset **47.9% of subscription rows** have `updated_at != created_at` —
they were rewritten in place when the subscription churned or changed plan. An
append-only load would produce two rows for the same `subscription_id` (one
`active`, one `cancelled`) and double-count MRR. Merging on the primary key
keeps exactly one current row.

The same property makes the pipeline **idempotent**: if a run dies halfway and
is retried, merge updates rather than duplicates. That matters more in practice
than in-place updates do — retries are the common case.

### What incremental buys

Measured on the committed fixture, appending one day of activity:

| Table | Rows moved | Full reload | Saved |
|---|---:|---:|---:|
| `patients` | 12 | 1,321 | 99% |
| `appointments` | 59 | 4,609 | 99% |
| `subscriptions` | 5 | 771 | 99% |
| `subscription_events` | 16 | 1,216 | 99% |
| `marketing_touchpoints` | 12 | 3,974 | 100% |
| **Total** | **104** | **11,891** | **99%** |

The cursor filter is pushed into the source query (`where updated_at > ?`), so
the skipped rows never cross the wire. On Redshift Serverless, where you pay for
what you scan, this is the difference between a pipeline that costs pennies and
one that doesn't.

State (each cursor's `last_value`) is persisted by dlt in the destination
(`_dlt_pipeline_state`) and under `~/.dlt`, which is what makes the *next* run
incremental.

## How this maps to production

| Here | Production |
|---|---|
| `source_db.duckdb` with 3 schemas | MySQL on RDS, Chargebee API, Customer.io API |
| `dlt` resources | Airbyte source connectors (or dlt — it runs in production fine) |
| Cursor on `updated_at` | Same, or MySQL binlog CDC for the app DB |
| Destination: DuckDB `raw` | Redshift `raw` schema |
| `python extract/pipeline.py` | Airbyte scheduled sync, or this script on cron/Dagster |

The sync-mode reasoning transfers unchanged — that's the part worth carrying
into any tool.

## Honest limitations

- **The source is simulated.** `source_db.duckdb` is built from CSVs, so this
  never exercises real connector problems: API rate limits, pagination, auth
  refresh, MySQL binlog retention, Chargebee webhook ordering.
- **No schema-drift handling is demonstrated.** dlt would evolve the target
  schema if a source column appeared; nothing here makes that happen.
- **`generate_data.py day` is append-only**, so in the incremental demo the
  merge path receives new rows but no in-place updates. The 47.9% mutation rate
  above comes from a full backfill. To exercise true updates, regenerate the
  backfill rather than appending a day.
- **This is additive.** `load.py`, CI, and the Pages deploy still use the
  deterministic fixture path and don't depend on dlt. Switch them over only once
  this runs reliably for you.

## If you want literal Airbyte

`abctl local install` (Docker, ~8GB RAM) gets you Airbyte OSS locally; point a
source connector at a Postgres/MySQL instance and a destination at your
warehouse. It's worth doing once to see the UI and sync-mode settings — but the
configuration lives in Airbyte's own database, not in this repo, so it can't be
version-controlled or run in CI the way this can.
