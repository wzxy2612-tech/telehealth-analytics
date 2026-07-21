{{
    config(
        materialized = 'view',
        tags = ['ehr', 'phi_boundary']
    )
}}

with source as (
    select * from {{ source('ehr', 'synthea_payer_transitions') }}
),

renamed as (
    select
        "PATIENT"                       as patient_id,
        "PAYER"                         as payer_id,
        "SECONDARY_PAYER"               as secondary_payer_id,
        "MEMBERID"                      as member_id,
        "PLAN_OWNERSHIP"                as plan_ownership,
        cast("START_DATE" as date)      as valid_from,
        cast("END_DATE"   as date)      as valid_to
    from source
)

select 
    *,
    valid_to is not null and valid_to < valid_from as is_invalid_interval
from renamed
-- 移除 WHERE 过滤。Staging 保持与源数据的 1:1 映射。
-- 异常数据的剔除逻辑下推至 int 层，以保证行数对齐和指标可观测。