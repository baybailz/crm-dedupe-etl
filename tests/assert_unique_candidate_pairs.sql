-- Guards: the union across the blocking passes. A pair found by two passes
-- must be compared once, not twice, or every score double counts.
-- Any row returned fails the build.

select
    record_key,
    matched_side,
    matched_id
from {{ ref('trn_scored_pairs') }}
group by record_key, matched_side, matched_id
having count(*) > 1
