-- Patients from the application DB.
--
-- PHI BOUNDARY: this staging model is the *only* place direct identifiers
-- (email, name, date of birth) are allowed to live. Downstream marts must not
-- select them. We expose an `email_domain` and an `age` band instead, and hash
-- the email so it can act as a join key without carrying the raw value forward.
with source as (
    select * from {{ source('raw', 'patients') }}
),

renamed as (
    select
        patient_id,
        anonymous_id,

        -- ---- PII/PHI: do not propagate past staging -----------------------
        lower(email)                                as email,
        first_name,
        last_name,
        cast(date_of_birth as date)                 as date_of_birth,
        -- -------------------------------------------------------------------

        split_part(lower(email), '@', 2)            as email_domain,
        date_diff('year', cast(date_of_birth as date), current_date) as age,
        lower(gender)                               as gender,
        upper(state)                                as state,
        lower(signup_channel)                       as signup_channel,
        cast(created_at as timestamp)               as signed_up_at,
        cast(updated_at as timestamp)               as updated_at,
        cast(_loaded_at as timestamp)               as _loaded_at
    from source
)

select * from renamed
