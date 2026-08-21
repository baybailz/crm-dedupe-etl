-- The company dimension: master rows plus imported purchased rows.
-- Incremental on company_id, so a repeated run upserts instead of duplicating.
-- A reset passes --full-refresh to rebuild from scratch.
{{ config(materialized='incremental', unique_key='company_id') }}

select
    company_id, company_name, address, city, state, zip,
    {{ phone_display('phone_number') }} as phone_number,
    website, primary_contact,
    'crm_company' as source,
    cast(null as varchar) as source_record_key,
    current_timestamp as dbt_run_timestamp
from {{ ref('stg_company') }}

union all

select
    company_id, company_name, address, city, state, zip,
    {{ phone_display('phone_number') }} as phone_number,
    website, primary_contact,
    source_file || '.csv' as source,
    source_record_key,
    current_timestamp as dbt_run_timestamp
from {{ ref('dim_purchased_company') }}
