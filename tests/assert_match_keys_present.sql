-- A match key must never be blank: a blank key silently kills matching
-- and everything looks "new". Returns offending rows; any row fails the build.

select record_key as offender from {{ ref('stg_purchased_company') }}
where coalesce(name_match, '') = ''
union all
select cast(company_id as varchar) from {{ ref('stg_company') }}
where coalesce(name_match, '') = ''
