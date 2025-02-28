-- Create function to get staff details
CREATE OR REPLACE FUNCTION get_staff_details(staff_id uuid)
RETURNS jsonb AS $$
DECLARE
  staff_details jsonb;
BEGIN
  SELECT jsonb_build_object(
    'primary', s.id,
    'staff_name', s.name,
    'staff_role', s.role,
    'backup', null,
    'history', jsonb_build_array(
      jsonb_build_object(
        'staff_id', s.id,
        'name', s.name,
        'role', s.role,
        'assigned_at', now(),
        'assigned_by', 'system'
      )
    )
  )
  INTO staff_details
  FROM staff s
  WHERE s.id = staff_id;

  RETURN staff_details;
END;
$$ LANGUAGE plpgsql;

-- Update existing video calls with proper assigned_staff data
UPDATE video_calls
SET assigned_staff = get_staff_details(staff_id)
WHERE staff_id IS NOT NULL 
  AND (assigned_staff IS NULL 
    OR assigned_staff->>'primary' IS NULL 
    OR assigned_staff->>'staff_name' IS NULL);

-- Create trigger to maintain assigned_staff consistency
CREATE OR REPLACE FUNCTION maintain_assigned_staff()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.staff_id IS NOT NULL AND (
    NEW.assigned_staff IS NULL OR 
    NEW.assigned_staff->>'primary' IS NULL OR 
    NEW.assigned_staff->>'staff_name' IS NULL
  ) THEN
    NEW.assigned_staff := get_staff_details(NEW.staff_id);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS maintain_assigned_staff_trigger ON video_calls;
CREATE TRIGGER maintain_assigned_staff_trigger
  BEFORE INSERT OR UPDATE OF staff_id ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION maintain_assigned_staff();