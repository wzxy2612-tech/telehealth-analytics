-- Channel/campaign acquisition performance for the Marketing team.
-- Grain: one row per (first_touch_channel, first_touch_campaign).
-- First-touch attribution: a patient is credited to the channel that first
-- brought them in. Joins to subscriptions to approximate CAC vs. value.
with attribution as (
    select * from {{ ref('int_marketing_attribution') }}
),
subs as (
    select patient_id, is_active, mrr_amount from {{ ref('int_subscriptions_enriched') }}
),
joined as (
    select
        a.first_touch_channel   as channel,
        a.first_touch_campaign  as campaign,
        a.patient_id,
        a.total_marketing_cost,
        (s.patient_id is not null)              as converted,
        coalesce(s.is_active, false)            as is_active_subscriber,
        coalesce(s.mrr_amount, 0)               as mrr_amount
    from attribution a
    left join subs s on a.patient_id = s.patient_id
)

select
    channel,
    campaign,
    count(*)                                             as signups,
    count(*) filter (where converted)                    as subscribers,
    count(*) filter (where is_active_subscriber)         as active_subscribers,
    round(sum(total_marketing_cost), 2)                  as total_spend,
    -- customer acquisition cost per signup
    round(sum(total_marketing_cost) / nullif(count(*), 0), 2)                     as cac_per_signup,
    -- spend per acquired subscriber
    round(sum(total_marketing_cost) / nullif(count(*) filter (where converted), 0), 2) as cac_per_subscriber,
    -- current monthly revenue attributed to the channel
    sum(mrr_amount) filter (where is_active_subscriber)  as active_mrr
from joined
where channel is not null
group by 1, 2
order by signups desc
