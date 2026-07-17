-- Appointments joined to provider + patient context, with derived measures.
-- Grain: one row per appointment.
with appointments as (
    select * from {{ ref('stg_appointments') }}
),
providers as (
    select * from {{ ref('stg_providers') }}
),
patients as (
    select patient_id, state as patient_state, signup_channel from {{ ref('stg_patients') }}
)

select
    a.appointment_id,
    a.patient_id,
    a.provider_id,
    pr.specialty            as provider_specialty,
    p.patient_state,
    p.signup_channel,
    a.appointment_type,
    a.status,
    a.is_completed,
    a.is_no_show,
    a.is_cancelled,
    a.scheduled_at,
    cast(a.scheduled_at as date)                        as appointment_date,
    date_trunc('week', a.scheduled_at)                  as appointment_week,
    date_trunc('month', a.scheduled_at)                 as appointment_month,
    -- lead time between booking and the scheduled slot
    date_diff('day', a.created_at, a.scheduled_at)      as lead_time_days,
    a.created_at,
    a.updated_at
from appointments a
left join providers pr on a.provider_id = pr.provider_id
left join patients  p  on a.patient_id  = p.patient_id
