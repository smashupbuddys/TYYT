/*
  # Set up demo users and staff

  1. Demo Data
    - Create staff members with default credentials
*/

-- Create staff records directly
INSERT INTO staff (id, name, email, role, active) VALUES
  (gen_random_uuid(), 'Admin User', 'admin@example.com', 'admin', true),
  (gen_random_uuid(), 'Manager User', 'manager@example.com', 'manager', true),
  (gen_random_uuid(), 'Sales User', 'sales@example.com', 'sales', true)
ON CONFLICT (email) DO NOTHING;
