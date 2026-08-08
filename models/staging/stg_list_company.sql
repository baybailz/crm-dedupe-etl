-- Both purchased lists, unioned, with a stable record key per row and the
-- same normalized match keys as the CRM side. In production the ingest step
-- stamps source filename + line number; for the seed-based demo we derive a
-- deterministic row number instead.
with unioned as (
    select 'list_a' as source_file, * from {{ ref('list_a') }}
    union all
    select 'list_b' as source_file, * from {{ ref('list_b') }}
),

numbered as (
    select
        *,
        row_number() over (
            partition by source_file
            order by company_name, address_1, city
        ) as row_num
    from unioned
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
    from numbered
)

select
    n.*,
    coalesce(a.canonical, n.name_norm)      as name_match,
    {{ street_number('n.address_norm') }}   as street_num
from normalized n
left join {{ ref('company_name_aliases') }} a
    on n.name_norm = a.alias
