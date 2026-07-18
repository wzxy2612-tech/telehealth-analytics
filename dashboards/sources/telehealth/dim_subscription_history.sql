-- SCD Type 2 plan history: one row per (subscription, plan period).
-- valid_to is NULL while the period is still open (is_current).
select
    subscription_id,
    patient_id,
    plan_id,
    mrr_amount,
    version,
    valid_from,
    valid_to,
    is_current
from marts.dim_subscription_history
