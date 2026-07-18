-- Subscription plan history as a Slowly Changing Dimension (Type 2).
--
-- Reconstructed from the subscription_events log: each row is one plan period,
-- with [valid_from, valid_to) and an is_current flag. Because the full change
-- history lives in events, this produces COMPLETE SCD2 immediately on a single
-- build — unlike a dbt snapshot, which only accrues history run over run. See
-- snapshots/subscriptions_snapshot.sql and the README for when to use which.
--
-- Grain: one row per (subscription_id, plan period). A subscription that never
-- changed plan has one row; each plan change adds a version.
with events as (
    select * from {{ ref('stg_subscription_events') }}
),

subscriptions as (
    select subscription_id, patient_id from {{ ref('stg_subscriptions') }}
),

-- 'created' and 'plan_changed' each set a new plan (to_plan) at event_at
plan_events as (
    select
        subscription_id,
        lower(to_plan)  as plan_id,
        event_at        as valid_from,
        row_number() over (
            partition by subscription_id order by event_at
        )               as version
    from events
    where event_type in ('created', 'plan_changed')
      and to_plan is not null
),

-- first cancellation closes the final plan period
cancellations as (
    select subscription_id, min(event_at) as cancelled_at
    from events
    where event_type = 'cancelled'
    group by 1
),

periods as (
    select
        pe.subscription_id,
        pe.plan_id,
        pe.version,
        pe.valid_from,
        lead(pe.valid_from) over (
            partition by pe.subscription_id order by pe.valid_from
        )               as next_change_at,
        c.cancelled_at
    from plan_events pe
    left join cancellations c using (subscription_id)
)

select
    p.subscription_id,
    s.patient_id,
    p.plan_id,
    -- historical plan price. In production this would join a plan/price
    -- dimension (prices change over time); the three tiers are stable enough
    -- to map inline for the demo.
    case p.plan_id
        when 'basic'   then 49
        when 'plus'    then 99
        when 'premium' then 199
    end                                             as mrr_amount,
    p.version,
    p.valid_from,
    -- a period ends at the next plan change; the final period ends at
    -- cancellation, or stays open (NULL = current) while still active
    coalesce(p.next_change_at, p.cancelled_at)      as valid_to,
    (p.next_change_at is null and p.cancelled_at is null) as is_current
from periods p
left join subscriptions s using (subscription_id)
