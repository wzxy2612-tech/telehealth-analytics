-- Current-state snapshot of each Chargebee subscription.
with source as (
    select * from {{ source('raw', 'subscriptions') }}
)

select
    subscription_id,
    patient_id,
    lower(plan_id)                                   as plan_id,
    cast(mrr_amount as integer)                      as mrr_amount,
    lower(status)                                    as status,
    cast(started_at as date)                         as started_at,
    -- empty string in CSV -> null date
    try_cast(nullif(cancelled_at, '') as date)       as cancelled_at,
    cast(created_at as timestamp)                    as created_at,
    cast(updated_at as timestamp)                    as updated_at,
    cast(_loaded_at as timestamp)                    as _loaded_at
from source
