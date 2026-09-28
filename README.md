# xengine-estate-cfd

The shared contract of the CFD tick estate: one producer that is not a dbt project (the Kafka Connect Iceberg sink writing four tick
tables to S3, catalogued in Glue `cfd`) and two dbt consumers that read the same Iceberg tables in place — Snowflake (audit tier,
`xengine-consumer-cfd-snowflake`) and ClickHouse (realtime/serving tier, `xengine-consumer-cfd-clickhouse`). `estate.yml` lists the
projects, the Glue-backed Snowflake pointers, and the pipeline id under which the stitched column lineage is stored.

    X=/home/ec2-user/git/datapai-platform-be
    python $X/scripts/xengine.py snowflake-sync --estate estate.yml     # once
    python $X/scripts/xengine.py lineage        --estate estate.yml --to-db
