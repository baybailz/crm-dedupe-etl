{#
  Row-count audit. Every conformed and datamart model writes one row per
  build via post-hook, so "when did this last load and how big was it" is a
  query, not a log search. Mirrors the enterprise metadata_audit post-hook.
#}
{% macro create_audit_table() -%}
  {% if execute %}
    create schema if not exists audit;
    create table if not exists audit.tbl_metadata_audit (
        model_name      varchar,
        row_count       bigint,
        invocation_id   varchar,
        loaded_at       timestamp
    );
  {% endif %}
{%- endmacro %}

{% macro metadata_audit() -%}
  insert into audit.tbl_metadata_audit
  select '{{ this.identifier }}', count(*), '{{ invocation_id }}', current_timestamp
  from {{ this }}
{%- endmacro %}
