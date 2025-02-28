-- Create table for time slots
CREATE TABLE IF NOT EXISTS time_slots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid REFERENCES staff(id) ON DELETE CASCADE,
  start_time timestamptz NOT NULL,
  end_time timestamptz NOT NULL,
  buffer_before interval DEFAULT '5 minutes',
  buffer_after interval DEFAULT '5 minutes',
  is_available boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE time_slots ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on time_slots"
  ON time_slots FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on time_slots"
  ON time_slots FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on time_slots"
  ON time_slots FOR UPDATE TO public USING (true);

-- Create function to check slot availability
CREATE OR REPLACE FUNCTION check_slot_availability(
  p_staff_id uuid,
  p_start_time timestamptz,
  p_end_time timestamptz
)
RETURNS boolean AS $$
DECLARE
  v_conflicts integer;
BEGIN
  -- Check for overlapping video calls
  SELECT COUNT(*)
  INTO v_conflicts
  FROM video_calls
  WHERE staff_id = p_staff_id
    AND status = 'scheduled'
    AND tstzrange(scheduled_at, scheduled_at + interval '1 hour') &&  -- Default 1 hour duration
        tstzrange(p_start_time, p_end_time);

  -- Also check time slots table
  IF v_conflicts = 0 THEN
    SELECT COUNT(*)
    INTO v_conflicts
    FROM time_slots
    WHERE staff_id = p_staff_id
      AND NOT is_available
      AND tstzrange(start_time - buffer_before, end_time + buffer_after) &&
          tstzrange(p_start_time, p_end_time);
  END IF;

  RETURN v_conflicts = 0;
END;
$$ LANGUAGE plpgsql;

-- Create function to schedule video call
CREATE OR REPLACE FUNCTION schedule_video_call(
  p_customer_id uuid,
  p_staff_id uuid,
  p_scheduled_at timestamptz,
  p_duration interval DEFAULT interval '1 hour',
  p_customer_timezone text DEFAULT NULL
)
RETURNS uuid AS $$
DECLARE
  v_video_call_id uuid;
  v_end_time timestamptz;
  v_customer_type text;
  v_settings jsonb;
BEGIN
  -- Calculate end time
  v_end_time := p_scheduled_at + p_duration;

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
      'duration', p_duration,
      'customer_timezone', p_customer_timezone
    )
  );

  RETURN v_video_call_id;
END;
$$ LANGUAGE plpgsql;

-- Create function to reschedule video call
CREATE OR REPLACE FUNCTION reschedule_video_call(
  p_video_call_id uuid,
  p_new_time timestamptz,
  p_duration interval DEFAULT interval '1 hour'
)
RETURNS boolean AS $$
DECLARE
  v_old_slot record;
  v_end_time timestamptz;
BEGIN
  -- Get current time slot
  SELECT staff_id, scheduled_at
  INTO v_old_slot
  FROM video_calls
  WHERE id = p_video_call_id;

  -- Calculate new end time
  v_end_time := p_new_time + p_duration;

  -- Check if new slot is available
  IF NOT check_slot_availability(v_old_slot.staff_id, p_new_time, v_end_time) THEN
    RETURN false;
  END IF;

  -- Update video call
  UPDATE video_calls
  SET 
    scheduled_at = p_new_time,
    updated_at = now()
  WHERE id = p_video_call_id;

  -- Update time slot
  UPDATE time_slots
  SET 
    start_time = p_new_time,
    end_time = v_end_time,
    updated_at = now()
  WHERE staff_id = v_old_slot.staff_id
    AND start_time = v_old_slot.scheduled_at;

  -- Create notification for rescheduling
  INSERT INTO notifications (
    user_id,
    type,
    title,
    message,
    data
  ) VALUES (
    v_old_slot.staff_id,
    'video_call_rescheduled',
    'Video Call Rescheduled',
    format(
      'Your video call has been rescheduled to %s',
      to_char(p_new_time, 'DD Mon YYYY HH24:MI')
    ),
    jsonb_build_object(
      'video_call_id', p_video_call_id,
      'old_time', v_old_slot.scheduled_at,
      'new_time', p_new_time,
      'duration', p_duration
    )
  );

  RETURN true;
END;
$$ LANGUAGE plpgsql;