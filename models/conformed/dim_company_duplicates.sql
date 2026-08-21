-- Deliverable 1: the duplicate report, one row per suspect pair.
-- A row colliding with master data and three earlier purchased rows appears
-- four times here. dim_record_status is the record-grained view.

select
    record_key,
    source_file,
    company_name,
    address_1,
    city,
    state,
    zip,
    matched_id,
    matched_name,
    matched_address,
    round(name_sim, 3) as name_similarity,
    round(addr_sim, 3) as address_similarity,
    phone_match,
    domain_match,
    match_class,
    current_timestamp as dbt_run_timestamp
from {{ ref('trn_scored_pairs') }}
where match_class is not null
order by record_key, matched_id
