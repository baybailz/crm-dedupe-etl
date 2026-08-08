{#- Portability note: Snowflake treats backslash as an escape char in string
    literals, DuckDB does not. These macros deliberately avoid backslashes and
    regex backreferences so the same SQL compiles identically on both. -#}

{#- Company-name normalization: lowercase, strip punctuation, drop leading
    "the", strip trailing legal suffixes (inc/llc/co/...), collapse spaces.
    Brand aliases (711 -> 7 eleven) are applied afterward in staging via the
    company_name_aliases seed, which is easier to maintain than code. -#}
{% macro normalize_company_name(col) -%}
    trim(regexp_replace(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            regexp_replace(
              regexp_replace(lower(coalesce({{ col }}, '')), '[^a-z0-9 ]', ' '),
              ' +', ' '),
            '^the ', ''),
          ' (incorporated|inc|llc|corporation|corp|company|co|ltd|lp|llp)$', ''),
        ' (incorporated|inc|llc|corporation|corp|company|co|ltd|lp|llp)$', ''),
      ' +', ' '))
{%- endmacro %}

{#- Address normalization: lowercase, strip punctuation, standardize common
    USPS suffix/directional words via space-padded whole-word replace(),
    collapse spaces. Production note: a CASS-certified service or libpostal
    does this properly; this covers the high-frequency cases. -#}
{% macro normalize_address(col) -%}
    {%- set replacements = [
        ('northwest', 'nw'), ('northeast', 'ne'),
        ('southwest', 'sw'), ('southeast', 'se'),
        ('street', 'st'), ('avenue', 'ave'), ('boulevard', 'blvd'),
        ('road', 'rd'), ('drive', 'dr'), ('lane', 'ln'),
        ('parkway', 'pkwy'), ('highway', 'hwy'), ('suite', 'ste'),
    ] -%}
    trim(regexp_replace(
    {%- for old, new in replacements %}
        replace(
    {%- endfor %}
        ' ' || regexp_replace(regexp_replace(lower(coalesce({{ col }}, '')), '[^a-z0-9 ]', ' '), ' +', ' ') || ' '
    {%- for old, new in replacements %}
        , ' {{ old }} ', ' {{ new }} ')
    {%- endfor %}
    , ' +', ' '))
{%- endmacro %}

{% macro digits_only(col) -%}
    nullif(regexp_replace(coalesce({{ col }}, ''), '[^0-9]', ''), '')
{%- endmacro %}

{#- Root domain from a website value: drop protocol and leading www. -#}
{% macro url_domain(col) -%}
    nullif(
      regexp_replace(
        regexp_replace(lower(trim(coalesce({{ col }}, ''))), '^https?://', ''),
        '^www[.]', ''),
      '')
{%- endmacro %}

{#- Leading street number of an address, for the "same street number" signal. -#}
{% macro street_number(col) -%}
    {% if target.type == 'snowflake' -%}
        regexp_substr({{ col }}, '^[0-9]+')
    {%- else -%}
        nullif(regexp_extract({{ col }}, '^[0-9]+'), '')
    {%- endif %}
{%- endmacro %}

{#- Jaro-Winkler similarity scaled 0..1 on both engines.
    Snowflake returns 0..100; DuckDB returns 0..1. -#}
{% macro similarity(a, b) -%}
    {% if target.type == 'snowflake' -%}
        jarowinkler_similarity({{ a }}, {{ b }}) / 100.0
    {%- else -%}
        jaro_winkler_similarity({{ a }}, {{ b }})
    {%- endif %}
{%- endmacro %}
