-- Subscription snapshot enriched with lifecycle facts derived from the event
-- log, plus tenure. Grain: one row per subscription.
with subs as (
    select * from {{ ref('stg_subscriptions') }}
),
events as (
    select * from {{ ref('stg_subscription_events') }}
),
plan_changes as (
    select
        subscription_id,
        count(*) filter (where event_type = 'plan_changed') as plan_change_count,
        max(event_at) filter (where event_type = 'cancelled') as cancelled_event_at
    from events
    group by 1
)

select
    s.subscription_id,
    s.patient_id,
    s.plan_id,
    s.mrr_amount,
    s.status,
    (s.status = 'active')                                    as is_active,
    s.started_at,
    s.cancelled_at,
    coalesce(pc.plan_change_count, 0)                        as plan_change_count,
    -- tenure in days: cancelled subs use cancel date; active subs use today
    date_diff(
        'day',
        s.started_at,
        coalesce(s.cancelled_at, current_date)
    )                                                        as tenure_days,
    s.created_at,
    s.updated_at
from subs s
left join plan_changes pc on s.subscription_id = pc.subscription_id
