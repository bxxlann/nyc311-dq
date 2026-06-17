# NYC 311 Data Quality ELT Project

End-to-end ELT pipeline on real open government data, demonstrating how raw
public datasets carry systematic quality issues and how to surface, flag, and
handle them with dbt.

**Stack:** Python (Socrata API) → PostgreSQL (Docker) → dbt (staging / intermediate / marts) → dbt-expectations

---

## Architecture

```
Socrata API (NYC Open Data)
        │
        ▼
 raw.service_requests       ← TEXT-only, nothing cleaned
        │
        ▼
 staging.stg_311_requests   ← type casts, trim, NULL coercion
        │
        ▼
 intermediate.int_requests_cleaned  ← DQ boolean flags added, no rows dropped
        │
     ┌──┴────────────────┐
     ▼                   ▼
 marts.fct_requests    marts.mart_dq_summary
 (clean rows only)     (aggregate DQ report)

        + marts.dim_agency (canonical agency names)
```

---

## Quick Start

```bash
# 1. Clone & enter the project
git clone <repo-url>
cd nyc311-dq

# 2. Copy env file and edit if needed
cp .env.example .env

# 3. Start Postgres
docker compose up -d

# 4. Install Python deps and load data (default: 500k rows, ~5 min)
cd ingest
pip install -r requirements.txt
python load_311.py

# 5. Run dbt
cd ../dbt_project
pip install dbt-postgres
dbt deps
dbt build          # runs models + tests in one shot

# 6. Inspect the DQ summary
psql -h localhost -U dq_user -d nyc311 \
  -c "SELECT * FROM marts.mart_dq_summary ORDER BY pct_affected DESC;"
```

To load more rows, set `MAX_ROWS` env var before running the ingest script:
```bash
MAX_ROWS=5000000 python load_311.py
```

---

## Data Quality Issues Found

All findings are based on the first 500k rows (2010–present). Percentages are
approximate and shift with the full ~35M row dataset.

### 1. Geocoding failures (~18% of rows)

**What I found:** `latitude` and `longitude` are NULL for a large share of
complaints. A smaller but non-trivial subset has `latitude = 0, longitude = 0`
— a classic sentinel value left over when the geocoder returned no result.
Cross-referencing with `borough = 'UNSPECIFIED'` shows near-perfect overlap,
confirming these records were never successfully geocoded.

**How handled:** `is_geocoding_failed` flag in `int_requests_cleaned`. The mart
`fct_requests` excludes these rows. `dim_agency` and `mart_dq_summary` still
count them so the magnitude is visible.

---

### 2. Timeline inversions — closed before opened (~0.03% of rows)

**What I found:** A small but consistent set of records where `closed_date <
created_date`. Some appear to be timezone offset errors (off-by-one-hour around
DST boundaries). Others have multi-day inversions, suggesting manual data
corrections entered with the wrong year.

**How handled:** `is_timeline_inverted = TRUE` flag. These rows are excluded
from `fct_requests`. `response_time_hours` is NULL-ed out for them in the
intermediate layer to prevent negative durations from polluting aggregations.

---

### 3. Impossible response times (~0.2% of closed rows)

**What I found:** Some closed tickets have a resolution time longer than 5
years. The extreme outlier was a ticket apparently open for 40+ years — clearly
a data entry error on the close date. A few tickets show sub-minute resolution
times for complaint types that require physical inspection (e.g., "HEATING"), 
which are equally suspect.

**How handled:** `is_response_time_outlier` flag for anything outside [0, 1825]
days. The dbt-expectations test on `response_time_hours` in `fct_requests` fires
as a `warn` so the pipeline doesn't break but the issue is surfaced in CI logs.

---

### 4. Missing resolution descriptions on closed tickets (~8% of closed rows)

**What I found:** `resolution_description` is NULL or empty for ~8% of tickets
with `status = 'CLOSED'`. A closed ticket with no resolution text means there
is no audit trail for what action was taken — a data completeness problem, not
just a cosmetic one.

**How handled:** `is_missing_resolution` flag. These rows are kept in
`fct_requests` (we don't exclude on completeness alone) but the flag lets
analysts filter them out for SLA analysis where a description is required.

---

### 5. Agency name inconsistencies (detected in `dim_agency`)

**What I found:** Several `agency_code` values appear with multiple distinct
`agency_name` spellings (extra spaces, abbreviations, occasional typos). For
example, the Department of Housing Preservation and Development appears as both
"Department of Housing Preservation and Development" and "HPD" depending on the
year the record was created.

**How handled:** `dim_agency.has_name_inconsistency = TRUE` flags affected
agencies. The canonical name is chosen as the most-frequently-occurring variant.

---

### 6. Borough = 'UNSPECIFIED' (~18% of rows)

**What I found:** The `borough` field falls back to the literal string
`"Unspecified"` whenever geocoding fails, rather than NULL. This means a simple
`WHERE borough = 'MANHATTAN'` query silently excludes nearly one-fifth of the
dataset without any warning.

**How handled:** Normalised to `'UNSPECIFIED'` (uppercase) at the staging layer
so it's clearly distinguishable from real borough values. The
`accepted_values` test in `stg_311_requests.yml` includes `UNSPECIFIED` as a
legal value (not an error) but the `is_borough_unknown` flag lets downstream
models handle it explicitly.

---

## dbt Test Coverage

| Layer | Test type | Tests run |
|---|---|---|
| Staging | `not_null`, `unique`, `accepted_values` | 8 |
| Staging | `dbt_expectations` range checks | 4 |
| Intermediate | `not_null`, `unique` | 3 |
| Intermediate | `dbt_expectations` range + set | 3 |
| Marts | `not_null`, `unique` | 3 |
| Marts | `dbt_expectations` range | 1 |
| Singular | Custom SQL assertions | 2 |
| **Total** | | **24** |

Run tests only (without rebuilding models):
```bash
dbt test
```

---

## Key Learnings

- **Never trust geocoding fields.** Lat/lon = 0 is not an error message — it
  looks like valid data until you plot it in the Atlantic Ocean.
- **Flag, don't drop.** Removing dirty rows at the staging layer hides the
  problem. Flagging at the intermediate layer lets you measure the impact and
  make an explicit decision per use case.
- **Composite quality.** A single row can fail multiple checks simultaneously.
  Tracking each dimension separately lets you prioritise fixes — e.g.,
  geocoding failures are far more common than timeline inversions.
- **dbt-expectations** fills the gap between dbt's built-in tests (which check
  structure) and real anomaly detection (range checks, distribution assertions,
  set membership).

---

## Project Structure

```
nyc311-dq/
├── docker-compose.yml          # Postgres 16
├── init.sql                    # Schema creation on first boot
├── .env.example
├── ingest/
│   ├── requirements.txt
│   └── load_311.py             # Socrata → raw.service_requests
└── dbt_project/
    ├── dbt_project.yml
    ├── profiles.yml
    ├── packages.yml             # dbt_utils + dbt_expectations
    ├── models/
    │   ├── staging/
    │   │   ├── sources.yml
    │   │   ├── stg_311_requests.sql
    │   │   └── stg_311_requests.yml
    │   ├── intermediate/
    │   │   ├── int_requests_cleaned.sql
    │   │   └── int_requests_cleaned.yml
    │   └── marts/
    │       ├── fct_requests.sql
    │       ├── dim_agency.sql
    │       ├── mart_dq_summary.sql
    │       └── marts.yml
    └── tests/
        ├── assert_no_duplicate_unique_keys.sql
        └── assert_fct_requests_no_dirty_rows.sql
```
