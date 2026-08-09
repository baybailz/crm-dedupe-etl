"""Land vendor CSVs in Snowflake (production path).

PUT each file to a stage, then COPY INTO raw.vendor_list with
metadata$file_row_number as the lineage stamp. Same columns as the
demo seed, so dbt reads either engine unchanged.
"""

import os
import sys
from pathlib import Path

import snowflake.connector

DDL = """
create table if not exists raw.vendor_list (
    source_file           varchar,
    file_row_num          number,
    company_name          varchar,
    address_1             varchar,
    address_2             varchar,
    address_3             varchar,
    city                  varchar,
    state                 varchar,
    zip                   varchar,
    website               varchar,
    primary_phone_number  varchar,
    loaded_at             timestamp_ntz default current_timestamp()
)
"""


def main(paths: list[str]) -> None:
    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        password=os.environ["SNOWFLAKE_PASSWORD"],
        database=os.environ.get("SNOWFLAKE_DATABASE", "CRM_DEMO"),
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "COMPUTE_WH"),
    )
    cur = conn.cursor()
    cur.execute("create schema if not exists raw")
    cur.execute(DDL)
    cur.execute("create stage if not exists raw.vendor_stage")

    for path in paths:
        p = Path(path).resolve()
        cur.execute(f"put file://{p} @raw.vendor_stage overwrite = true")
        cur.execute(
            f"""
            copy into raw.vendor_list
                (source_file, file_row_num, company_name, address_1, address_2,
                 address_3, city, state, zip, website, primary_phone_number)
            from (
                select '{p.stem}', metadata$file_row_number,
                       $1, $2, $3, $4, $5, $6, $7, $8, $9
                from @raw.vendor_stage/{p.name}
            )
            file_format = (type = csv skip_header = 1
                           field_optionally_enclosed_by = '"')
            """
        )
        print(f"loaded {p.name}")

    conn.close()


if __name__ == "__main__":
    main(sys.argv[1:] or ["incoming/list_a.csv", "incoming/list_b.csv"])
