"""
Loads NYC 311 Service Requests into Postgres raw schema via Socrata API.
Uses offset-based pagination; ~35M rows total, default limit = 500k rows (fast demo).
"""

import os
import sys
import json
import requests
import psycopg2
import psycopg2.extras
from dotenv import load_dotenv
from tqdm import tqdm

load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), "..", ".env"))

DB_DSN = (
    f"host={os.getenv('POSTGRES_HOST', 'localhost')} "
    f"port={os.getenv('POSTGRES_PORT', '5432')} "
    f"dbname={os.getenv('POSTGRES_DB', 'nyc311')} "
    f"user={os.getenv('POSTGRES_USER', 'dq_user')} "
    f"password={os.getenv('POSTGRES_PASSWORD', 'dq_pass')}"
)

SOCRATA_ENDPOINT = "https://data.cityofnewyork.us/resource/erm2-nwe9.json"
APP_TOKEN = os.getenv("SOCRATA_APP_TOKEN", "")

# Columns we actually care about — keeping raw so nothing is cleaned here
COLUMNS = [
    "unique_key",
    "created_date",
    "closed_date",
    "agency",
    "agency_name",
    "complaint_type",
    "descriptor",
    "location_type",
    "incident_zip",
    "incident_address",
    "street_name",
    "city",
    "status",
    "due_date",
    "resolution_description",
    "resolution_action_updated_date",
    "community_board",
    "bbl",
    "borough",
    "x_coordinate_state_plane",
    "y_coordinate_state_plane",
    "open_data_channel_type",
    "park_facility_name",
    "park_borough",
    "latitude",
    "longitude",
    "location",
]

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS raw.service_requests (
    unique_key              TEXT,
    created_date            TEXT,
    closed_date             TEXT,
    agency                  TEXT,
    agency_name             TEXT,
    complaint_type          TEXT,
    descriptor              TEXT,
    location_type           TEXT,
    incident_zip            TEXT,
    incident_address        TEXT,
    street_name             TEXT,
    city                    TEXT,
    status                  TEXT,
    due_date                TEXT,
    resolution_description  TEXT,
    resolution_action_updated_date TEXT,
    community_board         TEXT,
    bbl                     TEXT,
    borough                 TEXT,
    x_coordinate_state_plane TEXT,
    y_coordinate_state_plane TEXT,
    open_data_channel_type  TEXT,
    park_facility_name      TEXT,
    park_borough            TEXT,
    latitude                TEXT,
    longitude               TEXT,
    location                TEXT,
    _loaded_at              TIMESTAMPTZ DEFAULT NOW()
);
"""

PAGE_SIZE = 50_000
MAX_ROWS = int(os.getenv("MAX_ROWS", "500000"))


def fetch_page(offset: int) -> list[dict]:
    headers = {"X-App-Token": APP_TOKEN} if APP_TOKEN else {}
    params = {
        "$limit": PAGE_SIZE,
        "$offset": offset,
        "$order": ":id",
    }
    resp = requests.get(SOCRATA_ENDPOINT, headers=headers, params=params, timeout=60)
    resp.raise_for_status()
    return resp.json()


def row_to_tuple(row: dict) -> tuple:
    def coerce(v):
        if isinstance(v, (dict, list)):
            return json.dumps(v)
        return v
    return tuple(coerce(row.get(col)) for col in COLUMNS)


def main():
    conn = psycopg2.connect(DB_DSN)
    conn.autocommit = False
    cur = conn.cursor()

    cur.execute(CREATE_TABLE_SQL)
    cur.execute("TRUNCATE raw.service_requests")
    conn.commit()

    total_inserted = 0
    cols_placeholder = ", ".join(COLUMNS)
    values_placeholder = ", ".join(["%s"] * len(COLUMNS))
    insert_sql = f"INSERT INTO raw.service_requests ({cols_placeholder}) VALUES ({values_placeholder})"

    pbar = tqdm(total=MAX_ROWS, unit="rows", desc="Loading 311 data")

    offset = 0
    while total_inserted < MAX_ROWS:
        rows = fetch_page(offset)
        if not rows:
            break

        batch = [row_to_tuple(r) for r in rows]
        psycopg2.extras.execute_batch(cur, insert_sql, batch, page_size=1000)
        conn.commit()

        total_inserted += len(batch)
        offset += PAGE_SIZE
        pbar.update(len(batch))

        if len(rows) < PAGE_SIZE:
            break

    pbar.close()
    cur.close()
    conn.close()
    print(f"\nDone. Inserted {total_inserted:,} rows into raw.service_requests.")


if __name__ == "__main__":
    main()
