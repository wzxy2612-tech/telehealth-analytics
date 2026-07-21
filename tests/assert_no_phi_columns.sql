{{ config(severity = 'error', tags = ['governance', 'phi_boundary']) }}
/*
    Executable PHI boundary. The column list lives in one place --
    seeds/phi_column_registry.csv -- and is consumed by both load.py (which
    never lands tier 1) and this test (which proves it). A list that exists
    twice will drift; this one cannot.

    Tier 1: direct identifiers, banned everywhere including raw.
    Tier 2: inputs to Safe Harbor generalisation. Allowed in raw and staging,
            banned in anything the dashboards read.

    Matching is exact, never LIKE: `email_hash` is legitimate, `email` is not.
*/
with registry as (
    select
        lower(trim(column_name)) as column_name,
        cast(tier as integer)    as tier
    from {{ ref('phi_column_registry') }}
),
all_columns as (
    select
        table_schema,
        table_name,
        lower(column_name) as column_name
    from information_schema.columns
    where table_schema not in ('information_schema', 'pg_catalog')
)
select
    case r.tier
        when 1 then 'direct_identifier_present'
        else 'quasi_identifier_in_serving_layer'
    end as violation,
    c.table_schema,
    c.table_name,
    c.column_name
from all_columns c
join registry r
    on c.column_name = r.column_name
where r.tier = 1
   or (
        r.tier = 2
        and (
               starts_with(lower(c.table_name), 'dim_')
            or starts_with(lower(c.table_name), 'fct_')
            or starts_with(lower(c.table_name), 'mart_')
        )
      )