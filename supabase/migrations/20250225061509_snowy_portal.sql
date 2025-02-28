-- Drop existing function
DROP FUNCTION IF EXISTS validate_video_call_scheduling(uuid, timestamptz);

-- Create improved video call validation function
CREATE OR REPLACE FUNCTION validate_video_call_scheduling(
  p_customer_id uuid,
  p_scheduled_at timestamptz,
  p_is_staff_update boolean DEFAULT false -- New parameter to skip notice period check
)
RETURNS boolean AS $$
DECLARE
  v_customer_type text;
  v_settings jsonb;
  v_notice_hours integer;
  v_day_type text;
  v_start_time time;
  v_end_time time;
  v_now timestamptz;
BEGIN
  -- Get current time in UTC
  v_now := now();

  -- Get customer type and video call settings
  SELECT 
    c.type,
    cs.video_call_settings
  INTO 
    v_customer_type,
    v_settings
  FROM customers c
  CROSS JOIN company_settings cs
  WHERE c.id = p_customer_id;

  -- Check if customer exists
  IF v_customer_type IS NULL THEN
    RAISE EXCEPTION 'Customer not found';
  END IF;

  -- Skip notice period check for staff updates
  IF NOT p_is_staff_update THEN
    -- Check if video calls are enabled for this customer type
    IF v_customer_type = 'retailer' AND NOT (v_settings->>'allow_retail')::boolean THEN
      RAISE EXCEPTION 'Video calls are not enabled for retail customers';
    END IF;

    IF v_customer_type = 'wholesaler' AND NOT (v_settings->>'allow_wholesale')::boolean THEN
      RAISE EXCEPTION 'Video calls are not enabled for wholesale customers';
    END IF;

    -- Get required notice hours based on customer type with fallback values
    v_notice_hours := CASE v_customer_type
      WHEN 'retailer' THEN COALESCE((v_settings->>'retail_notice_hours')::integer, 24)
      WHEN 'wholesaler' THEN COALESCE((v_settings->>'wholesale_notice_hours')::integer, 48)
      ELSE 24 -- Default to 24 hours if not specified
    END;

    -- Check notice period with proper error message
    IF p_scheduled_at <= (v_now + (v_notice_hours || ' hours')::interval) THEN
      RAISE EXCEPTION 'Video calls must be scheduled at least % hours in advance for % customers',
        v_notice_hours,
        v_customer_type;
    END IF;

    -- Determine if weekday or weekend
    v_day_type := CASE EXTRACT(DOW FROM p_scheduled_at)
      WHEN 0, 6 THEN 'weekends'
      ELSE 'weekdays'
    END;

    -- Get business hours for the day with fallback values
    v_start_time := COALESCE(
      (v_settings->'business_hours'->v_day_type->>'start')::time,
      '10:00'::time
    );
    v_end_time := COALESCE(
      (v_settings->'business_hours'->v_day_type->>'end')::time,
      CASE v_day_type
        WHEN 'weekends' THEN '18:00'::time
        ELSE '20:00'::time
      END
    );

    -- Check if within business hours
    IF p_scheduled_at::time < v_start_time OR p_scheduled_at::time > v_end_time THEN
      RAISE EXCEPTION 'Video calls can only be scheduled between % and % on %',
        to_char(v_start_time, 'HH12:MI AM'),
        to_char(v_end_time, 'HH12:MI AM'),
        CASE v_day_type
          WHEN 'weekdays' THEN 'weekdays'
          ELSE 'weekends'
        END;
    END IF;
  END IF;

  RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Create trigger function to handle different update scenarios
CREATE OR REPLACE FUNCTION handle_video_call_updates()
RETURNS TRIGGER AS $$
BEGIN
  -- Check if only staff_id is being updated
  IF (TG_OP = 'UPDATE' AND 
      NEW.scheduled_at = OLD.scheduled_at AND 
      NEW.staff_id IS DISTINCT FROM OLD.staff_id) THEN
    -- Skip notice period validation for staff updates
    PERFORM validate_video_call_scheduling(NEW.customer_id, NEW.scheduled_at, true);
  ELSE
    -- Full validation for other updates
    PERFORM validate_video_call_scheduling(NEW.customer_id, NEW.scheduled_at, false);
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger
DROP TRIGGER IF EXISTS validate_video_call_trigger ON video_calls;

-- Create new trigger with improved handling
CREATE TRIGGER validate_video_call_trigger
  BEFORE INSERT OR UPDATE ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION handle_video_call_updates();

-- Add helpful comment
COMMENT ON FUNCTION validate_video_call_scheduling IS 'Validates video call scheduling with proper notice periods and business hours, with option to skip notice period check for staff updates';