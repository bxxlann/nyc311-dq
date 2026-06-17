-- Aggregate DQ report: one row per flag, showing volume and % affected.
-- This is the table you screenshot for the README / portfolio.
with flags as (
    select
        count(*)                                                    as total_rows,
        sum(is_timeline_inverted::int)                              as timeline_inverted,
        sum(is_response_time_outlier::int)                          as response_time_outlier,
        sum(is_geocoding_failed::int)                               as geocoding_failed,
        sum(is_borough_unknown::int)                                as borough_unknown,
        sum(is_missing_resolution::int)                             as missing_resolution,
        sum(is_address_missing::int)                                as address_missing
    from {{ ref('int_requests_cleaned') }}
),

unpivoted as (
    select 'Timeline inverted (closed < created)'  as dq_issue, timeline_inverted        as affected_rows, total_rows from flags union all
    select 'Response time outlier (> 5 yr / < 0)', response_time_outlier,                               total_rows from flags union all
    select 'Geocoding failed (null / zero / OOB)',  geocoding_failed,                                    total_rows from flags union all
    select 'Borough = UNSPECIFIED',                 borough_unknown,                                     total_rows from flags union all
    select 'Closed with no resolution description', missing_resolution,                                  total_rows from flags union all
    select 'Incident address missing',              address_missing,                                     total_rows from flags
)

select
    dq_issue,
    affected_rows,
    total_rows,
    round(100.0 * affected_rows / nullif(total_rows, 0), 2) as pct_affected
from unpivoted
order by affected_rows desc
