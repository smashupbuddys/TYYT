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

-- Create function to get staff details for video calls
CREATE OR REPLACE FUNCTION get_video_call_staff(video_call_id uuid)
RETURNS jsonb AS $$
DECLARE
  staff_details jsonb;
BEGIN
  SELECT jsonb_build_object(
    'id', s.id,
    'name', s.name,
    'role', s.role,
    'email', s.email
  ) INTO staff_details
  FROM video_calls vc
  JOIN staff s ON s.id = vc.staff_id
  WHERE vc.id = video_call_id;

  RETURN staff_details;
END;
$$ LANGUAGE plpgsql;

-- Create function to check upcoming video calls
CREATE OR REPLACE FUNCTION check_upcoming_video_calls(
  minutes_ahead integer DEFAULT 5
)
RETURNS TABLE (
  id uuid,
  video_call_number text,
  scheduled_at timestamptz,
  customer_name text,
  customer_phone text,
  staff_name text,
  staff_id uuid
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    vc.id,
    vc.video_call_number,
    vc.scheduled_at,
    c.name as customer_name,
    c.phone as customer_phone,
    s.name as staff_name,
    s.id as staff_id
  FROM video_calls vc
  JOIN customers c ON c.id = vc.customer_id
  JOIN staff s ON s.id = vc.staff_id
  WHERE vc.status = 'scheduled'
  AND vc.scheduled_at BETWEEN now() AND (now() + (minutes_ahead || ' minutes')::interval);
END;
$$ LANGUAGE plpgsql;