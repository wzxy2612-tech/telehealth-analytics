-- Subscription snapshot (from the staging view) to drive plan mix + churn.
select
    subscription_id,
    patient_id,
    plan_id,
    mrr_amount,
    status,
    started_at,
    cancelled_at
from staging.stg_subscriptions
