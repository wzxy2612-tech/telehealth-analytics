-- Shared patient dimension (PHI-minimised).
select
    patient_id,
    state,
    gender,
    age_band,
    signup_date,
    signup_cohort_month,
    signup_channel,
    first_touch_channel,
    acquisition_cost
from marts.dim_patients
