with providers as (
    select * from {{ ref('stg_providers') }}
)

select
    provider_id,
    provider_name,
    specialty,
    cast(created_at as date) as onboarded_date
from providers
