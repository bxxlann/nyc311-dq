-- One row per agency. Detects name inconsistencies across raw data.
with all_agencies as (
    select
        agency_code,
        agency_name,
        count(*) as name_occurrences
    from {{ ref('stg_311_requests') }}
    where agency_code is not null
    group by agency_code, agency_name
),

-- Pick the most-used name variant per code as the canonical name
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
    -- Flag agencies whose name appears in multiple variants (data quality signal)
    (distinct_name_variants > 1)                    as has_name_inconsistency
from ranked
where rn = 1
