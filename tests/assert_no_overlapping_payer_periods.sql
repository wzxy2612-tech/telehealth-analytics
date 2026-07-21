{{ config(severity = 'error', tags = ['ehr']) }}

/*
    Coverage periods are half-open [valid_from, valid_to): the end date is the
    first day NOT covered, so a period may end on the same date the next one
    begins. Anything strictly beyond that is a real overlap and would fan out
    the range join in mart_clinical_encounters.

    This began as a silent clamp inside the fold. It fired on 317 of ~570
    periods -- which meant the interval convention was wrong, not the data.
    Replacing repair with assertion is the point: a real overlap now fails
    loudly instead of quietly truncating a period.
*/

select patient_id, payer_period_seq, valid_to, next_valid_from
from (
    select
        patient_id,
        payer_period_seq,
        valid_to,
        lead(valid_from) over (
            partition by patient_id order by payer_period_seq
        ) as next_valid_from
    from {{ ref('int_ehr__payer_periods_folded') }}
)
where next_valid_from is not null
  and valid_to > next_valid_from
