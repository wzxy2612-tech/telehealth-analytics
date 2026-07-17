{#
    Use the +schema config value verbatim (staging / intermediate / marts)
    instead of dbt's default "<target_schema>_<custom_schema>". Keeps schema
    names clean and predictable across dev / ci / prod.

    On production warehouses you may prefer the default behaviour (which
    namespaces by target) to isolate dev builds. If so, delete this macro.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
