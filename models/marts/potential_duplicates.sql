-- Deliverable #1: the list of potential duplicates for the sales team.
-- One row per suspect pair, with what it matched, where, and how strongly.
select
    l.record_key,
    l.source_file,
    l.company_name,
    l.address_1,
    l.city,
    l.state,
    l.zip,
    case p.matched_side
        when 'crm' then 'existing CRM company'
        when 'within_file' then 'earlier record in same file'
        when 'cross_file' then 'record in other file'
    end                                as duplicate_of,
    p.matched_id,
    p.matched_name,
    p.matched_address,
    round(p.name_sim, 3)               as name_similarity,
    round(p.addr_sim, 3)               as address_similarity,
    p.phone_match,
    p.domain_match,
    p.match_class
from {{ ref('int_scored_pairs') }} p
join {{ ref('stg_list_company') }} l using (record_key)
where p.match_class is not null
order by l.record_key
