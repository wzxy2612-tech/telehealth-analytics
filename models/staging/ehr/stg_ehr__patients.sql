{{
    config(
        materialized = 'view',
        tags = ['ehr', 'phi_boundary']
    )
}}

/*
    HIPAA Safe Harbor generalisation layer for Synthea patient records.

    The PHI boundary is enforced in two tiers:

      1. load.py never lands direct identifiers (SSN, DRIVERS, PASSPORT, name
         parts, ADDRESS, LAT, LON, BIRTHPLACE). They do not exist in the
         warehouse at any layer.

      2. This model generalises the quasi-identifiers that ARE landed because
         they are inputs to that generalisation:
           - dates      -> year only            (Safe Harbor #3)
           - age        -> banded, 90+ ceiling  (Safe Harbor #3)
           - ZIP        -> 3-digit prefix, suppressed to 000 for sparse areas
           - geography  -> nothing finer than state (Safe Harbor #2)
         CITY, COUNTY and FIPS are simply not selected.

    Both tiers are asserted by tests/assert_no_phi_columns.sql, which fails
    the build if a forbidden column name reappears. That test is what makes
    this a constraint rather than a comment.
*/

-- Three-digit ZIP prefixes whose combined population is <= 20,000 must be
-- reported as 000. This is the commonly cited list derived from 2000 Census
-- ZCTA data; HHS expects the threshold to be checked against *current* Census
-- data, so treat this as a seed list and re-derive it for real use.
-- Synthea's default population is Massachusetts (ZIP3 010-027), so none of
-- these fire on the sample -- the control is present, not exercised.
{% set restricted_zip3 = [
    '036', '059', '063', '102', '203', '556', '692', '790', '821',
    '823', '830', '831', '878', '879', '884', '890', '893'
] %}

with source as (

    select * from {{ source('ehr', 'synthea_patients') }}

),

typed as (

    select
        "Id"                                    as patient_id,

        cast("BIRTHDATE" as date)               as birth_date_raw,
        cast("DEATHDATE" as date)               as death_date_raw,

        cast("ZIP" as varchar)                  as zip_raw,
        "STATE"                                 as state,

        -- Non-identifying demographics may be retained under Safe Harbor.
        "MARITAL"                               as marital_status,
        "RACE"                                  as race,
        "ETHNICITY"                             as ethnicity,
        "GENDER"                                as gender,

        -- Cumulative, patient-level, and NOT additive across any fact grain.
        -- See meta.additivity in _ehr__models.yml. These belong on the patient
        -- dimension only; joining them onto encounters and summing gives a
        -- number inflated by the average encounter count per patient.
        cast("HEALTHCARE_EXPENSES" as decimal(18, 2)) as lifetime_healthcare_expenses,
        cast("HEALTHCARE_COVERAGE" as decimal(18, 2)) as lifetime_healthcare_coverage,
        cast("INCOME"              as decimal(18, 2)) as annual_income

    from source

),

aged as (

    select
        *,

        -- Age is computed against a pinned reference date, never current_date.
        -- A fixture whose charts drift with the wall clock produces changes
        -- that no commit explains.
        date_diff(
            'year',
            birth_date_raw,
            coalesce(
                death_date_raw,
                cast('{{ var("ehr_as_of_date", "2024-12-31") }}' as date)
            )
        ) as age_years

    from typed

)

select
    patient_id,

    -- Safe Harbor #3: dates reduced to year. Do not restore precision
    -- downstream by joining back to raw.
    year(birth_date_raw)                        as birth_year,
    year(death_date_raw)                        as death_year,
    death_date_raw is not null                  as is_deceased,

    -- Safe Harbor #3: everything above 89 collapses into a single bucket.
    case
        when age_years >= 90 then '90+'
        when age_years >= 75 then '75-89'
        when age_years >= 65 then '65-74'
        when age_years >= 50 then '50-64'
        when age_years >= 35 then '35-49'
        when age_years >= 18 then '18-34'
        when age_years >=  0 then '0-17'
    end                                         as age_band,

    -- Safe Harbor #2: 3-digit ZIP prefix, suppressed where the area is sparse.
    case
        when left(zip_raw, 3) in (
            {%- for z in restricted_zip3 %}'{{ z }}'{% if not loop.last %}, {% endif %}{% endfor -%}
        ) then '000'
        else left(zip_raw, 3)
    end                                         as zip3,
    state,

    marital_status,
    race,
    ethnicity,
    gender,

    lifetime_healthcare_expenses,
    lifetime_healthcare_coverage,
    annual_income

from aged
