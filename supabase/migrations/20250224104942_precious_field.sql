-- Update company settings with correct notice periods
UPDATE company_settings
SET video_call_settings = jsonb_build_object(
  'allow_retail', true,
  'allow_wholesale', true,
  'retail_notice_hours', 24,
  'wholesale_notice_hours', 48,
  'max_duration', '1 hour',
  'buffer_before', '5 minutes',
  'buffer_after', '5 minutes',
  'business_hours', jsonb_build_object(
    'weekdays', jsonb_build_object(
      'start', '10:00',
      'end', '20:00'
    ),
    'weekends', jsonb_build_object(
      'start', '10:00',
      'end', '18:00'
    )
  )
)
WHERE settings_key = 1;

-- Create function to format notice period message
CREATE OR REPLACE FUNCTION format_notice_period_message(
  p_notice_hours integer,
  p_customer_type text
)
RETURNS text AS $$
BEGIN
  RETURN format(
    'Video calls must be scheduled at least %s in advance for %s customers. Please select a time after %s',
    CASE
      WHEN p_notice_hours >= 24 THEN (p_notice_hours / 24) || ' days'
      ELSE p_notice_hours || ' hours'
    END,
    p_customer_type,
    to_char(now() + (p_notice_hours || ' hours')::interval, 'Mon DD, YYYY, HH12:MI AM')
  );
END;
$$ LANGUAGE plpgsql;

-- Update validation function to use formatted message
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

  -- Check notice period with formatted message
  IF p_scheduled_at <= (now() + (v_notice_hours || ' hours')::interval) THEN
    RAISE EXCEPTION '%',
      format_notice_period_message(v_notice_hours, v_customer_type);
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