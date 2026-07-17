-- Medical Ops: one row per appointment (BI aggregates on the page).
select
    appointment_id,
    provider_specialty,
    patient_state,
    patient_signup_channel,
    appointment_type,
    status,
    is_completed,
    is_no_show,
    is_cancelled,
    lead_time_days,
    appointment_date,
    appointment_week,
    appointment_month
from marts.fct_appointments
