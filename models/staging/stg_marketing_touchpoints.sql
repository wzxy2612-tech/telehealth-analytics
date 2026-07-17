with source as (
    select * from {{ source('raw', 'marketing_touchpoints') }}
)

select
    touchpoint_id,
    anonymous_id,
    nullif(patient_id, '')                     as patient_id,
    lower(channel)                             as channel,
    lower(utm_medium)                          as utm_medium,
    lower(campaign)                            as campaign,
    lower(event_type)                          as event_type,
    cast(cost as double)                       as cost,
    cast(event_at as timestamp)                as event_at,
    cast(_loaded_at as timestamp)              as _loaded_at
from source
