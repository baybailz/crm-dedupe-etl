-- The matching engine. Three moves:
--   1 block     candidate pairs from four equality passes:
--               zip5 · city+state · phone · domain. Each pass is one clean
--               hash join; add a key to the list below, add recall.
--   2 score     Jaro-Winkler on name + address, plus exact signals
--   3 classify  duplicate or nothing; same name at a different street
--               number is a new location, not a duplicate
-- Every vendor record is compared against the CRM and against every
-- earlier vendor record, so within-file and cross-file dups both fall out.
{{ config(materialized='view', tags=['master_data']) }}

{% set candidate_join_keys = [
    ['zip5'],
    ['city_norm', 'state_norm'],
    ['phone10'],
    ['domain'],
] %}

with list_records as (
    select * from {{ ref('stg_purchased_company') }}
),

crm_companies as (
    select * from {{ ref('stg_company') }}
),

crm_candidates as (
{% for keys in candidate_join_keys %}
    select list_record.record_key, crm_company.company_id
    from list_records as list_record
    inner join crm_companies as crm_company
        on {% for key in keys %}list_record.{{ key }} = crm_company.{{ key }}{{ ' and ' if not loop.last }}{% endfor %}
    {{ 'union' if not loop.last }}
{% endfor %}
),

file_candidates as (
{% for keys in candidate_join_keys %}
    select list_record.record_key, earlier_record.record_key as matched_key
    from list_records as list_record
    inner join list_records as earlier_record
        on earlier_record.record_key < list_record.record_key
        and {% for key in keys %}list_record.{{ key }} = earlier_record.{{ key }}{{ ' and ' if not loop.last }}{% endfor %}
    {{ 'union' if not loop.last }}
{% endfor %}
),

crm_pairs as (
    select
        list_record.record_key,
        list_record.source_file,
        list_record.company_name,
        list_record.address_1,
        list_record.city,
        list_record.state,
        list_record.zip,
        'crm'                                        as matched_side,
        cast(crm_company.company_id as varchar)      as matched_id,
        crm_company.company_name                     as matched_name,
        crm_company.address                          as matched_address,
        {{ similarity('list_record.name_match', 'crm_company.name_match') }}     as name_sim,
        {{ similarity('list_record.address_norm', 'crm_company.address_norm') }} as addr_sim,
        (list_record.zip5 = crm_company.zip5)        as zip_match,
        (list_record.city_norm = crm_company.city_norm
            and list_record.state_norm = crm_company.state_norm) as city_match,
        (list_record.street_num is not null
            and list_record.street_num = crm_company.street_num) as street_match,
        (list_record.phone10 = crm_company.phone10)  as phone_match,
        (list_record.domain = crm_company.domain)    as domain_match
    from crm_candidates
    inner join list_records as list_record
        on list_record.record_key = crm_candidates.record_key
    inner join crm_companies as crm_company
        on crm_company.company_id = crm_candidates.company_id
),

file_pairs as (
    select
        list_record.record_key,
        list_record.source_file,
        list_record.company_name,
        list_record.address_1,
        list_record.city,
        list_record.state,
        list_record.zip,
        case when list_record.source_file = earlier_record.source_file
             then 'within_file' else 'cross_file' end as matched_side,
        earlier_record.record_key                    as matched_id,
        earlier_record.company_name                  as matched_name,
        earlier_record.address_1                     as matched_address,
        {{ similarity('list_record.name_match', 'earlier_record.name_match') }}     as name_sim,
        {{ similarity('list_record.address_norm', 'earlier_record.address_norm') }} as addr_sim,
        (list_record.zip5 = earlier_record.zip5)     as zip_match,
        (list_record.city_norm = earlier_record.city_norm
            and list_record.state_norm = earlier_record.state_norm) as city_match,
        (list_record.street_num is not null
            and list_record.street_num = earlier_record.street_num) as street_match,
        (list_record.phone10 = earlier_record.phone10) as phone_match,
        (list_record.domain = earlier_record.domain)   as domain_match
    from file_candidates
    inner join list_records as list_record
        on list_record.record_key = file_candidates.record_key
    inner join list_records as earlier_record
        on earlier_record.record_key = file_candidates.matched_key
),

scored as (
    select * from crm_pairs
    union all
    select * from file_pairs
)

select
    *,
    case
        -- tier 1: name + geography + street number agree
        when name_sim >= 0.85
             and (coalesce(zip_match, false) or coalesce(city_match, false))
             and coalesce(street_match, false)
             and addr_sim >= 0.70
            then 'duplicate'
        -- tier 2: hard identifier (phone/domain) backs the name
        when (coalesce(phone_match, false) or coalesce(domain_match, false))
             and name_sim >= 0.80
             and coalesce(street_match, false)
            then 'duplicate'
    end as match_class
from scored
