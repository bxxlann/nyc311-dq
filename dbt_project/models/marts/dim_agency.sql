with all_agencies as (
    select
        agency_code,
        agency_name,
        count(*) as name_occurrences
    from {{ ref('stg_311_requests') }}
    where agency_code is not null
    group by agency_code, agency_name
),

ranked as (
    select
        agency_code,
        agency_name,
        name_occurrences,
        row_number() over (
            partition by agency_code
            order by name_occurrences desc
        ) as rn,
        count(*) over (partition by agency_code) as distinct_name_variants
    from all_agencies
)

select
    agency_code,
    agency_name                                     as canonical_name,
    name_occurrences,
    distinct_name_variants,
    (distinct_name_variants > 1)                    as has_name_inconsistency
from ranked
where rn = 1
