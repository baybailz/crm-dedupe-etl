-- All vendor-list records loaded so far (seeds/vendor_records.csv, generated
-- by scripts/load_next.py from the files in incoming/), with a stable record
-- key of source file + original file row number, and the same normalized
-- match keys as the CRM side.
with src as (
    select * from {{ ref('vendor_records') }}
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
        ) }}                                         as address_norm,
        lower(trim(city))                            as city_norm,
        upper(trim(state))                           as state_norm,
        left({{ digits_only('zip') }}, 5)            as zip5,
        right({{ digits_only('primary_phone_number') }}, 10) as phone10,
        {{ url_domain('website') }}                  as domain
    from src
)

select
    n.*,
    coalesce(a.canonical, n.name_norm)      as name_match,
    {{ street_number('n.address_norm') }}   as street_num
from normalized n
left join {{ ref('company_name_aliases') }} a
    on n.name_norm = a.alias
