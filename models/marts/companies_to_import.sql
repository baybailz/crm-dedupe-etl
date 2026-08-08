-- Deliverable #3: clean records to insert into the CRM company table,
-- mapped from the vendor-list schema to the CRM schema. Only status = 'new'
-- records qualify, so re-running never creates duplicates (and the loader
-- MERGEs on top of that as a belt-and-braces guard).
--
-- Survivorship: when file records duplicate each other, the earliest record
-- key wins and is the one imported; the later ones carry duplicate_* status
-- and never reach this model.
with new_records as (
    select r.record_key
    from {{ ref('record_status') }} r
    where r.status = 'new'
),

max_id as (
    select max(company_id) as max_company_id from {{ ref('stg_crm_company') }}
)

select
    max_id.max_company_id
      + row_number() over (order by l.record_key)   as company_id,
    l.company_name,
    trim(coalesce(l.address_1, '')
      || case when l.address_2 is not null and l.address_2 <> ''
              then ' ' || l.address_2 else '' end
      || case when l.address_3 is not null and l.address_3 <> ''
              then ' ' || l.address_3 else '' end)  as address,
    l.city,
    l.state,
    l.zip,
    l.primary_phone_number                          as phone_number,
    l.website,
    cast(null as varchar)                           as primary_contact,
    l.record_key                                    as source_record_key
from new_records n
join {{ ref('stg_list_company') }} l using (record_key)
cross join max_id
