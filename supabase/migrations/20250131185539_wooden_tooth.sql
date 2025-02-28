/*
  # Add Staff Management Tables

  1. New Tables
    - `staff`
      - Basic staff information
      - Role-based access control
      - Activity tracking

  2. Security
    - Enable RLS
    - Add policies for public access (temporary for development)

  3. Sample Data
    - Add initial staff members for testing
*/

-- Create staff table
CREATE TABLE IF NOT EXISTS staff (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text UNIQUE NOT NULL,
  role text NOT NULL CHECK (role IN ('admin', 'manager', 'sales', 'qc', 'packaging', 'dispatch')),
  active boolean DEFAULT true,
  last_active timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE staff ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on staff"
  ON staff FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on staff"
  ON staff FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on staff"
  ON staff FOR UPDATE TO public USING (true) WITH CHECK (true);

-- Insert sample staff data
INSERT INTO staff (name, email, role) VALUES
  ('John Smith', 'john@example.com', 'admin'),
  ('Sarah Johnson', 'sarah@example.com', 'manager'),
  ('Mike Brown', 'mike@example.com', 'sales'),
  ('Lisa Davis', 'lisa@example.com', 'qc'),
  ('David Wilson', 'david@example.com', 'packaging'),
  ('Emma Taylor', 'emma@example.com', 'dispatch');

-- Create staff_activity_log table
CREATE TABLE IF NOT EXISTS staff_activity_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid REFERENCES staff(id),
  action text NOT NULL,
  details jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE staff_activity_log ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on staff_activity_log"
  ON staff_activity_log FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on staff_activity_log"
  ON staff_activity_log FOR INSERT TO public WITH CHECK (true);

-- Create function to log staff activity
CREATE OR REPLACE FUNCTION log_staff_activity()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO staff_activity_log (staff_id, action, details)
  VALUES (
    NEW.staff_id,
    TG_ARGV[0],
    jsonb_build_object(
      'video_call_id', NEW.video_call_id,
      'role', NEW.role,
      'status', NEW.status
    )
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for workflow assignments
DROP TRIGGER IF EXISTS log_workflow_assignment ON workflow_assignments;

CREATE TRIGGER log_workflow_assignment
  AFTER INSERT OR UPDATE ON workflow_assignments
  FOR EACH ROW
  EXECUTE FUNCTION log_staff_activity('workflow_assignment');
