-- ERP Baseline Schema (PostgreSQL)
-- Minimal core for security, master data, products, partners, inventory, sales, purchasing, accounting

BEGIN;
SET client_min_messages TO WARNING;

CREATE SCHEMA IF NOT EXISTS erp;
SET search_path TO erp, public;

-- ===============
-- Master Data
-- ===============

CREATE TABLE IF NOT EXISTS currencies (
  code char(3) PRIMARY KEY,
  name text NOT NULL,
  symbol text,
  decimals smallint NOT NULL DEFAULT 2 CHECK (decimals BETWEEN 0 AND 6)
);

CREATE TABLE IF NOT EXISTS units (
  code text PRIMARY KEY,
  name text NOT NULL
);

CREATE TABLE IF NOT EXISTS tax_codes (
  id bigserial PRIMARY KEY,
  company_id bigint,
  code text NOT NULL,
  name text NOT NULL,
  rate numeric(7,4) NOT NULL CHECK (rate >= 0),
  kind text NOT NULL CHECK (kind IN ('VAT','GST','SALES','NONE')),
  UNIQUE (company_id, code)
);

CREATE TABLE IF NOT EXISTS addresses (
  id bigserial PRIMARY KEY,
  line1 text,
  line2 text,
  city text,
  state text,
  postal_code text,
  country_code char(2),
  phone text,
  email text
);

CREATE TABLE IF NOT EXISTS companies (
  id bigserial PRIMARY KEY,
  name text NOT NULL,
  legal_name text,
  tax_id text,
  default_currency char(3) NOT NULL REFERENCES currencies(code),
  address_id bigint REFERENCES addresses(id) ON DELETE SET NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS companies_currency_idx ON companies(default_currency);

-- ===============
-- Security
-- ===============

CREATE TABLE IF NOT EXISTS users (
  id bigserial PRIMARY KEY,
  company_id bigint REFERENCES companies(id) ON DELETE SET NULL,
  email text NOT NULL UNIQUE,
  password_hash text,
  first_name text,
  last_name text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS roles (
  id bigserial PRIMARY KEY,
  company_id bigint REFERENCES companies(id) ON DELETE CASCADE,
  name text NOT NULL,
  UNIQUE (company_id, name)
);

CREATE TABLE IF NOT EXISTS permissions (
  id bigserial PRIMARY KEY,
  code text NOT NULL UNIQUE,
  description text
);

CREATE TABLE IF NOT EXISTS role_permissions (
  role_id bigint NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_id bigint NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS user_roles (
  user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id bigint NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, role_id)
);

-- ===============
-- Partners (Customers/Suppliers)
-- ===============

CREATE TABLE IF NOT EXISTS partners (
  id bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('customer','supplier','both')),
  name text NOT NULL,
  tax_id text,
  billing_address_id bigint REFERENCES addresses(id) ON DELETE SET NULL,
  shipping_address_id bigint REFERENCES addresses(id) ON DELETE SET NULL,
  phone text,
  email text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, name)
);

CREATE TABLE IF NOT EXISTS contacts (
  id bigserial PRIMARY KEY,
  partner_id bigint NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
  first_name text,
  last_name text,
  email text,
  phone text,
  position text
);

-- ===============
-- Products
-- ===============

CREATE TABLE IF NOT EXISTS product_categories (
  id bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name text NOT NULL,
  parent_id bigint REFERENCES product_categories(id) ON DELETE SET NULL,
  UNIQUE (company_id, name)
);

CREATE TABLE IF NOT EXISTS products (
  id bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  sku text NOT NULL,
  name text NOT NULL,
  category_id bigint REFERENCES product_categories(id) ON DELETE SET NULL,
  unit_code text NOT NULL REFERENCES units(code),
  tax_code_id bigint REFERENCES tax_codes(id) ON DELETE SET NULL,
  cost_price numeric(14,4) NOT NULL DEFAULT 0,
  sale_price numeric(14,4) NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, sku)
);

CREATE INDEX IF NOT EXISTS products_category_idx ON products(category_id);

-- ===============
-- Inventory
-- ===============

CREATE TABLE IF NOT EXISTS warehouses (
  id bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  code text NOT NULL,
  name text NOT NULL,
  address_id bigint REFERENCES addresses(id) ON DELETE SET NULL,
  UNIQUE (company_id, code)
);

CREATE TABLE IF NOT EXISTS stock_levels (
  product_id bigint NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  warehouse_id bigint NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
  quantity numeric(18,6) NOT NULL DEFAULT 0,
  PRIMARY KEY (product_id, warehouse_id)
);

