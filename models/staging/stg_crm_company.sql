-- Existing CRM companies with normalized match keys alongside the raw values.
with src as (
    select * from {{ ref('crm_company') }}
),

normalized as (
    select
        company_id,
        company_name,
        address,
        city,
        state,
        zip,
        phone_number,
        website,
        primary_contact,
        {{ normalize_company_name('company_name') }}       as name_norm,
        {{ normalize_address('address') }}                 as address_norm,
        lower(trim(city))                                  as city_norm,
        upper(trim(state))                                 as state_norm,
        left({{ digits_only('zip') }}, 5)                  as zip5,
        right({{ digits_only('phone_number') }}, 10)       as phone10,
        {{ url_domain('website') }}                        as domain
    from src
)

select
    n.*,
    coalesce(a.canonical, n.name_norm)          as name_match,
    {{ street_number('n.address_norm') }}       as street_num
from normalized n
left join {{ ref('company_name_aliases') }} a
    on n.name_norm = a.alias
