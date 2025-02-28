-- First ensure staff table exists and has required fields
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

-- Drop existing foreign key if it exists
DO $$ 
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'video_calls_staff_id_fkey'
  ) THEN
    ALTER TABLE video_calls DROP CONSTRAINT video_calls_staff_id_fkey;
  END IF;
END $$;

-- Add foreign key constraint to staff table
ALTER TABLE video_calls
  ADD CONSTRAINT video_calls_staff_id_fkey 
  FOREIGN KEY (staff_id) 
  REFERENCES staff(id)
  ON DELETE SET NULL;

-- Add index for better join performance
CREATE INDEX IF NOT EXISTS idx_video_calls_staff_id ON video_calls(staff_id);

-- Enable RLS on staff table
ALTER TABLE staff ENABLE ROW LEVEL SECURITY;

-- Create policies with existence checks
DO $$ 
BEGIN
  -- Drop existing policies if they exist
  DROP POLICY IF EXISTS "Allow public read access on staff" ON staff;
  DROP POLICY IF EXISTS "Allow public insert access on staff" ON staff;
  DROP POLICY IF EXISTS "Allow public update access on staff" ON staff;

  -- Create new policies
  CREATE POLICY "Allow public read access on staff"
    ON staff FOR SELECT TO public USING (true);

  CREATE POLICY "Allow public insert access on staff"
    ON staff FOR INSERT TO public WITH CHECK (true);

  CREATE POLICY "Allow public update access on staff"
    ON staff FOR UPDATE TO public USING (true);
END $$;

-- Insert demo staff if they don't exist
INSERT INTO staff (id, name, email, role) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Admin User', 'admin@example.com', 'admin'),
  ('00000000-0000-0000-0000-000000000002', 'Manager User', 'manager@example.com', 'manager'),
  ('00000000-0000-0000-0000-000000000003', 'Sales User', 'sales@example.com', 'sales')
ON CONFLICT (email) DO UPDATE
SET name = EXCLUDED.name,
    role = EXCLUDED.role,
    active = true;

-- Add helpful comments
COMMENT ON TABLE staff IS 'Stores staff member information';
COMMENT ON CONSTRAINT video_calls_staff_id_fkey ON video_calls IS 'Links video calls to assigned staff members';