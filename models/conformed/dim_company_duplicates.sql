-- Deliverable 1: the duplicate report for the sales team.
-- One row per suspect pair: what it matched, where, and the similarity
-- scores behind the call.
{{ config(materialized='table', tags=['master_data']) }}

select
    record_key,
    source_file,
    company_name,
    address_1,
    city,
    state,
    zip,
    case matched_side
        when 'crm' then 'existing CRM company'
        when 'within_file' then 'earlier record in same file'
        when 'cross_file' then 'record in other file'
    end                     as duplicate_of,
    matched_id,
    matched_name,
    matched_address,
    round(name_sim, 3)      as name_similarity,
    round(addr_sim, 3)      as address_similarity,
    phone_match,
    domain_match,
    match_class
from {{ ref('trn_scored_pairs') }}
where match_class is not null
order by record_key, matched_id
