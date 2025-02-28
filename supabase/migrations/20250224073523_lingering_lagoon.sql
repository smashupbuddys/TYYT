-- Drop existing function if it exists
DROP FUNCTION IF EXISTS check_staff_availability(uuid, timestamptz, timestamptz);

-- Create improved staff availability check function
CREATE OR REPLACE FUNCTION check_staff_availability(
  p_staff_id uuid,
  p_start_time timestamptz,
  p_end_time timestamptz
)
RETURNS boolean AS $$
DECLARE
  v_conflicts integer;
BEGIN
  -- First check for overlapping video calls
  SELECT COUNT(*)
  INTO v_conflicts
  FROM video_calls
  WHERE staff_id = p_staff_id
    AND status = 'scheduled'
    AND tstzrange(scheduled_at, scheduled_at + interval '1 hour') &&  -- Default 1 hour duration
        tstzrange(p_start_time, p_end_time);

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
      AND tstzrange(start_time, end_time) &&
          tstzrange(p_start_time, p_end_time);
          
    RETURN v_conflicts = 0;
  END IF;

  -- If time_slots table doesn't exist yet, just return true
  RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Add helpful comment
COMMENT ON FUNCTION check_staff_availability IS 'Checks staff availability considering both video calls and time slots, with graceful handling of missing time_slots table';