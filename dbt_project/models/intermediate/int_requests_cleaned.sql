with staged as (
    select * from {{ ref('stg_311_requests') }}
),

enriched as (
    select
        *,

        case
            when closed_at is not null and closed_at < created_at then true
            else false
        end                                                 as is_timeline_inverted,

        case
            when closed_at is not null
             and extract(epoch from (closed_at - created_at)) / 86400.0
                 not between 0 and 1825
            then true
            else false
        end                                                 as is_response_time_outlier,

        case
            when latitude is null or longitude is null then true
            when latitude = 0 or longitude = 0 then true
            when latitude not between 40.4 and 40.95 then true
            when longitude not between -74.26 and -73.70 then true
            else false
        end                                                 as is_geocoding_failed,

        (borough = 'UNSPECIFIED')                           as is_borough_unknown,

        case
            when status = 'CLOSED'
             and (resolution_description is null
                  or trim(resolution_description) = '')
            then true
            else false
        end                                                 as is_missing_resolution,

        (incident_address is null or trim(incident_address) = '')
                                                            as is_address_missing,

        case
            when closed_at is not null and not (closed_at < created_at)
            then extract(epoch from (closed_at - created_at)) / 3600.0
        end                                                 as response_time_hours

    from staged
)

select * from enriched
