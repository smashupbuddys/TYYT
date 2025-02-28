-- Add video call settings to company_settings if not exists
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'company_settings' AND column_name = 'video_call_settings'
  ) THEN
    -- Add video call settings column
    ALTER TABLE company_settings
      ADD COLUMN video_call_settings jsonb DEFAULT '{
        "allow_retail": true,
        "allow_wholesale": true,
        "retail_notice_hours": 24,
        "wholesale_notice_hours": 48,
        "max_duration": "1 hour",
        "buffer_before": "5 minutes",
        "buffer_after": "5 minutes",
        "business_hours": {
          "weekdays": {
            "start": "10:00",
            "end": "20:00"
          },
          "weekends": {
            "start": "10:00",
            "end": "18:00"
          }
        }
      }';
  END IF;
END $$;

-- Create function to validate video call scheduling based on settings
CREATE OR REPLACE FUNCTION validate_video_call_scheduling(
  p_customer_id uuid,
  p_scheduled_at timestamptz
)
RETURNS boolean AS $$
DECLARE
  v_customer_type text;
  v_settings jsonb;
  v_notice_hours integer;
  v_day_type text;
  v_start_time time;
  v_end_time time;
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
  WHERE c.id = p_customer_id;

  -- Check if video calls are enabled for this customer type
  IF v_customer_type = 'retailer' AND NOT (v_settings->>'allow_retail')::boolean THEN
    RAISE EXCEPTION 'Video calls are not enabled for retail customers';
  END IF;

  IF v_customer_type = 'wholesaler' AND NOT (v_settings->>'allow_wholesale')::boolean THEN
    RAISE EXCEPTION 'Video calls are not enabled for wholesale customers';
  END IF;

  -- Get required notice hours based on customer type
  v_notice_hours := CASE v_customer_type
    WHEN 'retailer' THEN (v_settings->>'retail_notice_hours')::integer
    WHEN 'wholesaler' THEN (v_settings->>'wholesale_notice_hours')::integer
    ELSE 24 -- Default to 24 hours if not specified
  END;

  -- Check notice period
  IF p_scheduled_at <= (now() + (v_notice_hours || ' hours')::interval) THEN
    RAISE EXCEPTION 'Video calls must be scheduled at least % hours in advance for % customers',
      v_notice_hours,
      v_customer_type;
  END IF;

  -- Determine if weekday or weekend
  v_day_type := CASE EXTRACT(DOW FROM p_scheduled_at)
    WHEN 0, 6 THEN 'weekends'
    ELSE 'weekdays'
  END;

  -- Get business hours for the day
  v_start_time := (v_settings->'business_hours'->v_day_type->>'start')::time;
  v_end_time := (v_settings->'business_hours'->v_day_type->>'end')::time;

  -- Check if within business hours
  IF p_scheduled_at::time < v_start_time OR p_scheduled_at::time > v_end_time THEN
    RAISE EXCEPTION 'Video calls can only be scheduled between % and % on %',
      v_start_time,
      v_end_time,
      CASE v_day_type
        WHEN 'weekdays' THEN 'weekdays'
        ELSE 'weekends'
      END;
  END IF;

  RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Update existing video call validation trigger
CREATE OR REPLACE FUNCTION validate_video_call()
RETURNS TRIGGER AS $$
BEGIN
  -- Validate scheduling based on settings
  PERFORM validate_video_call_scheduling(NEW.customer_id, NEW.scheduled_at);

  -- Check staff availability
  IF NOT check_staff_availability(
    NEW.staff_id,
    NEW.scheduled_at::date,
    NEW.scheduled_at::time,
    (NEW.scheduled_at + interval '1 hour')::time
  ) THEN
    RAISE EXCEPTION 'Selected staff member is not available at this time';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add helpful comments
COMMENT ON COLUMN company_settings.video_call_settings IS 'JSON object containing video call configuration including notice periods and business hours';
COMMENT ON FUNCTION validate_video_call_scheduling IS 'Validates video call scheduling based on customer type and company settings';