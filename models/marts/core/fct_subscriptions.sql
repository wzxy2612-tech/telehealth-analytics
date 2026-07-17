-- Subscription fact, one row per subscription. Exposes plan / status / tenure
-- at subscription grain so BI can slice revenue by plan, status, and cohort
-- (fct_mrr_daily aggregates these away).
with subs as (
    select * from {{ ref('int_subscriptions_enriched') }}
)

select
    subscription_id,
    patient_id,
    plan_id,
    mrr_amount,
    status,
    is_active,
    started_at,
    cancelled_at,
    date_trunc('month', started_at)     as start_cohort_month,
    tenure_days,
    plan_change_count
from subs
