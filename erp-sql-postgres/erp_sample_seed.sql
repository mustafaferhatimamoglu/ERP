-- Minimal sample data to make the schema usable for demos
BEGIN;
SET search_path TO erp, public;

-- Currencies
INSERT INTO currencies (code, name, symbol, decimals) VALUES
  ('USD','US Dollar','$',2),
  ('EUR','Euro','€',2)
ON CONFLICT (code) DO NOTHING;

-- Units
INSERT INTO units (code, name) VALUES
  ('EA','Each'),
  ('KG','Kilogram')
ON CONFLICT (code) DO NOTHING;

-- Company
INSERT INTO addresses (line1, city, state, postal_code, country_code)
VALUES ('1 Main Street','Metropolis','NY','10001','US');

-- Insert company with default USD currency
INSERT INTO companies (name, legal_name, default_currency, address_id)
SELECT 'Acme Inc.', 'Acme Incorporated', 'USD', a.id
FROM addresses a
WHERE a.line1 = '1 Main Street' AND a.city = 'Metropolis'
  AND NOT EXISTS (
    SELECT 1 FROM companies c WHERE c.name = 'Acme Inc.'
  );

-- Basic tax codes (company-scoped)
INSERT INTO tax_codes (company_id, code, name, rate, kind)
SELECT c.id, 'VAT20', 'VAT 20%', 0.20, 'VAT' FROM companies c WHERE c.name='Acme Inc.'
ON CONFLICT DO NOTHING;

-- Roles and permissions
INSERT INTO permissions (code, description) VALUES
  ('admin','Full access'),
  ('sales.manage','Manage sales'),
  ('purchasing.manage','Manage purchasing'),
  ('inventory.manage','Manage inventory'),
  ('accounting.manage','Manage accounting')
ON CONFLICT (code) DO NOTHING;

INSERT INTO roles (company_id, name)
SELECT id, 'Admin' FROM companies WHERE name='Acme Inc.'
ON CONFLICT DO NOTHING;

-- Map admin role to all permissions
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
JOIN companies c ON c.id = r.company_id AND c.name='Acme Inc.'
JOIN permissions p ON true
WHERE r.name='Admin'
ON CONFLICT DO NOTHING;

-- Create an admin user (set a real hash in application)
INSERT INTO users (company_id, email, password_hash, first_name, last_name)
SELECT c.id, 'admin@example.com', '{set-a-real-hash}', 'System', 'Admin'
FROM companies c WHERE c.name='Acme Inc.'
ON CONFLICT (email) DO NOTHING;

-- Assign Admin role to the admin user
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id
FROM users u
JOIN roles r ON r.company_id = u.company_id AND r.name='Admin'
WHERE u.email='admin@example.com'
ON CONFLICT DO NOTHING;

-- Partners (customer & supplier)
INSERT INTO partners (company_id, kind, name, email)
SELECT c.id, 'customer', 'Wayne Enterprises', 'ap@wayne.example'
FROM companies c WHERE c.name='Acme Inc.'
ON CONFLICT DO NOTHING;

INSERT INTO partners (company_id, kind, name, email)
SELECT c.id, 'supplier', 'Stark Industries', 'ar@stark.example'
FROM companies c WHERE c.name='Acme Inc.'
ON CONFLICT DO NOTHING;

-- Warehouse
INSERT INTO warehouses (company_id, code, name)
SELECT c.id, 'MAIN', 'Main Warehouse'
FROM companies c WHERE c.name='Acme Inc.'
ON CONFLICT DO NOTHING;

-- Product category and product
INSERT INTO product_categories (company_id, name)
SELECT c.id, 'Default'
FROM companies c WHERE c.name='Acme Inc.'
ON CONFLICT DO NOTHING;

INSERT INTO products (company_id, sku, name, category_id, unit_code, sale_price, cost_price)
SELECT c.id, 'WIDGET-001', 'Standard Widget', pc.id, 'EA', 25.00, 10.00
FROM companies c
JOIN product_categories pc ON pc.company_id = c.id AND pc.name='Default'
WHERE c.name='Acme Inc.'
ON CONFLICT DO NOTHING;

-- Seed stock level
INSERT INTO stock_levels (product_id, warehouse_id, quantity)
SELECT p.id, w.id, 100
FROM products p
JOIN companies c ON c.id = p.company_id AND c.name='Acme Inc.'
JOIN warehouses w ON w.company_id = c.id AND w.code='MAIN'
WHERE p.sku='WIDGET-001'
ON CONFLICT (product_id, warehouse_id) DO NOTHING;

-- Example sales order and invoice
INSERT INTO sales_orders (company_id, order_no, customer_id, currency_code, total_amount)
SELECT c.id, 'SO-0001', cust.id, c.default_currency, 300.00
FROM companies c
JOIN partners cust ON cust.company_id=c.id AND cust.name='Wayne Enterprises'
WHERE c.name='Acme Inc.'
ON CONFLICT DO NOTHING;

INSERT INTO sales_order_lines (sales_order_id, line_no, product_id, description, quantity, unit_price, tax_rate, line_total)
SELECT so.id, 1, p.id, p.name, 10, 25.00, 0.20, 300.00
FROM sales_orders so
JOIN companies c ON c.id = so.company_id AND c.name='Acme Inc.'
JOIN products p ON p.company_id=c.id AND p.sku='WIDGET-001'
WHERE so.order_no='SO-0001'
ON CONFLICT DO NOTHING;

INSERT INTO ar_invoices (company_id, invoice_no, customer_id, currency_code, total_amount, status)
SELECT c.id, 'INV-0001', cust.id, c.default_currency, 300.00, 'posted'
FROM companies c
JOIN partners cust ON cust.company_id=c.id AND cust.name='Wayne Enterprises'
WHERE c.name='Acme Inc.'
ON CONFLICT DO NOTHING;

INSERT INTO ar_invoice_lines (invoice_id, line_no, product_id, description, quantity, unit_price, tax_rate, line_total)
SELECT inv.id, 1, p.id, p.name, 10, 25.00, 0.20, 300.00
FROM ar_invoices inv
JOIN companies c ON c.id = inv.company_id AND c.name='Acme Inc.'
JOIN products p ON p.company_id=c.id AND p.sku='WIDGET-001'
WHERE inv.invoice_no='INV-0001'
ON CONFLICT DO NOTHING;

COMMIT;
