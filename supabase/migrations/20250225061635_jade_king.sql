-- Drop existing trigger and functions
DROP TRIGGER IF EXISTS validate_video_call_trigger ON video_calls;
DROP FUNCTION IF EXISTS handle_video_call_updates();
DROP FUNCTION IF EXISTS validate_video_call_scheduling(uuid, timestamptz, boolean);

-- Create improved video call validation function
CREATE OR REPLACE FUNCTION validate_video_call_scheduling(
  p_customer_id uuid,
  p_scheduled_at timestamptz,
  p_is_staff_update boolean DEFAULT false,
  p_old_staff_id uuid DEFAULT NULL,
  p_new_staff_id uuid DEFAULT NULL
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

  -- For staff updates, only check staff availability
  IF p_is_staff_update THEN
    -- Check staff availability
    IF NOT check_staff_availability(
      p_new_staff_id,
      p_scheduled_at::date,
      p_scheduled_at::time,
      (p_scheduled_at + interval '1 hour')::time
    ) THEN
      RAISE EXCEPTION 'Selected staff member is not available at this time';
    END IF;
    RETURN true;
  END IF;

  -- Regular validation for new calls or rescheduling
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

  RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Create trigger function to handle different update scenarios
CREATE OR REPLACE FUNCTION handle_video_call_updates()
RETURNS TRIGGER AS $$
BEGIN
  -- Determine if this is just a staff update
  IF (TG_OP = 'UPDATE' AND 
      NEW.scheduled_at = OLD.scheduled_at AND 
      NEW.staff_id IS DISTINCT FROM OLD.staff_id) THEN
    -- Only validate staff availability
    PERFORM validate_video_call_scheduling(
      NEW.customer_id, 
      NEW.scheduled_at, 
      true,
      OLD.staff_id,
      NEW.staff_id
    );
  ELSE
    -- Full validation for new calls or rescheduling
    PERFORM validate_video_call_scheduling(
      NEW.customer_id,
      NEW.scheduled_at,
      false,
      NULL,
      NEW.staff_id
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create new trigger with improved handling
CREATE TRIGGER validate_video_call_trigger
  BEFORE INSERT OR UPDATE ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION handle_video_call_updates();

-- Add helpful comment
COMMENT ON FUNCTION validate_video_call_scheduling IS 'Validates video call scheduling with proper notice periods and business hours, with special handling for staff updates';