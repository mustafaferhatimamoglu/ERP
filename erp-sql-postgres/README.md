ERP SQL Schema (PostgreSQL)

This repository contains a minimal, production-ready starting schema for an ERP system targeting PostgreSQL. It covers core domains: security, master data, products, partners, inventory, sales, purchasing, and accounting.

Requirements
- PostgreSQL 12+
- Access to `psql`

Quick Start

1) Create a database (if you don’t have one):

`createdb erp_dev`

2) Load the schema, then optional sample data:

`psql -d erp_dev -f erp_schema_postgres.sql`

`psql -d erp_dev -f erp_sample_seed.sql`

3) Explore some data:

`psql -d erp_dev -c "select * from erp.products;"`

What’s Included
- Security: `users`, `roles`, `permissions`, mappings
- Master data: `companies`, `currencies`, `units`, `tax_codes`, `addresses`
- Products: categories, products
- Partners: customers/suppliers via unified `partners` with contacts
- Inventory: warehouses, stock levels, stock movements
- Sales: orders, order lines, AR invoices, payments
- Purchasing: POs, PO lines, AP invoices, payments
- Accounting: chart of accounts, journals, journal entries (header + lines)

Notes
- All primary keys are `bigserial` for simplicity.
- Timestamps default to `now()` in UTC (`timestamptz`).
- Status fields are constrained via CHECKs to keep portability.
- Passwords are stored as `password_hash` (no hashing performed here). Hash in your application before inserting.

Next Steps
- Add triggers or application logic to automatically create journal entries from source docs.
- Add indices to fit your workload; some helpful ones are included.
- Extend with BOM/Manufacturing, Projects, HR/Payroll if needed.

Portability
This schema uses PostgreSQL-specific features sparingly. If you need MySQL or another RDBMS, let me know and I’ll adapt the DDL.

Remote Access (Allow connections from other machines)
- Server config: this setup enables PostgreSQL to listen on all interfaces and accept TCP connections with SCRAM auth.
- What was changed on the server:
  - `listen_addresses = '*'` in `/etc/postgresql/17/main/postgresql.conf` (requires service restart)
  - Added to `/etc/postgresql/17/main/pg_hba.conf`:
    - `host    all    all    0.0.0.0/0    scram-sha-256`
    - `host    all    all    ::/0         scram-sha-256`
- Restart service: `sudo systemctl restart postgresql`
- Verify listening: `ss -ltnp | grep 5432` should show `0.0.0.0:5432` and `[::]:5432`.
- Firewall: allow inbound TCP/5432 on your OS/router.
  - UFW example: `sudo ufw allow 5432/tcp`
  - iptables example: `sudo iptables -A INPUT -p tcp --dport 5432 -j ACCEPT`
  - nftables example: `sudo nft add rule inet filter input tcp dport 5432 accept`

Credentials and Connection URLs
- Default DB name: `erp_dev`
- App user: `erp_user`
- App password: `1q` (change in production; see below)
- Local URL: `postgresql://erp_user:1q@127.0.0.1:5432/erp_dev`
- LAN URL (replace `<SERVER_IP>` with your server’s IP):
  - `postgresql://erp_user:1q@<SERVER_IP>:5432/erp_dev`
  - Find IP: `hostname -I` or `ip -4 addr show scope global`

Change Passwords
- Change app user password: `psql -c "ALTER ROLE erp_user WITH PASSWORD 'NewStrong#Pass1';"`
- Optionally set a password for `postgres` superuser (avoid remote use):
  - `sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'Another#Pass2';"`
  - Restrict `pg_hba.conf` so `postgres` is not allowed from remote hosts.

Security Notes
- The `pg_hba.conf` rules above allow password-protected access from any IP. For tighter security, replace `0.0.0.0/0` and `::/0` with your CIDR ranges, e.g. `192.168.1.0/24`.
- Always use strong passwords and rotate them regularly. Consider enabling TLS for external networks.

Automated Setup Scripts
- Install and configure PostgreSQL (Debian/Kali):
  - `export DB_USER="erp_user" DB_PASS="1q" DB_NAME="erp_dev"`
  - `bash scripts/erp_postgres_setup.sh`
  - Prints local and LAN connection URLs at the end.
- Load schema and seed data:
  - `export DB_USER="erp_user" DB_PASS="1q" DB_NAME="erp_dev" DB_HOST="127.0.0.1"`
  - `bash scripts/load_erp_schema.sh` (use `--no-seed` to skip demo data)

Command Log (this chat ran)
- `sudo apt-get update && sudo apt-get install -y postgresql postgresql-contrib`
- `sudo systemctl enable --now postgresql`
- `sudo -u postgres createuser --createdb erp_user`
- `sudo -u postgres psql -c "ALTER ROLE erp_user WITH PASSWORD '1q';"`
- `sudo -u postgres createdb -O erp_user erp_dev`
- In `/etc/postgresql/17/main/postgresql.conf`: set `listen_addresses='*'`
- In `/etc/postgresql/17/main/pg_hba.conf`: add `host all all 0.0.0.0/0 scram-sha-256` and `host all all ::/0 scram-sha-256`
- `sudo systemctl restart postgresql`
- Verify: `ss -ltnp | grep 5432` and `sudo -u postgres psql -c "SHOW listen_addresses;"`
