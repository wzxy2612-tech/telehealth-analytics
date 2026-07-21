{{
    config(
        materialized = 'view',
        tags = ['ehr']
    )
}}

{% set gap_tolerance = var('payer_gap_tolerance_days', 1) %}

with transitions as (
    select
        patient_id,
        payer_id,
        member_id,
        valid_from,
        valid_to
    from {{ ref('stg_ehr__payer_transitions') }}
    where valid_from is not null
      and not is_invalid_interval -- 在此显式过滤脏数据
),

lagged as (
    select
        *,
        lag(payer_id) over (partition by patient_id order by valid_from, valid_to) as prev_payer_id,
        lag(valid_to) over (partition by patient_id order by valid_from, valid_to) as prev_valid_to
    from transitions
),

island_starts as (
    select
        *,
        case
            when prev_payer_id is null then 1
            when prev_payer_id is distinct from payer_id then 1
            when prev_valid_to is null then 0
            when date_diff('day', prev_valid_to, valid_from) > {{ gap_tolerance }} then 1
            else 0
        end as is_island_start
    from lagged
),

islanded as (
    select
        *,
        sum(is_island_start) over (
            partition by patient_id
            order by valid_from, valid_to
            rows between unbounded preceding and current row
        ) as payer_period_seq
    from island_starts
),

folded as (
    select
        patient_id,
        payer_period_seq,
        payer_id,
        min(valid_from) as valid_from,
        nullif(max(coalesce(valid_to, date '9999-12-31')), date '9999-12-31') as valid_to,
        count(*) as source_row_count,
        count(distinct member_id) as distinct_member_ids,
        arg_min(member_id, valid_from) as first_member_id,
        arg_max(member_id, valid_from) as last_member_id
    from islanded
    group by 1, 2, 3
)

select
    {{ dbt_utils.generate_surrogate_key(['patient_id', 'payer_period_seq']) }} as payer_period_key,
    patient_id,
    payer_period_seq,
    payer_id,
    first_member_id,
    last_member_id,
    distinct_member_ids,
    distinct_member_ids > 1                 as member_id_was_reissued,
    valid_from,
    valid_to,
    date_diff('day', valid_from, valid_to)  as coverage_days,
    source_row_count,
    payer_period_seq = max(payer_period_seq) over (partition by patient_id)
                                            as is_current_period
from folded