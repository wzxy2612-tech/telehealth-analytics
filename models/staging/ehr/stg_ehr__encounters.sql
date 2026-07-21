{{
    config(
        materialized = 'view',
        tags = ['ehr']
    )
}}

/*
    Clinical encounters. Grain = one completed visit.

    Two things worth knowing about this source before building on it:

      1. There is no appointment lifecycle. Every row is a visit that
         happened. No scheduled / cancelled / no-show state exists, so the
         booking funnel and no-show rate stay owned by the SaaS domain.

      2. ENCOUNTERCLASS is overwhelmingly in-person. On the 100-patient
         sample, `virtual` is 3 rows out of 7,210 (0.04%). is_virtual below is
         kept as an honest breadcrumb, not as a metric anyone should chart.
*/

with source as (

    select * from {{ source('ehr', 'synthea_encounters') }}

),

renamed as (

    select
        "Id"                        as encounter_id,
        "PATIENT"                   as patient_id,
        "ORGANIZATION"              as organization_id,
        "PROVIDER"                  as provider_id,
        "PAYER"                     as encounter_payer_id,

        cast("START" as timestamp)  as started_at,
        cast("STOP"  as timestamp)  as stopped_at,

        lower("ENCOUNTERCLASS")     as encounter_class,
        "CODE"                      as encounter_code,
        "DESCRIPTION"               as encounter_description,
        "REASONCODE"                as reason_code,
        "REASONDESCRIPTION"         as reason_description,

        -- Fee-for-service claim economics, not subscription billing. There is
        -- no MRR / churn / expansion semantics available here; that lives in
        -- the SaaS domain and the two must not be conflated.
        cast("BASE_ENCOUNTER_COST" as decimal(18, 2)) as base_encounter_cost,
        cast("TOTAL_CLAIM_COST"    as decimal(18, 2)) as total_claim_cost,
        cast("PAYER_COVERAGE"      as decimal(18, 2)) as payer_coverage

    from source

)

select
    encounter_id,
    patient_id,
    organization_id,
    provider_id,
    encounter_payer_id,

    started_at,
    stopped_at,
    cast(started_at as date)                        as encounter_date,
    date_diff('minute', started_at, stopped_at)     as duration_minutes,

    encounter_class,
    encounter_class = 'virtual'                     as is_virtual,
    encounter_code,
    encounter_description,
    reason_code,
    reason_description,

    base_encounter_cost,
    total_claim_cost,
    payer_coverage,
    total_claim_cost - payer_coverage               as patient_responsibility

from renamed
