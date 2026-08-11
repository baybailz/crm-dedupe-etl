-- Guards: counting the same collision more than once.
--
-- A record can be flagged by several matching keys at once. list_a-005
-- ("The Home Depot") shares a zip, a city, a phone AND a website with the
-- CRM's Home Depot. That is one collision found four ways, not four
-- collisions, so the matching step keeps one copy. This checks it did.
--
-- If it ever stopped, the duplicate report would say that company is a
-- duplicate four times instead of once.
-- Any row returned fails the build.

select
    record_key,
    matched_side,
    matched_id
from {{ ref('trn_scored_pairs') }}
group by record_key, matched_side, matched_id
having count(*) > 1
