/*
  # Fix Video Calls Schema and Validation

  1. Changes
    - Fix staff_id column type to UUID
    - Add proper notice period validation
    - Add staff availability check function
    - Add video call validation function

  2. Security
    - Maintain existing RLS policies
    - Add proper constraints
*/

-- First, temporarily disable the trigger that might interfere
DROP TRIGGER IF EXISTS video_call_staff_assignment ON video_calls;

-- Update staff_id column to UUID type
ALTER TABLE video_calls
  ALTER COLUMN staff_id TYPE uuid USING staff_id::uuid;

-- Create function to check staff availability
CREATE OR REPLACE FUNCTION check_staff_availability(
  p_staff_id uuid,
  p_date date,
  p_start_time time,
  p_end_time time
) RETURNS boolean AS $$
DECLARE
  v_available boolean;
BEGIN
  -- Check if staff member has any overlapping calls
  SELECT NOT EXISTS (
    SELECT 1
    FROM video_calls
    WHERE staff_id = p_staff_id
    AND date_trunc('day', scheduled_at) = p_date
    AND (
      (scheduled_at::time BETWEEN p_start_time AND p_end_time) OR
      ((scheduled_at + interval '30 minutes')::time BETWEEN p_start_time AND p_end_time)
    )
    AND status = 'scheduled'
  ) INTO v_available;

  RETURN v_available;
END;
$$ LANGUAGE plpgsql;

-- Create function to validate video call scheduling
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

  -- Check staff availability
  IF NOT check_staff_availability(
    NEW.staff_id,
    NEW.scheduled_at::date,
    NEW.scheduled_at::time,
    (NEW.scheduled_at + interval '30 minutes')::time
  ) THEN
    RAISE EXCEPTION 'Selected staff member is not available at this time';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for video call validation
CREATE TRIGGER validate_video_call_trigger
  BEFORE INSERT OR UPDATE OF scheduled_at, staff_id ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION validate_video_call();

-- Add helpful comment
COMMENT ON TABLE video_calls IS 'Stores video call appointments with proper validation for scheduling and staff availability.';