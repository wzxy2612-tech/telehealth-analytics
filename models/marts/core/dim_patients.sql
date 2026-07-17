-- Patient dimension for BI. PHI-minimised: NO email, name, or DOB. Age is
-- bucketed into bands; acquisition context comes from the attribution model.
with patients as (
    select * from {{ ref('stg_patients') }}
),
attribution as (
    select * from {{ ref('int_marketing_attribution') }}
)

select
    p.patient_id,
    p.state,
    p.gender,
    case
        when p.age < 25 then '18-24'
        when p.age < 35 then '25-34'
        when p.age < 45 then '35-44'
        when p.age < 55 then '45-54'
        when p.age < 65 then '55-64'
        else '65+'
    end                                             as age_band,
    cast(p.signed_up_at as date)                    as signup_date,
    date_trunc('month', p.signed_up_at)             as signup_cohort_month,
    p.signup_channel,
    a.first_touch_channel,
    a.last_touch_channel,
    coalesce(a.touch_count, 0)                       as marketing_touch_count,
    coalesce(a.total_marketing_cost, 0)             as acquisition_cost
from patients p
left join attribution a on p.patient_id = a.patient_id