CREATE TABLE IF NOT EXISTS stock_movements (
  id bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  product_id bigint NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  warehouse_id bigint NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
  qty_delta numeric(18,6) NOT NULL,
  movement_type text NOT NULL CHECK (movement_type IN ('IN','OUT','ADJUST')),
  reference_type text,
  reference_id bigint,
  moved_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS stock_movements_lookup_idx ON stock_movements(company_id, product_id, warehouse_id, moved_at);

-- ===============
-- Sales
-- ===============

CREATE TABLE IF NOT EXISTS sales_orders (
  id bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  order_no text NOT NULL,
  customer_id bigint NOT NULL REFERENCES partners(id) ON DELETE RESTRICT,
  order_date date NOT NULL DEFAULT (now()::date),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','confirmed','fulfilled','cancelled')),
  currency_code char(3) NOT NULL REFERENCES currencies(code),
  notes text,
  total_amount numeric(14,2) NOT NULL DEFAULT 0,
  UNIQUE (company_id, order_no)
);

CREATE TABLE IF NOT EXISTS sales_order_lines (
  id bigserial PRIMARY KEY,
  sales_order_id bigint NOT NULL REFERENCES sales_orders(id) ON DELETE CASCADE,
  line_no int NOT NULL,
  product_id bigint REFERENCES products(id) ON DELETE SET NULL,
  description text,
  quantity numeric(14,4) NOT NULL CHECK (quantity > 0),
  unit_price numeric(14,4) NOT NULL DEFAULT 0,
  tax_rate numeric(7,4) NOT NULL DEFAULT 0,
  line_total numeric(14,2) NOT NULL DEFAULT 0,
  UNIQUE (sales_order_id, line_no)
);

CREATE TABLE IF NOT EXISTS ar_invoices (
  id bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  invoice_no text NOT NULL,
  customer_id bigint NOT NULL REFERENCES partners(id) ON DELETE RESTRICT,
  invoice_date date NOT NULL DEFAULT (now()::date),
  due_date date,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted','paid','void')),
  currency_code char(3) NOT NULL REFERENCES currencies(code),
  notes text,
  total_amount numeric(14,2) NOT NULL DEFAULT 0,
  UNIQUE (company_id, invoice_no)
);

CREATE TABLE IF NOT EXISTS ar_invoice_lines (
  id bigserial PRIMARY KEY,
  invoice_id bigint NOT NULL REFERENCES ar_invoices(id) ON DELETE CASCADE,
  line_no int NOT NULL,
  product_id bigint REFERENCES products(id) ON DELETE SET NULL,
  description text,
  quantity numeric(14,4) NOT NULL CHECK (quantity > 0),
  unit_price numeric(14,4) NOT NULL DEFAULT 0,
  tax_rate numeric(7,4) NOT NULL DEFAULT 0,
  line_total numeric(14,2) NOT NULL DEFAULT 0,
  UNIQUE (invoice_id, line_no)
);

CREATE TABLE IF NOT EXISTS ar_payments (
  id bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  customer_id bigint NOT NULL REFERENCES partners(id) ON DELETE RESTRICT,
  payment_date date NOT NULL DEFAULT (now()::date),
  currency_code char(3) NOT NULL REFERENCES currencies(code),
  amount numeric(14,2) NOT NULL CHECK (amount >= 0),
  method text NOT NULL CHECK (method IN ('cash','bank','card','other')),
  reference text
);

CREATE TABLE IF NOT EXISTS ar_payment_applications (
  payment_id bigint NOT NULL REFERENCES ar_payments(id) ON DELETE CASCADE,
  invoice_id bigint NOT NULL REFERENCES ar_invoices(id) ON DELETE CASCADE,
  amount numeric(14,2) NOT NULL CHECK (amount >= 0),
  PRIMARY KEY (payment_id, invoice_id)
);

-- ===============
-- Purchasing
-- ===============

CREATE TABLE IF NOT EXISTS purchase_orders (
  id bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  po_no text NOT NULL,
  supplier_id bigint NOT NULL REFERENCES partners(id) ON DELETE RESTRICT,
  order_date date NOT NULL DEFAULT (now()::date),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','confirmed','received','cancelled')),
  currency_code char(3) NOT NULL REFERENCES currencies(code),
  notes text,
  total_amount numeric(14,2) NOT NULL DEFAULT 0,
  UNIQUE (company_id, po_no)
);

CREATE TABLE IF NOT EXISTS purchase_order_lines (
  id bigserial PRIMARY KEY,
  purchase_order_id bigint NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  line_no int NOT NULL,
  product_id bigint REFERENCES products(id) ON DELETE SET NULL,
  description text,
  quantity numeric(14,4) NOT NULL CHECK (quantity > 0),
  unit_price numeric(14,4) NOT NULL DEFAULT 0,
  tax_rate numeric(7,4) NOT NULL DEFAULT 0,
  line_total numeric(14,2) NOT NULL DEFAULT 0,
  UNIQUE (purchase_order_id, line_no)
);

CREATE TABLE IF NOT EXISTS ap_invoices (
  id bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  invoice_no text NOT NULL,
  supplier_id bigint NOT NULL REFERENCES partners(id) ON DELETE RESTRICT,
  invoice_date date NOT NULL DEFAULT (now()::date),
  due_date date,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted','paid','void')),
  currency_code char(3) NOT NULL REFERENCES currencies(code),
  notes text,
  total_amount numeric(14,2) NOT NULL DEFAULT 0,
  UNIQUE (company_id, invoice_no)
);

CREATE TABLE IF NOT EXISTS ap_invoice_lines (
  id bigserial PRIMARY KEY,
  invoice_id bigint NOT NULL REFERENCES ap_invoices(id) ON DELETE CASCADE,
  line_no int NOT NULL,
  product_id bigint REFERENCES products(id) ON DELETE SET NULL,
  description text,
  quantity numeric(14,4) NOT NULL CHECK (quantity > 0),
  unit_price numeric(14,4) NOT NULL DEFAULT 0,
  tax_rate numeric(7,4) NOT NULL DEFAULT 0,
  line_total numeric(14,2) NOT NULL DEFAULT 0,
  UNIQUE (invoice_id, line_no)
);

CREATE TABLE IF NOT EXISTS ap_payments (
  id bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  supplier_id bigint NOT NULL REFERENCES partners(id) ON DELETE RESTRICT,
  payment_date date NOT NULL DEFAULT (now()::date),
  currency_code char(3) NOT NULL REFERENCES currencies(code),
  amount numeric(14,2) NOT NULL CHECK (amount >= 0),
  method text NOT NULL CHECK (method IN ('cash','bank','card','other')),
  reference text
);

CREATE TABLE IF NOT EXISTS ap_payment_applications (
  payment_id bigint NOT NULL REFERENCES ap_payments(id) ON DELETE CASCADE,
  invoice_id bigint NOT NULL REFERENCES ap_invoices(id) ON DELETE CASCADE,
  amount numeric(14,2) NOT NULL CHECK (amount >= 0),
  PRIMARY KEY (payment_id, invoice_id)
);

-- ===============
-- Accounting
-- ===============

CREATE TABLE IF NOT EXISTS accounts (
  id bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  code text NOT NULL,
  name text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('asset','liability','equity','revenue','expense')),
  parent_id bigint REFERENCES accounts(id) ON DELETE SET NULL,
  is_active boolean NOT NULL DEFAULT true,
  UNIQUE (company_id, code)
);

