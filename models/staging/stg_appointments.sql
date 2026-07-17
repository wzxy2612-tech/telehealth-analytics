with source as (
    select * from {{ source('raw', 'appointments') }}
)

select
    appointment_id,
    patient_id,
    provider_id,
    lower(appointment_type)          as appointment_type,
    lower(status)                    as status,
    cast(scheduled_at as timestamp)  as scheduled_at,
    cast(created_at as timestamp)    as created_at,
    cast(updated_at as timestamp)    as updated_at,

    -- convenience flags used all over the appointment marts
    (lower(status) = 'completed')    as is_completed,
    (lower(status) = 'no_show')      as is_no_show,
    (lower(status) = 'cancelled')    as is_cancelled,

    cast(_loaded_at as timestamp)    as _loaded_at
from source
