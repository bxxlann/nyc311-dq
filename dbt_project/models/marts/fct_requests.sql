-- Clean fact table: only records that pass all DQ checks.
-- Analysts who need dirty records should query int_requests_cleaned.
with cleaned as (
    select * from {{ ref('int_requests_cleaned') }}
),

valid_only as (
    select
        unique_key,
        created_at,
        closed_at,
        due_at,
        agency_code,
        agency_name,
        complaint_type,
        descriptor,
        location_type,
        status,
        resolution_description,
        incident_address,
        street_name,
        city,
        incident_zip,
        borough,
        community_board,
        latitude,
        longitude,
        channel,
        response_time_hours,
        _loaded_at
    from cleaned
    where not is_timeline_inverted
      and not is_geocoding_failed
      and not is_response_time_outlier
)

select * from valid_only
