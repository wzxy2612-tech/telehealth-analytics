{{
    config(
        materialized = 'table',
        tags = ['ehr']
    )
}}

/*
    Encounter-grain clinical fact table. One row per Synthea encounter.

    DELIBERATELY EXCLUDED
    ---------------------
    lifetime_healthcare_expenses, lifetime_healthcare_coverage and
    annual_income are cumulative patient-level attributes. Joining them onto
    an encounter grain means a patient with 80 encounters contributes their
    lifetime spend 80 times, and any sum() over this table is inflated by
    roughly the average encounter count. They stay on the patient dimension
    and nowhere else. See meta.additivity in _ehr__models.yml.

    PAYER ATTRIBUTION
    -----------------
    Coverage is joined from the FOLDED periods, not from raw
    payer_transitions. Against the raw table the range join would match one
    row per plan year and fan out this fact table by ~15x.

    has_payer_mismatch compares the payer recorded on the encounter against
    the payer implied by the coverage timeline. Non-zero counts are a real
    finding, not noise -- surface it rather than coalescing it away.
*/

with encounters as (

    select * from {{ ref('stg_ehr__encounters') }}

),

patients as (

    select * from {{ ref('stg_ehr__patients') }}

),

coverage as (

    select * from {{ ref('int_ehr__payer_periods_folded') }}

)

select
    e.encounter_id,
    e.patient_id,

    e.encounter_date,
    e.started_at,
    e.stopped_at,
    e.duration_minutes,

    e.encounter_class,
    e.is_virtual,
    e.encounter_code,
    e.encounter_description,
    e.reason_code,
    e.reason_description,

    -- De-identified patient attributes only. Nothing here is finer than
    -- state, a year, or an age band.
    p.age_band,
    p.gender,
    p.race,
    p.ethnicity,
    p.marital_status,
    p.state,
    p.zip3,

    e.encounter_payer_id,
    c.payer_id                                          as coverage_payer_id,
    c.payer_period_key,
    e.encounter_payer_id is distinct from c.payer_id    as has_payer_mismatch,
    c.payer_period_key is null                          as has_no_coverage_period,

    e.base_encounter_cost,
    e.total_claim_cost,
    e.payer_coverage,
    e.patient_responsibility

from encounters e

left join patients p
    on e.patient_id = p.patient_id

left join coverage c
    on  e.patient_id = c.patient_id
    and e.encounter_date >= c.valid_from
    and (c.valid_to is null or e.encounter_date < c.valid_to)
