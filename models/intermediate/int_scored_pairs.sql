-- Candidate-pair generation (blocking) + fuzzy scoring + classification.
--
-- Blocking: only compare records that share zip5 OR city+state. This keeps the
-- comparison space near-linear instead of N x M. In production you'd add more
-- blocks (phone, domain, name prefix) and union them.
--
-- Every list record is compared against (1) the CRM table and (2) every
-- *earlier* list record (by record_key), which covers within-file and
-- cross-file duplicates without double-counting pairs.

with list_recs as (
    select * from {{ ref('stg_list_company') }}
),

crm as (
    select * from {{ ref('stg_crm_company') }}
),

crm_pairs as (
    select
        a.record_key,
        'crm'                       as matched_side,
        cast(b.company_id as varchar) as matched_id,
        b.company_name              as matched_name,
        b.address                   as matched_address,
        {{ similarity('a.name_match', 'b.name_match') }}       as name_sim,
        {{ similarity('a.address_norm', 'b.address_norm') }}   as addr_sim,
        (a.zip5 = b.zip5)                                        as zip_match,
        (a.city_norm = b.city_norm and a.state_norm = b.state_norm) as city_match,
        (a.street_num is not null and a.street_num = b.street_num)  as street_match,
        (a.phone10 = b.phone10)                                  as phone_match,
        (a.domain = b.domain)                                    as domain_match
    from list_recs a
    join crm b
      on a.zip5 = b.zip5
      or (a.city_norm = b.city_norm and a.state_norm = b.state_norm)
),

file_pairs as (
    select
        a.record_key,
        case when a.source_file = b.source_file
             then 'within_file' else 'cross_file' end as matched_side,
        b.record_key                as matched_id,
        b.company_name              as matched_name,
        b.address_1                 as matched_address,
        {{ similarity('a.name_match', 'b.name_match') }}       as name_sim,
        {{ similarity('a.address_norm', 'b.address_norm') }}   as addr_sim,
        (a.zip5 = b.zip5)                                        as zip_match,
        (a.city_norm = b.city_norm and a.state_norm = b.state_norm) as city_match,
        (a.street_num is not null and a.street_num = b.street_num)  as street_match,
        (a.phone10 = b.phone10)                                  as phone_match,
        (a.domain = b.domain)                                    as domain_match
    from list_recs a
    join list_recs b
      on b.record_key < a.record_key       -- each unordered pair once
     and (a.zip5 = b.zip5
          or (a.city_norm = b.city_norm and a.state_norm = b.state_norm))
),

scored as (
    select * from crm_pairs
    union all
    select * from file_pairs
)

select
    *,
    case
        -- Confirmed duplicate: same-ish name, same geography, same street
        -- number, similar street text.
        when name_sim >= 0.85
             and (coalesce(zip_match, false) or coalesce(city_match, false))
             and coalesce(street_match, false)
             and addr_sim >= 0.70
            then 'duplicate'
        -- Hard identifier (phone/domain) backs up a decent name match.
        when (coalesce(phone_match, false) or coalesce(domain_match, false))
             and name_sim >= 0.80
             and coalesce(street_match, false)
            then 'duplicate'
        -- Name is a near-exact hit in the same city but the address differs:
        -- could be a second location or a bad address. A human decides.
        when name_sim >= 0.92
             and (coalesce(zip_match, false) or coalesce(city_match, false))
            then 'review'
    end as match_class
from scored
