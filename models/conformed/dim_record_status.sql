-- Deliverable 2: one verdict per purchased record.
-- Spine is stage, not the transform: a record with no candidate pairs still
-- needs a verdict. Best match wins by priority: master, then file, else new.

with best_match as (
    select
        record_key,
        matched_side,
        matched_id,
        matched_name,
        match_class,
        -- A record can duplicate several things at once, but it gets one
        -- status, so rank its pairs and keep the first. matched_side sorts
        -- crm, cross_file, within_file: a match against master data outranks
        -- a match against another purchased file.
        row_number() over (
            partition by record_key
            order by matched_side asc, name_sim desc, matched_id asc
        ) as rn
    from {{ ref('trn_scored_pairs') }}
    where match_class is not null
)

select
    stg_purchased_company.record_key,
    stg_purchased_company.source_file,
    stg_purchased_company.company_name,
    stg_purchased_company.address_1,
    stg_purchased_company.address_2,
    stg_purchased_company.address_3,
    stg_purchased_company.city,
    stg_purchased_company.state,
    stg_purchased_company.zip,
    stg_purchased_company.website,
    stg_purchased_company.primary_phone_number,
    stg_purchased_company.phone10,
    case
        when best_match.match_class = 'duplicate' and best_match.matched_side = 'crm'
            then 'duplicate_of_crm'
        when best_match.match_class = 'duplicate' and best_match.matched_side = 'within_file'
            then 'duplicate_within_file'
        when best_match.match_class = 'duplicate' and best_match.matched_side = 'cross_file'
            then 'duplicate_cross_file'
        else 'new'
    end as status,
    best_match.matched_id,
    best_match.matched_name,
    current_timestamp as dbt_run_timestamp
from {{ ref('stg_purchased_company') }} as stg_purchased_company
left join best_match
    on stg_purchased_company.record_key = best_match.record_key and best_match.rn = 1
order by stg_purchased_company.record_key
