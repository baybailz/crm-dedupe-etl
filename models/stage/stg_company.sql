-- Master data with the normalized match keys the matching layer compares on.
-- Brand aliases come from seeds/company_name_aliases.csv: stewards write
-- natural names (711 -> 7-Eleven), the normalizing happens here.
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
        {{ normalize_company_name('company_name') }} as name_norm,
        {{ normalize_address('address') }} as address_norm,
        nullif(lower(trim(city)), '') as city_norm,
        nullif(upper(trim(state)), '') as state_norm,
        left({{ digits_only('zip') }}, 5) as zip5,
        right({{ digits_only('phone_number') }}, 10) as phone10,
        {{ url_domain('website') }} as web_domain
    from src
)

select
    normalized.*,
    coalesce(nullif({{ normalize_company_name('company_name_aliases.canonical_name') }}, ''), normalized.name_norm) as name_match,
    {{ street_number('normalized.address_norm') }} as street_num
from normalized
left join {{ ref('company_name_aliases') }} as company_name_aliases
    on normalized.name_norm = {{ normalize_company_name('company_name_aliases.alias') }}
