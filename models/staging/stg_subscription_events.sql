-- Immutable subscription lifecycle log.
with source as (
    select * from {{ source('raw', 'subscription_events') }}
)

select
    event_id,
    subscription_id,
    lower(event_type)                          as event_type,
    nullif(from_plan, '')                      as from_plan,
    nullif(to_plan, '')                        as to_plan,
    cast(mrr_delta as integer)                 as mrr_delta,
    cast(event_at as timestamp)                as event_at,
    cast(_loaded_at as timestamp)              as _loaded_at
from source
