-- Appointment fact, one row per appointment.
--
-- INCREMENTAL: on a scheduled run only rows updated since the last build are
-- processed, instead of rebuilding the whole table. This is the pattern that
-- keeps warehouse cost/runtime flat as the table grows (the point of Redshift
-- Serverless cost control). `updated_at` is the watermark.
{{
    config(
        materialized='incremental',
        unique_key='appointment_id',
        incremental_strategy='delete+insert'
    )
}}

with enriched as (
    select * from {{ ref('int_appointments_enriched') }}
)

select
    appointment_id,
    patient_id,
    provider_id,
    provider_specialty,
    patient_state,
    signup_channel      as patient_signup_channel,
    appointment_type,
    status,
    is_completed,
    is_no_show,
    is_cancelled,
    lead_time_days,
    appointment_date,
    appointment_week,
    appointment_month,
    scheduled_at,
    created_at,
    updated_at
from enriched

{% if is_incremental() %}
    -- only new/changed rows since the last run
    where updated_at > (select coalesce(max(updated_at), '1900-01-01') from {{ this }})
{% endif %}
