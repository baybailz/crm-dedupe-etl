{#
  Shared SQL helpers.
  replace_all exists because DuckDB replaces only the FIRST match unless the
  'g' option is passed; Snowflake's regexp_replace is global already.
#}

{% macro replace_all(expr, pattern, replacement) -%}
  {%- if target.type == 'snowflake' -%}
    regexp_replace({{ expr }}, '{{ pattern }}', '{{ replacement }}')
  {%- else -%}
    regexp_replace({{ expr }}, '{{ pattern }}', '{{ replacement }}', 'g')
  {%- endif -%}
{%- endmacro %}
