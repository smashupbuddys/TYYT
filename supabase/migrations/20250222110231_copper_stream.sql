-- Drop existing trigger first
DROP TRIGGER IF EXISTS validate_video_call_trigger ON video_calls;

-- Drop existing function
DROP FUNCTION IF EXISTS validate_video_call();

-- Create improved video call validation function
CREATE OR REPLACE FUNCTION validate_video_call()
RETURNS TRIGGER AS $$
DECLARE
  v_customer_type text;
  v_notice_hours integer;
  v_settings jsonb;
BEGIN
  -- Get customer type and video call settings
  SELECT 
    c.type,
    cs.video_call_settings
  INTO 
    v_customer_type,
    v_settings
  FROM customers c
  CROSS JOIN company_settings cs
  WHERE c.id = NEW.customer_id;

  -- Get required notice hours based on customer type
  v_notice_hours := CASE v_customer_type
    WHEN 'retailer' THEN (v_settings->>'retail_notice_hours')::integer
    WHEN 'wholesaler' THEN (v_settings->>'wholesale_notice_hours')::integer
    ELSE 24 -- Default to 24 hours if not specified
  END;

  -- Check if video calls are allowed for this customer type
  IF v_customer_type = 'retailer' AND NOT (v_settings->>'allow_retail')::boolean THEN
    RAISE EXCEPTION 'Video calls are not enabled for retail customers';
  END IF;

  IF v_customer_type = 'wholesaler' AND NOT (v_settings->>'allow_wholesale')::boolean THEN
    RAISE EXCEPTION 'Video calls are not enabled for wholesale customers';
  END IF;

  -- Validate notice period
  IF NEW.scheduled_at <= (now() + (v_notice_hours || ' hours')::interval) THEN
    RAISE EXCEPTION 'Video calls must be scheduled at least % hours in advance for % customers',
      v_notice_hours,
      v_customer_type;
  END IF;

  -- Check if staff member has any overlapping calls
  IF EXISTS (
    SELECT 1
    FROM video_calls
    WHERE staff_id = NEW.staff_id
    AND id != NEW.id -- Exclude current call when updating
    AND status = 'scheduled'
    AND tstzrange(scheduled_at, scheduled_at + interval '30 minutes') &&
        tstzrange(NEW.scheduled_at, NEW.scheduled_at + interval '30 minutes')
  ) THEN
    RAISE EXCEPTION 'Selected staff member is not available at this time';
  END IF;

  -- Check if scheduled time is within business hours
  IF NOT EXISTS (
    SELECT 1 
    FROM video_call_rules
    WHERE day_of_week = EXTRACT(DOW FROM NEW.scheduled_at)
    AND is_working_day = true
    AND NEW.scheduled_at::time BETWEEN start_time AND end_time
  ) THEN
    RAISE EXCEPTION 'Video calls can only be scheduled during business hours';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for video call validation
CREATE TRIGGER validate_video_call_trigger
  BEFORE INSERT OR UPDATE OF scheduled_at, staff_id ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION validate_video_call();

-- Update existing video call rules to remove time restrictions
UPDATE video_call_rules
SET start_time = '10:00',
    end_time = '20:00'
WHERE true;

-- Add helpful comment
COMMENT ON FUNCTION validate_video_call IS 'Validates video call scheduling with flexible time slots and proper business rules';