#!/bin/bash
# xestate — run the whole estate from its estate.yml with one command (one per team repo is xdbt.sh; this is the shared one).
#   ./xestate.sh build     dbt build + docs generate in every project of estate.yml, producer first (the order in the file)
#   ./xestate.sh docs      docs generate only (refresh artefacts without rebuilding tables)
#   ./xestate.sh glue-sync Glue pointers for Snowflake-written marts (defer-to-lake for DuckDB dev; Python/Athena readers)
#   ./xestate.sh sync      Snowflake pointers for the raw layer (snowflake_sync in estate.yml; once, or when a raw table is added)
#   ./xestate.sh lineage   stitch every project's manifest+catalog into one column-lineage graph, persist it (--to-db), copy the JSON
#                          beside the public page when PUBLISH_DIR is set (default: none)
#   ./xestate.sh all       build, then lineage
# Never run ad-hoc dbt commands inside a consumer repo: `dbt show` rewrites the manifest without compiled SQL and empties its lineage.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ESTATE="$HERE/estate.yml"
X="${XENGINE_HOME:-/home/ec2-user/git/datapai-platform-be}"; PY="${XENGINE_PY:-/home/ec2-user/venv_ai_etl/bin/python}"
set -a; source /home/ec2-user/.env.dev; set +a
unset DBT_PROFILE DBT_TARGET DBT_PROJECT_PATH DBT_PROJECT_DIR
export DBT_PROFILES_DIR=/home/ec2-user/.dbt AWS_DEFAULT_REGION=ap-southeast-2
projects() { "$PY" - "$ESTATE" <<'PYEOF'
import sys, yaml
for p in yaml.safe_load(open(sys.argv[1]))["projects"]: print(p["name"], p["project_dir"], p.get("dbt_bin", "/home/ec2-user/venv_ai_etl/bin/dbt"), p.get("profiles_dir", "/home/ec2-user/.dbt"))
PYEOF
}
# per-project dbt (v1 or v2) + profiles dir from estate.yml. dbt v2 (dbt-oss) writes catalog.json only via `compile --write-catalog`
# (its `docs generate` builds the Parquet info schema instead), and the stitcher needs catalog.json + manifest.json from every project.
run_dbt() { local what="$1"; while read -r name dir bin pdir; do
  echo "== $name ($what) [$(basename $(dirname $(dirname $bin)))]"
  if [ "$what" = "docs generate" ] && "$bin" --version 2>/dev/null | grep -q -E "dbt-oss|dbt 2\.|installed: 2\."; then
    (cd "$dir" && DBT_PROFILES_DIR="$pdir" "$bin" compile --write-catalog -q && DBT_PROFILES_DIR="$pdir" "$bin" docs generate -q && echo "   v2: catalog.json + manifest.json + info_schema written")
  else
    (cd "$dir" && DBT_PROFILES_DIR="$pdir" "$bin" $what)
  fi
done < <(projects); }
cmd="${1:-help}"
case "$cmd" in
  build)   run_dbt build; run_dbt "docs generate" ;;
  docs)    run_dbt "docs generate" ;;
  sync)    (cd "$X" && "$PY" scripts/xengine.py snowflake-sync --estate "$ESTATE") ;;
  glue-sync) (cd "$X" && "$PY" scripts/xengine.py glue-sync --estate "$ESTATE") ;;   # prod marts -> Glue pointers (defer-to-lake)
  lineage) (cd "$X" && "$PY" scripts/xengine.py lineage --estate "$ESTATE" --to-db)
           out="$HERE/$("$PY" -c "import sys,yaml; print(yaml.safe_load(open(sys.argv[1])).get('lineage_out','lineage_xengine.json'))" "$ESTATE")"
           "$PY" -c "import json,sys; s=json.load(open(sys.argv[1]))['summary']; print('lineage:', s['nodes'], 'tables |', s['edges'], 'column edges |', s['cross_engine_edges'], 'cross-engine |', len(s['not_built']), 'not built')" "$out"
           if [ -n "${PUBLISH_DIR:-}" ] && [ -n "${PUBLISH_AS:-}" ]; then cp "$out" "$PUBLISH_DIR/$PUBLISH_AS" && echo "published -> $PUBLISH_DIR/$PUBLISH_AS"; fi ;;
  all)     "$0" build; "$0" lineage ;;
  *)       sed -n 2,10p "$0" ;;
esac