CREATE TABLE IF NOT EXISTS journals (
  id bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  code text NOT NULL,
  name text NOT NULL,
  UNIQUE (company_id, code)
);

CREATE TABLE IF NOT EXISTS journal_entries (
  id bigserial PRIMARY KEY,
  company_id bigint NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  journal_id bigint NOT NULL REFERENCES journals(id) ON DELETE RESTRICT,
  journal_date date NOT NULL DEFAULT (now()::date),
  memo text,
  source_type text,
  source_id bigint,
  posted boolean NOT NULL DEFAULT false,
  posted_at timestamptz
);

CREATE TABLE IF NOT EXISTS journal_entry_lines (
  id bigserial PRIMARY KEY,
  entry_id bigint NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
  account_id bigint NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  partner_id bigint REFERENCES partners(id) ON DELETE SET NULL,
  product_id bigint REFERENCES products(id) ON DELETE SET NULL,
  warehouse_id bigint REFERENCES warehouses(id) ON DELETE SET NULL,
  description text,
  debit numeric(14,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
  credit numeric(14,2) NOT NULL DEFAULT 0 CHECK (credit >= 0)
);

CREATE INDEX IF NOT EXISTS jel_entry_idx ON journal_entry_lines(entry_id);
CREATE INDEX IF NOT EXISTS jel_account_idx ON journal_entry_lines(account_id);

-- Optional helper: ensure JE balances (debits == credits) per entry via a view or application logic

-- ===============
-- Housekeeping
-- ===============

-- Basic updated_at auto-update via triggers is application-specific. Keep DDL portable/minimal.

COMMIT;
