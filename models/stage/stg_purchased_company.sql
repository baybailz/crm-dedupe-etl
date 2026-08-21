-- Purchased records with the same match keys as the master side, so the two
-- compare like-for-like. record_key is source file + line number.
with src as (
    -- The loader rewrites this seed from whatever files are loaded, then
    -- dbt seed lands it. See scripts/run.py.
    select * from {{ ref('purchased_company') }}
),

normalized as (
    select
        source_file || '-' || lpad(cast(row_num as varchar), 3, '0') as record_key,
        source_file,
        row_num,
        company_name,
        address_1,
        address_2,
        address_3,
        city,
        state,
        zip,
        website,
        primary_phone_number,
        {{ normalize_company_name('company_name') }} as name_norm,
        {{ normalize_address(
            "trim(coalesce(address_1,'') || ' ' || coalesce(address_2,'') || ' ' || coalesce(address_3,''))"
        ) }} as address_norm,
        nullif(lower(trim(city)), '') as city_norm,
        nullif(upper(trim(state)), '') as state_norm,
        left({{ digits_only('zip') }}, 5) as zip5,
        right({{ digits_only('primary_phone_number') }}, 10) as phone10,
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
