-- Casts raw TEXT columns to proper types. No business logic here.
with source as (
    select * from {{ source('raw', 'service_requests') }}
),

renamed as (
    select
        unique_key,

        -- Dates stored as ISO strings in Socrata; cast with NULL on parse failure
        nullif(created_date, '')::timestamptz                       as created_at,
        nullif(closed_date, '')::timestamptz                        as closed_at,
        nullif(due_date, '')::timestamptz                           as due_at,
        nullif(resolution_action_updated_date, '')::timestamptz     as resolved_updated_at,

        -- Agency
        upper(trim(agency))                                         as agency_code,
        trim(agency_name)                                           as agency_name,

        -- Complaint
        trim(complaint_type)                                        as complaint_type,
        trim(descriptor)                                            as descriptor,
        trim(location_type)                                         as location_type,

        -- Status
        upper(trim(status))                                         as status,
        trim(resolution_description)                                as resolution_description,

        -- Address
        trim(incident_address)                                      as incident_address,
        trim(street_name)                                           as street_name,
        trim(city)                                                  as city,
        trim(incident_zip)                                          as incident_zip,

        -- Geography
        coalesce(upper(trim(borough)), 'UNSPECIFIED')               as borough,
        trim(community_board)                                       as community_board,
        trim(bbl)                                                   as bbl,
        trim(park_facility_name)                                    as park_facility_name,
        trim(park_borough)                                          as park_borough,

        -- Coordinates — keep as numeric, NULL if unparseable
        case
            when latitude ~ '^-?[0-9]+\.?[0-9]*$' then latitude::numeric
        end                                                         as latitude,
        case
            when longitude ~ '^-?[0-9]+\.?[0-9]*$' then longitude::numeric
        end                                                         as longitude,

        upper(trim(open_data_channel_type))                         as channel,

        _loaded_at

    from source
)

select * from renamed
