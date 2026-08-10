-- The company dimension. One row per company in the CRM.
{{ config(materialized='table', tags=['master_data']) }}

select
    company_id,
    company_name,
    address,
    city,
    state,
    zip,
    phone_number,
    website,
    primary_contact
from {{ ref('stg_company') }}
