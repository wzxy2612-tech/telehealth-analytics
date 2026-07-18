{% snapshot subscriptions_snapshot %}

{{
    config(
        target_schema='snapshots',
        unique_key='subscription_id',
        strategy='check',
        check_cols=['plan_id', 'mrr_amount', 'status'],
        invalidate_hard_deletes=True
    )
}}

-- Snapshots the CURRENT-STATE subscription source (Chargebee's subscription
-- object, which overwrites in place). Run `dbt snapshot` (or `dbt build`)
-- repeatedly: each run records a NEW version of any row whose plan / mrr /
-- status changed since the last run, stamping dbt_valid_from / dbt_valid_to /
-- dbt_scd_id. This is the SCD Type 2 pattern for sources that keep no history
-- of their own.
--
-- Two honest caveats for this project:
--   1. A snapshot only captures changes going FORWARD from when you first run
--      it. On a single build it just records current state (one version per
--      subscription) — history accrues run over run.
--   2. `generate_data.py day` appends to subscription_events but does NOT
--      rewrite existing rows' plan in subscriptions.csv, so this snapshot won't
--      even see those plan changes. That's the giveaway that, HERE, the event
--      log is the reliable change record — so dim_subscription_history
--      reconstructs full SCD2 from subscription_events instead. Keep this
--      snapshot as the tool you'd reach for when a source overwrites current
--      state and gives you no event log (e.g. a patient's address).
--
-- (dbt >= 1.9 may print a `target_schema` deprecation notice; to silence it,
--  move this config into a snapshots/*.yml using `schema:` instead.)
select
    subscription_id,
    patient_id,
    lower(plan_id)                              as plan_id,
    cast(mrr_amount as integer)                 as mrr_amount,
    lower(status)                               as status,
    cast(started_at as date)                    as started_at,
    try_cast(nullif(cancelled_at, '') as date)  as cancelled_at
from {{ source('raw', 'subscriptions') }}

{% endsnapshot %}
