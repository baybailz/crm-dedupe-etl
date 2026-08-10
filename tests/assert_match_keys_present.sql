-- Guards: matching itself. A blank match key scores 0.0 against everything,
-- so the record matches nothing and imports as new. Nothing errors.
-- Any row returned fails the build.

select record_key as offender from {{ ref('stg_purchased_company') }}
where coalesce(name_match, '') = ''
union all
select cast(company_id as varchar) from {{ ref('stg_company') }}
where coalesce(name_match, '') = ''
