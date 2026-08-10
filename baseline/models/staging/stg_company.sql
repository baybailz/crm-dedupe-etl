-- Staging view over the CRM company table.
-- Collapses stray whitespace so the dimension reads clean values.
{{ config(materialized='view', tags=['master_data']) }}

select
    company_id,
    trim({{ replace_all("coalesce(company_name, '')", ' +', ' ') }}) as company_name,
    trim({{ replace_all("coalesce(address, '')", ' +', ' ') }})      as address,
    trim(city)          as city,
    upper(trim(state))  as state,
    trim(zip)           as zip,
    phone_number,
    website,
    primary_contact
from {{ ref('crm_company') }}
