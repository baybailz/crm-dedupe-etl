-- The company dimension: master rows plus imported purchased rows.
-- Incremental on company_id, so each run upserts rather than rebuilds.
-- On Snowflake dbt compiles this to a MERGE; on DuckDB, delete+insert.
-- A reset passes --full-refresh to drop and rebuild from scratch.
{{ config(
    materialized='incremental',
    unique_key='company_id',
    tags=['master_data']
) }}

select
    company_id, company_name, address, city, state, zip,
    phone_number, website, primary_contact,
    'crm_company'         as source,
    cast(null as varchar) as source_record_key
from {{ ref('stg_company') }}

union all

select
    company_id, company_name, address, city, state, zip,
    phone_number, website, primary_contact,
    source_file || '.csv'   as source,
    source_record_key
from {{ ref('dim_company_purchased') }}
