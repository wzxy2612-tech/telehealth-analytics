-- Daily point-in-time plan mix: for each calendar day, how many subscriptions
-- were on each plan and what MRR that represented.
--
-- This query is only possible because of SCD2 — the current-state table can't
-- tell you what plan a subscription was on last month.
--
-- The date spine reuses fct_mrr_daily (already one row per day), bounded to the
-- range the history actually covers so the chart has no empty tail.
with bounds as (
    select
        cast(min(valid_from) as date)                        as start_date,
        cast(max(coalesce(valid_to, valid_from)) as date)    as end_date
    from marts.dim_subscription_history
),

days as (
    select m.calendar_date
    from marts.fct_mrr_daily m, bounds b
    where m.calendar_date between b.start_date and b.end_date
)

select
    d.calendar_date,
    h.plan_id,
    count(*)             as subscriptions,
    sum(h.mrr_amount)    as mrr
from days d
join marts.dim_subscription_history h
    -- a period covers a day if it started on/before it and hasn't ended yet.
    -- half-open interval [valid_from, valid_to) means no double counting on
    -- the day a plan changes.
    on  d.calendar_date >= cast(h.valid_from as date)
    and (h.valid_to is null or d.calendar_date < cast(h.valid_to as date))
group by 1, 2
order by 1, 2
