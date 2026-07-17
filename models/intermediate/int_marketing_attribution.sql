-- Resolve marketing touches to patients and compute first/last-touch per
-- patient. Pre-signup touches carry only anonymous_id; we bridge to patient_id
-- via the anonymous_id assigned at signup. Grain: one row per patient.
with touchpoints as (
    select * from {{ ref('stg_marketing_touchpoints') }}
),
patients as (
    select patient_id, anonymous_id, signed_up_at from {{ ref('stg_patients') }}
),

-- attach patient_id to every touch (linked directly, or via anonymous_id)
resolved as (
    select
        coalesce(t.patient_id, p.patient_id) as patient_id,
        t.channel,
        t.campaign,
        t.cost,
        t.event_at
    from touchpoints t
    left join patients p on t.anonymous_id = p.anonymous_id
    where coalesce(t.patient_id, p.patient_id) is not null
),

ranked as (
    select
        *,
        row_number() over (partition by patient_id order by event_at asc)  as touch_seq_asc,
        row_number() over (partition by patient_id order by event_at desc) as touch_seq_desc
    from resolved
),

agg as (
    select
        patient_id,
        count(*)          as touch_count,
        sum(cost)         as total_marketing_cost,
        min(event_at)     as first_touch_at,
        max(event_at)     as last_touch_at
    from resolved
    group by 1
)

select
    a.patient_id,
    a.touch_count,
    round(a.total_marketing_cost, 2)  as total_marketing_cost,
    a.first_touch_at,
    a.last_touch_at,
    ft.channel   as first_touch_channel,
    ft.campaign  as first_touch_campaign,
    lt.channel   as last_touch_channel,
    lt.campaign  as last_touch_campaign
from agg a
left join ranked ft on a.patient_id = ft.patient_id and ft.touch_seq_asc = 1
left join ranked lt on a.patient_id = lt.patient_id and lt.touch_seq_desc = 1
