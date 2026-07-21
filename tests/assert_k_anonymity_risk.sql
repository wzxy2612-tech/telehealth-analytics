{{ config(severity = 'warn') }}

with risk_cells as (
    select 
        age_band, 
        gender, 
        race, 
        ethnicity, 
        state, 
        zip3, 
        count(distinct patient_id) as k
    from {{ ref('mart_clinical_encounters') }}
    group by 1, 2, 3, 4, 5, 6
)

select *
from risk_cells
where k < 5