#!/usr/bin/env bash
set -euo pipefail

# ERP PostgreSQL setup for Debian/Kali
# - Installs PostgreSQL server and contrib
# - Enables + starts service
# - Creates app role and database (idempotent)
# - Enables remote connections (listen on all interfaces)
# - Adds pg_hba rules for IPv4/IPv6 with SCRAM auth
# - Restarts service and prints connection info
#
# Usage:
#   sudo true  # ensure you can sudo (will prompt once)
#   export DB_USER="erp_user" DB_PASS="changeMe!" DB_NAME="erp_dev"
#   bash scripts/erp_postgres_setup.sh
#
# Optional env vars:
#   PG_VERSION (defaults to auto-detect e.g. 17)

DB_USER="${DB_USER:-erp_user}"
DB_PASS="${DB_PASS:-changeMe!}"
DB_NAME="${DB_NAME:-erp_dev}"

echo "[1/7] Installing PostgreSQL packages (requires sudo)..."
sudo apt-get update -y >/dev/null
sudo apt-get install -y postgresql postgresql-contrib >/dev/null

echo "[2/7] Enabling and starting service..."
sudo systemctl enable --now postgresql >/dev/null

PG_VERSION="${PG_VERSION:-}"
if [[ -z "${PG_VERSION}" ]]; then
  # Detect version from /etc/postgresql/*/main
  PG_DIR=$(ls -d /etc/postgresql/*/main 2>/dev/null | head -n1 || true)
  if [[ -z "${PG_DIR}" ]]; then
    echo "Could not detect PostgreSQL config dir under /etc/postgresql/*/main" >&2
    exit 1
  fi
  PG_VERSION=$(basename "$(dirname "${PG_DIR}")")
fi

CONF_DIR="/etc/postgresql/${PG_VERSION}/main"
CONF_FILE="${CONF_DIR}/postgresql.conf"
HBA_FILE="${CONF_DIR}/pg_hba.conf"

echo "[3/7] Creating role and database (idempotent)..."
# Create role if missing
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1; then
  sudo -u postgres createuser --createdb "${DB_USER}"
fi
# Ensure password
sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER ROLE \"${DB_USER}\" WITH PASSWORD '${DB_PASS}';" >/dev/null
# Create DB if missing
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
fi

echo "[4/7] Enabling remote connections (listen_addresses='*')..."
sudo bash -c "\
  if grep -Eq '^\s*listen_addresses\s*=.*' '${CONF_FILE}'; then \
    sed -i \"s/^\s*listen_addresses\s*=.*/listen_addresses = '\''*'\''/\" '${CONF_FILE}'; \
  else \
    printf \"\n# Added by setup: allow remote connections\nlisten_addresses = '\''*'\''\n\" >> '${CONF_FILE}'; \
  fi"

echo "[5/7] Adding pg_hba.conf rules for IPv4/IPv6 (scram-sha-256)..."
sudo bash -c "\
  add_line() { L=\"$1\"; grep -Fqx \"$L\" '${HBA_FILE}' || echo \"$L\" >> '${HBA_FILE}'; }; \
  add_line 'host    all             all             0.0.0.0/0               scram-sha-256'; \
  add_line 'host    all             all             ::/0                    scram-sha-256'; \
"

echo "[6/7] Restarting PostgreSQL to apply changes..."
sudo systemctl restart postgresql

echo "[7/7] Verifying..."
LISTEN=$(ss -ltnp 2>/dev/null | grep 5432 || true)
SHOW_LISTEN=$(sudo -u postgres psql -tAc "SHOW listen_addresses;" 2>/dev/null || true)
echo "listen_addresses=${SHOW_LISTEN}"
echo "$LISTEN"

# Try to detect a non-loopback IPv4
SERVER_IP=$(hostname -I 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i!~/^127\./ && $i!~/\:/){print $i; exit}}}')
SERVER_IP=${SERVER_IP:-127.0.0.1}

echo
echo "Done. Connection URLs:"
echo " - Local: postgresql://${DB_USER}:${DB_PASS}@127.0.0.1:5432/${DB_NAME}"
echo " - LAN:   postgresql://${DB_USER}:${DB_PASS}@${SERVER_IP}:5432/${DB_NAME}"
echo
echo "Security tip: Restrict pg_hba.conf to your LAN CIDR instead of 0.0.0.0/0 in production."

