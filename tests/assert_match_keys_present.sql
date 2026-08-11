-- Guards: matching itself.
--
-- Nothing is ever compared on its raw name. "7-Eleven, Inc." is cleaned to
-- "7 eleven" first, and that cleaned value is what every comparison uses.
-- If the cleaning ever returns blank, that record has nothing to compare,
-- so it matches nobody and imports as a brand new company.
--
-- Nothing errors when this happens. The build stays green and the duplicate
-- turns up in the CRM later. It happened here once.
-- Any row returned fails the build.

select record_key as offender from {{ ref('stg_purchased_company') }}
where coalesce(name_match, '') = ''
union all
select cast(company_id as varchar) from {{ ref('stg_company') }}
where coalesce(name_match, '') = ''
