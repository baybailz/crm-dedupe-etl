-- Deliverable #2: every record from both files with its disposition.
-- Priority: duplicate of CRM > duplicate of another file record >
-- needs_review > new.
with best_match as (
    select
        record_key,
        matched_side,
        matched_id,
        matched_name,
        match_class,
        row_number() over (
            partition by record_key
            order by
                case when match_class = 'duplicate' then 0 else 1 end,
                case matched_side
                    when 'crm' then 0
                    when 'cross_file' then 1
                    else 2
                end,
                name_sim desc
        ) as rn
    from {{ ref('int_scored_pairs') }}
    where match_class is not null
)

select
    l.record_key,
    l.source_file,
    l.company_name,
    l.address_1,
    l.city,
    l.state,
    l.zip,
    case
        when m.match_class = 'duplicate' and m.matched_side = 'crm'
            then 'duplicate_of_crm'
        when m.match_class = 'duplicate' and m.matched_side = 'within_file'
            then 'duplicate_within_file'
        when m.match_class = 'duplicate' and m.matched_side = 'cross_file'
            then 'duplicate_cross_file'
        when m.match_class = 'review'
            then 'needs_review'
        else 'new'
    end                 as status,
    m.matched_id,
    m.matched_name
from {{ ref('stg_list_company') }} l
left join best_match m
    on l.record_key = m.record_key and m.rn = 1
order by l.record_key
