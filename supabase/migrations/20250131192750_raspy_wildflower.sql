-- Create staff records with fixed UUIDs for demo users
INSERT INTO staff (id, name, email, role, active) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Admin User', 'admin@example.com', 'admin', true),
  ('00000000-0000-0000-0000-000000000002', 'Manager User', 'manager@example.com', 'manager', true),
  ('00000000-0000-0000-0000-000000000003', 'Sales User', 'sales@example.com', 'sales', true)
ON CONFLICT (email) DO UPDATE SET
  name = EXCLUDED.name,
  role = EXCLUDED.role,
  active = EXCLUDED.active;
