-- Create function to get staff details with better error handling
CREATE OR REPLACE FUNCTION get_staff_details_v3(staff_id uuid)
RETURNS jsonb AS $$
DECLARE
  staff_details jsonb;
  current_user text;
BEGIN
  -- Get current user ID with fallback
  current_user := COALESCE(
    current_setting('app.current_user_id', true),
    'system'
  );

  -- Get staff details with error handling
  BEGIN
    SELECT jsonb_build_object(
      'primary', s.id,
      'staff_name', s.name,
      'staff_role', s.role,
      'backup', null,
      'history', COALESCE(
        jsonb_build_array(
          jsonb_build_object(
            'staff_id', s.id,
            'name', s.name,
            'role', s.role,
            'assigned_at', now(),
            'assigned_by', current_user
          )
        ),
        '[]'::jsonb
      )
    )
    INTO staff_details
    FROM staff s
    WHERE s.id = staff_id AND s.active = true;

    -- Return unassigned if staff not found or inactive
    IF staff_details IS NULL THEN
      RETURN jsonb_build_object(
        'primary', null,
        'staff_name', 'Unassigned',
        'staff_role', null,
        'backup', null,
        'history', '[]'::jsonb
      );
    END IF;

    RETURN staff_details;
  EXCEPTION WHEN OTHERS THEN
    -- Log error and return unassigned state
    RAISE NOTICE 'Error getting staff details: %', SQLERRM;
    RETURN jsonb_build_object(
      'primary', null,
      'staff_name', 'Unassigned',
      'staff_role', null,
      'backup', null,
      'history', '[]'::jsonb
    );
  END;
END;
$$ LANGUAGE plpgsql;

-- Create function to maintain staff assignment
CREATE OR REPLACE FUNCTION maintain_staff_assignment_v3()
RETURNS TRIGGER AS $$
DECLARE
  v_staff_details jsonb;
  current_user text;
BEGIN
  -- Get current user ID with fallback
  current_user := COALESCE(
    current_setting('app.current_user_id', true),
    'system'
  );

  -- Initialize assigned_staff if NULL
  IF NEW.assigned_staff IS NULL THEN
    NEW.assigned_staff := jsonb_build_object(
      'primary', null,
      'staff_name', 'Unassigned',
      'staff_role', null,
      'backup', null,
      'history', '[]'::jsonb
    );
  END IF;

  -- Only proceed if staff_id is set and different from current
  IF NEW.staff_id IS NOT NULL AND (
    NEW.assigned_staff->>'primary' IS NULL OR 
    (NEW.assigned_staff->>'primary')::uuid != NEW.staff_id
  ) THEN
    -- Get staff details
    SELECT jsonb_build_object(
      'staff_id', s.id,
      'name', s.name,
      'role', s.role,
      'assigned_at', now(),
      'assigned_by', current_user
    )
    INTO v_staff_details
    FROM staff s
    WHERE s.id = NEW.staff_id AND s.active = true;

    IF v_staff_details IS NOT NULL THEN
      NEW.assigned_staff := jsonb_build_object(
        'primary', NEW.staff_id,
        'staff_name', v_staff_details->>'name',
        'staff_role', v_staff_details->>'role',
        'backup', null,
        'history', COALESCE(NEW.assigned_staff->'history', '[]'::jsonb) || v_staff_details
      );
    ELSE
      -- Staff not found or inactive - reset to unassigned
      NEW.staff_id := null;
      NEW.assigned_staff := jsonb_build_object(
        'primary', null,
        'staff_name', 'Unassigned',
        'staff_role', null,
        'backup', null,
        'history', COALESCE(NEW.assigned_staff->'history', '[]'::jsonb)
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing triggers
DROP TRIGGER IF EXISTS maintain_staff_assignment_trigger ON video_calls;
DROP TRIGGER IF EXISTS initialize_staff_assignment_trigger ON video_calls;

-- Create new triggers
CREATE TRIGGER maintain_staff_assignment_trigger
  BEFORE INSERT OR UPDATE OF staff_id ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION maintain_staff_assignment_v3();

-- Fix existing unassigned staff
UPDATE video_calls
SET assigned_staff = get_staff_details_v3(staff_id)
WHERE staff_id IS NOT NULL AND (
  assigned_staff IS NULL OR
  assigned_staff->>'primary' IS NULL OR
  assigned_staff->>'staff_name' IS NULL OR
  assigned_staff->>'staff_name' = 'Unassigned'
);

-- Add helpful comment
COMMENT ON FUNCTION maintain_staff_assignment_v3 IS 'Maintains consistent staff assignment data with proper error handling and history tracking';