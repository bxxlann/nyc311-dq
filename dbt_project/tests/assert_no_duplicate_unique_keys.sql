-- Singular test: returns rows only if duplicates exist (non-zero = test fails).
select
    unique_key,
    count(*) as cnt
from {{ ref('stg_311_requests') }}
where unique_key is not null
group by unique_key
having count(*) > 1
