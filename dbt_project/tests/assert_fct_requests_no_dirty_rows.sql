-- Ensures the mart contains zero rows flagged by any DQ rule.
-- Joins back to the intermediate layer by unique_key.
select
    fct.unique_key
from {{ ref('fct_requests') }} fct
join {{ ref('int_requests_cleaned') }} mid
    on fct.unique_key = mid.unique_key
where mid.is_timeline_inverted
   or mid.is_geocoding_failed
   or mid.is_response_time_outlier
