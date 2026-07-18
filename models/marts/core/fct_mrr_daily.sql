-- Daily recurring revenue: one row per calendar day with active subscription
-- count and total MRR. Powers the Business Ops revenue dashboard.
--
-- Simplification: MRR uses each subscription's current plan amount. A
-- production model would reconstruct point-in-time MRR from the plan_changed
-- events so historical days reflect the plan active on that day.
with spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('" ~ var('mrr_start_date') ~ "' as date)",
        end_date="(select max(started_at) + interval 1 day from " ~ ref('int_subscriptions_enriched') ~ ")"
    ) }}
),
days as (
    select cast(date_day as date) as calendar_date from spine
),
subs as (
    select * from {{ ref('int_subscriptions_enriched') }}
)

select
    d.calendar_date,
    count(s.subscription_id)                              as active_subscriptions,
    coalesce(sum(s.mrr_amount), 0)                        as mrr,
    round(coalesce(sum(s.mrr_amount), 0) * 12.0, 2)       as arr,
    coalesce(round(avg(s.mrr_amount), 2), 0)              as arpu
from days d
left join subs s
    on  d.calendar_date >= s.started_at
    and d.calendar_date <  coalesce(s.cancelled_at, current_date + interval 1 day)
group by 1
order by 1
