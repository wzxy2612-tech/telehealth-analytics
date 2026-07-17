with source as (
    select * from {{ source('raw', 'providers') }}
)

select
    provider_id,
    provider_name,
    specialty,
    cast(created_at as timestamp) as created_at,
    cast(_loaded_at as timestamp) as _loaded_at
from source
