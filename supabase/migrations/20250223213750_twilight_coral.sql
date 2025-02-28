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
        'assigned_by', current_setting('app.current_user_id', true)
      )
    )
  )
  INTO staff_details
  FROM staff s
  WHERE s.id = staff_id;

  RETURN COALESCE(staff_details, jsonb_build_object(
    'primary', null,
    'staff_name', 'Unassigned',
    'staff_role', null,
    'backup', null,
    'history', '[]'::jsonb
  ));
END;
$$ LANGUAGE plpgsql;

-- Create function to maintain staff assignment history
CREATE OR REPLACE FUNCTION maintain_staff_assignment()
RETURNS TRIGGER AS $$
DECLARE
  v_old_staff_id uuid;
  v_new_staff_id uuid;
  v_history jsonb;
BEGIN
  -- Get old and new staff IDs
  v_old_staff_id := OLD.staff_id;
  v_new_staff_id := NEW.staff_id;

  -- Only proceed if staff assignment changed
  IF v_old_staff_id IS DISTINCT FROM v_new_staff_id THEN
    -- Get current history or initialize empty array
    v_history := COALESCE(NEW.assigned_staff->'history', '[]'::jsonb);

    -- Add new assignment to history
    IF v_new_staff_id IS NOT NULL THEN
      SELECT jsonb_build_object(
        'primary', s.id,
        'staff_name', s.name,
        'staff_role', s.role,
        'backup', null,
        'history', v_history || jsonb_build_object(
          'staff_id', s.id,
          'name', s.name,
          'role', s.role,
          'assigned_at', now(),
          'assigned_by', current_setting('app.current_user_id', true)
        )
      )
      INTO NEW.assigned_staff
      FROM staff s
      WHERE s.id = v_new_staff_id;
    ELSE
      -- Reset to unassigned state but preserve history
      NEW.assigned_staff := jsonb_build_object(
        'primary', null,
        'staff_name', 'Unassigned',
        'staff_role', null,
        'backup', null,
        'history', v_history
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for staff assignment maintenance
DROP TRIGGER IF EXISTS maintain_staff_assignment_trigger ON video_calls;
CREATE TRIGGER maintain_staff_assignment_trigger
  BEFORE UPDATE OF staff_id ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION maintain_staff_assignment();

-- Create trigger for new video calls
CREATE TRIGGER initialize_staff_assignment_trigger
  BEFORE INSERT ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION maintain_staff_assignment();

-- Update existing records with proper staff details
UPDATE video_calls
SET assigned_staff = get_staff_details(staff_id)
WHERE staff_id IS NOT NULL;