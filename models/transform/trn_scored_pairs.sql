-- The matching engine: block, score, classify.
--   block     candidate pairs from the equality passes listed below
--   score     Jaro-Winkler on name + address, plus exact signals
--   classify  duplicate or nothing; a different street number is a new location
-- Both match sides fold into match_targets first, so the blocking and the
-- scoring are each written once instead of once per side.
{{ config(materialized='view', tags=['master_data']) }}

-- One pass per key below. Master data is always fair game; a purchased record
-- only compares against purchased records that came before it, so each pair is
-- produced once and within-file order is stable.
{% set candidate_join_keys = [
    ['zip5'],
    ['city_norm', 'state_norm'],
    ['phone10'],
    ['domain'],
] %}

with purchased_records as (
    select * from {{ ref('stg_purchased_company') }}
),

crm_companies as (
    select * from {{ ref('stg_company') }}
),

match_targets as (
    -- everything a purchased record can match against, in one shape
    select
        cast(crm_companies.company_id as varchar)  as target_id,
        'crm'                                    as target_kind,
        cast(null as varchar)                    as target_file,
        crm_companies.company_name                 as target_name,
        crm_companies.address                      as target_address,
        crm_companies.name_match,
        crm_companies.address_norm,
        crm_companies.zip5,
        crm_companies.city_norm,
        crm_companies.state_norm,
        crm_companies.street_num,
        crm_companies.phone10,
        crm_companies.domain
    from crm_companies

    union all

    select
        purchased_records.record_key,
        'purchased',
        purchased_records.source_file,
        purchased_records.company_name,
        purchased_records.address_1,
        purchased_records.name_match,
        purchased_records.address_norm,
        purchased_records.zip5,
        purchased_records.city_norm,
        purchased_records.state_norm,
        purchased_records.street_num,
        purchased_records.phone10,
        purchased_records.domain
    from purchased_records
),

candidates as (
{% for keys in candidate_join_keys %}
    select
        purchased_records.record_key,
        match_targets.target_id,
        match_targets.target_kind
    from purchased_records
    inner join match_targets
        on {% for key in keys %}purchased_records.{{ key }} = match_targets.{{ key }}{{ ' and ' if not loop.last }}{% endfor %}

        and (match_targets.target_kind = 'crm'
             or match_targets.target_id < purchased_records.record_key)
    {{ 'union' if not loop.last }}
{% endfor %}
),

pairs as (
    select
        purchased_records.record_key,
        purchased_records.source_file,
        purchased_records.company_name,
        purchased_records.address_1,
        purchased_records.city,
        purchased_records.state,
        purchased_records.zip,
        case
            when match_targets.target_kind = 'crm'                     then 'crm'
            when match_targets.target_file = purchased_records.source_file   then 'within_file'
            else 'cross_file'
        end                                          as matched_side,
        match_targets.target_id                       as matched_id,
        match_targets.target_name                     as matched_name,
        match_targets.target_address                  as matched_address,
        {{ similarity('purchased_records.name_match', 'match_targets.name_match') }}     as name_sim,
        {{ similarity('purchased_records.address_norm', 'match_targets.address_norm') }} as addr_sim,
        (purchased_records.zip5 = match_targets.zip5)       as zip_match,
        (purchased_records.city_norm = match_targets.city_norm
            and purchased_records.state_norm = match_targets.state_norm) as city_match,
        (purchased_records.street_num is not null
            and purchased_records.street_num = match_targets.street_num) as street_match,
        (purchased_records.phone10 = match_targets.phone10) as phone_match,
        (purchased_records.domain = match_targets.domain)   as domain_match
    from candidates
    inner join purchased_records
        on purchased_records.record_key = candidates.record_key
    inner join match_targets
        on match_targets.target_id = candidates.target_id
        and match_targets.target_kind = candidates.target_kind
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
from pairs
