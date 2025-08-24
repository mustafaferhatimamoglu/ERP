#!/usr/bin/env bash
set -euo pipefail

# Load ERP schema and optional seed data into an existing database.
# Usage:
#   export DB_USER="erp_user" DB_PASS="changeMe!" DB_NAME="erp_dev" DB_HOST="127.0.0.1" DB_PORT="5432"
#   bash scripts/load_erp_schema.sh [--no-seed]

DB_USER="${DB_USER:-erp_user}"
DB_PASS="${DB_PASS:-changeMe!}"
DB_NAME="${DB_NAME:-erp_dev}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"

NO_SEED="false"
if [[ ${1:-} == "--no-seed" ]]; then NO_SEED="true"; fi

URI="postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SCHEMA_FILE="$ROOT_DIR/erp_schema_postgres.sql"
SEED_FILE="$ROOT_DIR/erp_sample_seed.sql"

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "Schema file not found: $SCHEMA_FILE" >&2
  exit 1
fi

echo "Loading schema from $SCHEMA_FILE ..."
psql "$URI" -v ON_ERROR_STOP=1 -f "$SCHEMA_FILE"

if [[ "$NO_SEED" != "true" ]]; then
  if [[ -f "$SEED_FILE" ]]; then
    echo "Loading seed data from $SEED_FILE ..."
    psql "$URI" -v ON_ERROR_STOP=1 -f "$SEED_FILE"
  else
    echo "Seed file not found: $SEED_FILE (skipping)"
  fi
fi

echo "Done."

