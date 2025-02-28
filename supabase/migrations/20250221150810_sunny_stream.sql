-- First, drop dependent objects in correct order
DROP TRIGGER IF EXISTS validate_video_call_trigger ON video_calls;
DROP FUNCTION IF EXISTS validate_video_call();
DROP FUNCTION IF EXISTS check_staff_availability();

-- Drop foreign key constraints that reference video_calls
ALTER TABLE profiling_responses
  DROP CONSTRAINT IF EXISTS profiling_responses_video_call_id_fkey;

ALTER TABLE staff_ratings
  DROP CONSTRAINT IF EXISTS staff_ratings_video_call_id_fkey;

-- Create temporary table to store video call data
CREATE TEMP TABLE temp_video_calls AS 
SELECT 
  id,
  customer_id,
  staff_id,
  scheduled_at,
  status,
  notes,
  quotation_required,
  quotation_id,
  payment_status,
  payment_due_date,
  bill_amount,
  bill_status,
  bill_generated_at,
  bill_sent_at,
  bill_paid_at,
  workflow_status,
  assigned_staff,
  time_zone,
  customer_time_zone,
  video_call_number,
  created_at,
  updated_at
FROM video_calls;

-- Drop and recreate video_calls table with correct column type
DROP TABLE video_calls CASCADE;

CREATE TABLE video_calls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid REFERENCES customers(id),
  staff_id uuid NOT NULL,
  scheduled_at timestamptz NOT NULL,
  status text NOT NULL CHECK (status IN ('scheduled', 'completed', 'cancelled')),
  notes text,
  quotation_required boolean DEFAULT false,
  quotation_id uuid,
  payment_status text CHECK (payment_status IN ('pending', 'completed', 'overdue')) DEFAULT 'pending',
  payment_due_date timestamptz,
  bill_amount numeric DEFAULT 0,
  bill_status text CHECK (bill_status IN ('pending', 'generated', 'sent', 'paid', 'overdue')) DEFAULT 'pending',
  bill_generated_at timestamptz,
  bill_sent_at timestamptz,
  bill_paid_at timestamptz,
  workflow_status jsonb DEFAULT '{
    "video_call": "pending",
    "quotation": "pending",
    "profiling": "pending",
    "payment": "pending",
    "qc": "pending",
    "packaging": "pending",
    "dispatch": "pending"
  }',
  assigned_staff jsonb DEFAULT '{
    "primary": null,
    "backup": null,
    "history": []
  }',
  time_zone text,
  customer_time_zone text,
  customer_country text,
  video_call_number text UNIQUE,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Restore data from temporary table
INSERT INTO video_calls (
  id, customer_id, staff_id, scheduled_at, status, notes,
  quotation_required, quotation_id, payment_status, payment_due_date,
  bill_amount, bill_status, bill_generated_at, bill_sent_at, bill_paid_at,
  workflow_status, assigned_staff, time_zone, customer_time_zone,
  video_call_number, created_at, updated_at
)
SELECT 
  id, customer_id, staff_id::uuid, scheduled_at, status, notes,
  quotation_required, quotation_id, payment_status, payment_due_date,
  bill_amount, bill_status, bill_generated_at, bill_sent_at, bill_paid_at,
  workflow_status, assigned_staff, time_zone, customer_time_zone,
  video_call_number, created_at, updated_at
FROM temp_video_calls;

-- Drop temporary table
DROP TABLE temp_video_calls;

-- Recreate foreign key constraints
ALTER TABLE profiling_responses
  ADD CONSTRAINT profiling_responses_video_call_id_fkey 
  FOREIGN KEY (video_call_id) 
  REFERENCES video_calls(id) 
  ON DELETE CASCADE;

ALTER TABLE staff_ratings
  ADD CONSTRAINT staff_ratings_video_call_id_fkey 
  FOREIGN KEY (video_call_id) 
  REFERENCES video_calls(id) 
  ON DELETE CASCADE;

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