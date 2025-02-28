-- Drop existing function
DROP FUNCTION IF EXISTS check_staff_availability(uuid, timestamptz, timestamptz);

-- Create improved staff availability check function
CREATE OR REPLACE FUNCTION check_staff_availability(
  p_staff_id uuid,
  p_date date,
  p_start_time time,
  p_end_time time
) RETURNS boolean AS $$
DECLARE
  v_conflicts integer;
BEGIN
  -- Check for overlapping video calls
  SELECT COUNT(*)
  INTO v_conflicts
  FROM video_calls
  WHERE staff_id = p_staff_id
    AND status = 'scheduled'
    AND date_trunc('day', scheduled_at) = p_date
    AND scheduled_at::time BETWEEN p_start_time AND p_end_time;

  -- Return false if video call conflicts found
  IF v_conflicts > 0 THEN
    RETURN false;
  END IF;

  -- Check time slots table if it exists
  IF EXISTS (
    SELECT 1 
    FROM information_schema.tables 
    WHERE table_name = 'time_slots'
  ) THEN
    SELECT COUNT(*)
    INTO v_conflicts
    FROM time_slots
    WHERE staff_id = p_staff_id
      AND NOT is_available
      AND date_trunc('day', start_time) = p_date
      AND start_time::time <= p_end_time
      AND end_time::time >= p_start_time;
          
    RETURN v_conflicts = 0;
  END IF;

  -- If time_slots table doesn't exist yet, just return true
  RETURN true;
END;
$$ LANGUAGE plpgsql;