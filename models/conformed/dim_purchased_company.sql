-- Deliverable 3: the clean insert set, mapped to the CRM schema.
-- Only status = 'new'. New company_ids continue the CRM sequence.
{{ config(materialized='table', tags=['master_data']) }}

with new_records as (
    select * from {{ ref('dim_record_status') }}
    where status = 'new'
),

max_id as (
    select max(company_id) as max_company_id from {{ ref('stg_company') }}
)

select
    max_id.max_company_id
      + row_number() over (order by new_records.record_key)   as company_id,
    new_records.company_name,
    trim(coalesce(new_records.address_1, '')
      || case when new_records.address_2 is not null and new_records.address_2 <> ''
              then ' ' || new_records.address_2 else '' end
      || case when new_records.address_3 is not null and new_records.address_3 <> ''
              then ' ' || new_records.address_3 else '' end)  as address,
    new_records.city,
    new_records.state,
    new_records.zip,
    new_records.primary_phone_number                          as phone_number,
    new_records.website,
    cast(null as varchar)                                     as primary_contact,
    new_records.source_file,
    new_records.record_key                                    as source_record_key
from new_records
cross join max_id
