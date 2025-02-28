-- Drop existing triggers first
DROP TRIGGER IF EXISTS maintain_staff_assignment_trigger ON video_calls;
DROP TRIGGER IF EXISTS initialize_staff_assignment_trigger ON video_calls;

-- Create improved staff details function with better error handling
CREATE OR REPLACE FUNCTION get_staff_details_v2(staff_id uuid)
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

-- Create improved staff assignment function
CREATE OR REPLACE FUNCTION maintain_staff_assignment_v2()
RETURNS TRIGGER AS $$
DECLARE
  v_old_staff_id uuid;
  v_new_staff_id uuid;
  v_history jsonb;
  v_staff_details jsonb;
  current_user text;
BEGIN
  -- Get current user ID with fallback
  current_user := COALESCE(
    current_setting('app.current_user_id', true),
    'system'
  );

  -- Get old and new staff IDs
  v_old_staff_id := OLD.staff_id;
  v_new_staff_id := NEW.staff_id;

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

  -- Only proceed if staff assignment changed
  IF v_old_staff_id IS DISTINCT FROM v_new_staff_id THEN
    -- Get current history
    v_history := COALESCE(NEW.assigned_staff->'history', '[]'::jsonb);

    -- Get new staff details if assigned
    IF v_new_staff_id IS NOT NULL THEN
      SELECT jsonb_build_object(
        'staff_id', s.id,
        'name', s.name,
        'role', s.role,
        'assigned_at', now(),
        'assigned_by', current_user
      )
      INTO v_staff_details
      FROM staff s
      WHERE s.id = v_new_staff_id AND s.active = true;

      IF v_staff_details IS NOT NULL THEN
        NEW.assigned_staff := jsonb_build_object(
          'primary', v_new_staff_id,
          'staff_name', v_staff_details->>'name',
          'staff_role', v_staff_details->>'role',
          'backup', null,
          'history', v_history || v_staff_details
        );
      ELSE
        -- Staff not found or inactive - reset to unassigned
        NEW.staff_id := null;
        NEW.assigned_staff := jsonb_build_object(
          'primary', null,
          'staff_name', 'Unassigned',
          'staff_role', null,
          'backup', null,
          'history', v_history
        );
      END IF;
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

-- Create triggers with improved error handling
CREATE TRIGGER maintain_staff_assignment_trigger
  BEFORE UPDATE OF staff_id ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION maintain_staff_assignment_v2();

CREATE TRIGGER initialize_staff_assignment_trigger
  BEFORE INSERT ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION maintain_staff_assignment_v2();

-- Fix any inconsistent data
WITH staff_updates AS (
  SELECT 
    vc.id as video_call_id,
    vc.staff_id,
    s.name as staff_name,
    s.role as staff_role
  FROM video_calls vc
  LEFT JOIN staff s ON s.id = vc.staff_id
  WHERE (
    vc.staff_id IS NOT NULL AND (
      vc.assigned_staff IS NULL OR
      vc.assigned_staff->>'staff_name' = 'Unassigned' OR
      vc.assigned_staff->>'primary' IS NULL
    )
  ) OR (
    vc.staff_id IS NULL AND (
      vc.assigned_staff IS NULL OR
      vc.assigned_staff->>'staff_name' != 'Unassigned'
    )
  )
)
UPDATE video_calls vc
SET assigned_staff = get_staff_details_v2(su.staff_id)
FROM staff_updates su
WHERE vc.id = su.video_call_id;