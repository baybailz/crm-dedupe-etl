-- What importing blind would have produced: every master row and every
-- purchased row side by side, with no matching in between.
-- cluster_key is the normalized name, so rows that are the same company
-- land next to each other and in_cluster marks the collisions.
--
-- The only model in the project that reads stage instead of conformed.
-- That is the point of it: it is the picture before the matching layer.

with crm_side as (
    select
        stg_company.company_name,
        stg_company.address,
        stg_company.city,
        stg_company.state,
        stg_company.zip,
        stg_company.phone_number,
        'crm_company' as source,
        stg_company.name_match as cluster_key
    from {{ ref('stg_company') }} as stg_company
),

purchased_side as (
    select
        stg_purchased_company.company_name,
        stg_purchased_company.address_1 as address,
        stg_purchased_company.city,
        stg_purchased_company.state,
        stg_purchased_company.zip,
        stg_purchased_company.primary_phone_number as phone_number,
        stg_purchased_company.source_file || '.csv' as source,
        stg_purchased_company.name_match as cluster_key
    from {{ ref('stg_purchased_company') }} as stg_purchased_company
),

unioned as (
    select * from crm_side
    union all
    select * from purchased_side
)

select
    unioned.company_name,
    unioned.address,
    unioned.city,
    unioned.state,
    unioned.zip,
    unioned.phone_number,
    unioned.source,
    unioned.cluster_key,
    count(*) over (partition by unioned.cluster_key) > 1 as in_cluster,
    current_timestamp as dbt_run_timestamp
from unioned
