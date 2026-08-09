{#
  Shared normalization macros. Both sides of every comparison run through
  these, so master and purchased data are cleaned the same way.
    normalize_company_name   lowercase, strip punctuation + legal suffixes
    normalize_address        USPS abbreviations: Street->st, Northwest->nw
    digits_only, url_domain, street_number   phone, domain, house number
    similarity               Jaro-Winkler, 0..1 on DuckDB and Snowflake
  replace_all exists because DuckDB replaces only the FIRST match unless
  the 'g' option is passed; Snowflake's regexp_replace is global already.
#}

{% macro replace_all(expr, pattern, replacement) -%}
  {%- if target.type == 'snowflake' -%}
    regexp_replace({{ expr }}, '{{ pattern }}', '{{ replacement }}')
  {%- else -%}
    regexp_replace({{ expr }}, '{{ pattern }}', '{{ replacement }}', 'g')
  {%- endif -%}
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
      regexp_replace(lower(trim(coalesce({{ col }}, ''))), '^https?://', ''),
      '^www[.]', ''),
    '')
{%- endmacro %}

{% macro street_number(col) -%}
  {% if target.type == 'snowflake' -%}
    regexp_substr({{ col }}, '^[0-9]+')
  {%- else -%}
    nullif(regexp_extract({{ col }}, '^[0-9]+'), '')
  {%- endif %}
{%- endmacro %}

{% macro similarity(a, b) -%}
  {% if target.type == 'snowflake' -%}
    jarowinkler_similarity({{ a }}, {{ b }}) / 100.0
  {%- else -%}
    jaro_winkler_similarity({{ a }}, {{ b }})
  {%- endif %}
{%- endmacro %}
