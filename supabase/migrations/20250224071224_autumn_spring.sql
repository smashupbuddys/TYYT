-- Drop existing scheduling functions
DROP FUNCTION IF EXISTS schedule_video_call(uuid, uuid, timestamptz, interval, text);

-- Create improved video call scheduling function
CREATE OR REPLACE FUNCTION schedule_video_call(
  p_customer_id uuid,
  p_staff_id uuid,
  p_scheduled_at timestamptz,
  p_duration text,
  p_customer_timezone text
)
RETURNS uuid AS $$
DECLARE
  v_video_call_id uuid;
  v_duration_interval interval;
  v_end_time timestamptz;
  v_customer_type text;
  v_settings jsonb;
BEGIN
  -- Convert duration string to interval
  v_duration_interval := p_duration::interval;
  
  -- Calculate end time
  v_end_time := p_scheduled_at + v_duration_interval;

  -- Check if slot is available
  IF NOT check_slot_availability(p_staff_id, p_scheduled_at, v_end_time) THEN
    RAISE EXCEPTION 'Selected time slot is not available';
  END IF;

  -- Get customer type and settings
  SELECT c.type, cs.video_call_settings
  INTO v_customer_type, v_settings
  FROM customers c
  CROSS JOIN company_settings cs
  WHERE c.id = p_customer_id;

  -- Create video call
  INSERT INTO video_calls (
    customer_id,
    staff_id,
    scheduled_at,
    status,
    time_zone,
    customer_time_zone,
    workflow_status,
    assigned_staff
  ) VALUES (
    p_customer_id,
    p_staff_id,
    p_scheduled_at,
    'scheduled',
    'UTC',
    p_customer_timezone,
    jsonb_build_object(
      'video_call', 'pending',
      'quotation', 'pending',
      'profiling', 'pending',
      'payment', 'pending',
      'qc', 'pending',
      'packaging', 'pending',
      'dispatch', 'pending'
    ),
    get_staff_details_v3(p_staff_id)
  )
  RETURNING id INTO v_video_call_id;

  -- Create unavailable time slot
  INSERT INTO time_slots (
    staff_id,
    start_time,
    end_time,
    is_available,
    buffer_before,
    buffer_after
  ) VALUES (
    p_staff_id,
    p_scheduled_at,
    v_end_time,
    false,
    interval '5 minutes',
    interval '5 minutes'
  );

  -- Create notification for staff
  INSERT INTO notifications (
    user_id,
    type,
    title,
    message,
    data
  ) VALUES (
    p_staff_id,
    'video_call_scheduled',
    'New Video Call Scheduled',
    format(
      'You have a video call scheduled with %s on %s',
      (SELECT name FROM customers WHERE id = p_customer_id),
      to_char(p_scheduled_at AT TIME ZONE COALESCE(p_customer_timezone, 'UTC'), 'DD Mon YYYY HH24:MI')
    ),
    jsonb_build_object(
      'video_call_id', v_video_call_id,
      'scheduled_at', p_scheduled_at,
      'duration', v_duration_interval,
      'customer_timezone', p_customer_timezone
    )
  );

  RETURN v_video_call_id;
END;
$$ LANGUAGE plpgsql;