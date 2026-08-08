-- What the CRM company table looks like after the import: existing rows plus
-- the deduplicated new rows. In production this is a MERGE into the real
-- table (scripts/merge_into_company.sql) rather than a rebuilt model.
select
    company_id, company_name, address, city, state, zip,
    phone_number, website, primary_contact,
    'crm' as record_source
from {{ ref('stg_crm_company') }}

union all

select
    company_id, company_name, address, city, state, zip,
    phone_number, website, primary_contact,
    source_record_key as record_source
from {{ ref('companies_to_import') }}
