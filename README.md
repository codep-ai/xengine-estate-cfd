# xengine-estate-cfd

The shared contract of the CFD tick estate: one producer that is not a dbt project (the Kafka Connect Iceberg sink writing four tick
tables to S3, catalogued in Glue `cfd`) and two dbt consumers that read the same Iceberg tables in place — Snowflake (audit tier,
`xengine-consumer-cfd-snowflake`) and ClickHouse (realtime/serving tier, `xengine-consumer-cfd-clickhouse`). `estate.yml` lists the
projects, the Glue-backed Snowflake pointers, and the pipeline id under which the stitched column lineage is stored.

    X=/home/ec2-user/git/datapai-platform-be
    python $X/scripts/xengine.py snowflake-sync --estate estate.yml     # once
    python $X/scripts/xengine.py lineage        --estate estate.yml --to-db

## One command for the whole estate

    ./xestate.sh build      # dbt build + docs generate in every project, producer first
    ./xestate.sh lineage    # stitch all projects into one column-lineage graph, persist it, optionally publish the JSON
    ./xestate.sh sync       # Snowflake pointers for the raw layer (once, or when a raw table is added)
    ./xestate.sh all        # build, then lineage

Publish beside the public page: `PUBLISH_DIR=/path/to/public/data-governance PUBLISH_AS=lineage_xengine_cfd.json ./xestate.sh lineage`.
Never run ad-hoc dbt commands inside a consumer repo (`dbt show` rewrites the manifest without compiled SQL and empties its lineage).
