{#
  Both sides of every comparison run through these, so master and purchased
  data get cleaned the same way.
  replace_all forces the 'g' flag: without it DuckDB replaces only the first
  match and silently truncates the value.
#}

{% macro replace_all(expr, pattern, replacement) -%}
  regexp_replace({{ expr }}, '{{ pattern }}', '{{ replacement }}', 'g')
{%- endmacro %}

{% macro normalize_company_name(col) -%}
  {%- set suffixes = ' (incorporated|inc|llc|corporation|corp|company|co|ltd|lp|llp)$' -%}
  {%- set e1 = replace_all("lower(coalesce(" ~ col ~ ", ''))", '[^a-z0-9 ]', ' ') -%}
  {%- set e2 = replace_all(e1, ' +', ' ') -%}
  {%- set e3 = replace_all("trim(" ~ e2 ~ ")", '^the ', '') -%}
  {%- set e4 = replace_all(e3, suffixes, '') -%}
  {%- set e5 = replace_all(e4, suffixes, '') -%}
  trim({{ replace_all(e5, ' +', ' ') }})
{%- endmacro %}

{% macro normalize_address(col) -%}
  {%- set replacements = [
      ('northwest', 'nw'), ('northeast', 'ne'),
      ('southwest', 'sw'), ('southeast', 'se'),
      ('street', 'st'), ('avenue', 'ave'), ('boulevard', 'blvd'),
      ('road', 'rd'), ('drive', 'dr'), ('lane', 'ln'),
      ('parkway', 'pkwy'), ('highway', 'hwy'), ('suite', 'ste'),
  ] -%}
  {%- set e1 = replace_all("lower(coalesce(" ~ col ~ ", ''))", '[^a-z0-9 ]', ' ') -%}
  {%- set e2 = replace_all(e1, ' +', ' ') -%}
  {%- set padded = "' ' || " ~ e2 ~ " || ' '" -%}
  trim({{ replace_all(usps_abbreviations(padded, replacements), ' +', ' ') }})
{%- endmacro %}

{% macro usps_abbreviations(expr, replacements) -%}
  {%- for old, new in replacements %}replace({% endfor -%}
  {{ expr }}
  {%- for old, new in replacements %}, ' {{ old }} ', ' {{ new }} '){% endfor -%}
{%- endmacro %}

{% macro digits_only(col) -%}
  nullif({{ replace_all("coalesce(" ~ col ~ ", '')", '[^0-9]', '') }}, '')
{%- endmacro %}

{% macro url_domain(col) -%}
  nullif(
    regexp_replace(
      regexp_replace(
        regexp_replace(lower(trim(coalesce({{ col }}, ''))), '^https?://', ''),
        '^www[.]', ''),
      '[/?#].*$', ''),
    '')
{%- endmacro %}

{% macro street_number(col) -%}
  nullif(regexp_extract({{ col }}, '^[0-9]+'), '')
{%- endmacro %}

{#- one display format for the dimension, whichever source a row came from -#}
{% macro phone_display(col) -%}
  {%- set d = digits_only(col) -%}
  case when length({{ d }}) = 10
       then '(' || substr({{ d }}, 1, 3) || ') ' || substr({{ d }}, 4, 3)
            || '-' || substr({{ d }}, 7, 4)
       else {{ col }} end
{%- endmacro %}

{% macro similarity(a, b) -%}
  jaro_winkler_similarity({{ a }}, {{ b }})
{%- endmacro %}
