/*
  # Video Call Scheduling Rules

  1. New Tables
    - video_call_rules: Stores business hours and scheduling rules
    - recurring_calls: Tracks recurring video call schedules

  2. Changes
    - Add recurring_schedule to video_calls table
    - Add validation functions for scheduling rules

  3. Security
    - Enable RLS
    - Add policies for staff access
*/

-- Create video_call_rules table
CREATE TABLE video_call_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  day_of_week integer NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  start_time time NOT NULL DEFAULT '10:30',
  end_time time NOT NULL DEFAULT '20:00',
  is_working_day boolean DEFAULT true,
  special_hours jsonb DEFAULT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create recurring_calls table
CREATE TABLE recurring_calls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid REFERENCES customers(id) ON DELETE CASCADE,
  staff_id uuid NOT NULL,
  frequency text NOT NULL CHECK (frequency IN ('weekly', 'biweekly', 'monthly')),
  day_of_week integer CHECK (day_of_week BETWEEN 0 AND 6),
  time_of_day time NOT NULL,
  start_date date NOT NULL,
  end_date date,
  last_scheduled_date date,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Add recurring schedule to video_calls
ALTER TABLE video_calls
  ADD COLUMN recurring_schedule_id uuid REFERENCES recurring_calls(id);

-- Create function to validate business hours
CREATE OR REPLACE FUNCTION validate_business_hours(
  p_scheduled_at timestamptz,
  p_customer_type text DEFAULT 'retail'
)
RETURNS boolean AS $$
DECLARE
  v_day_of_week integer;
  v_time time;
  v_rule record;
BEGIN
  -- Get day of week (0 = Sunday) and time
  v_day_of_week := EXTRACT(DOW FROM p_scheduled_at);
  v_time := p_scheduled_at::time;

  -- Get business hours for this day
  SELECT * INTO v_rule
  FROM video_call_rules
  WHERE day_of_week = v_day_of_week;

  -- Check if it's a working day
  IF NOT v_rule.is_working_day THEN
    RETURN false;
  END IF;

  -- Check special hours for this date if any
  IF v_rule.special_hours IS NOT NULL AND 
     v_rule.special_hours ? p_scheduled_at::date::text THEN
    RETURN v_time BETWEEN 
      (v_rule.special_hours->>p_scheduled_at::date::text)::jsonb->>'start_time' AND
      (v_rule.special_hours->>p_scheduled_at::date::text)::jsonb->>'end_time';
  END IF;

  -- Check regular business hours
  -- Give preference to wholesale customers by allowing slightly outside hours
  RETURN CASE 
    WHEN p_customer_type = 'wholesale' THEN
      v_time BETWEEN 
        (v_rule.start_time - interval '30 minutes') AND
        (v_rule.end_time + interval '30 minutes')
    ELSE
      v_time BETWEEN v_rule.start_time AND v_rule.end_time
  END;
END;
$$ LANGUAGE plpgsql;

-- Create function to check staff availability for video calls
CREATE OR REPLACE FUNCTION check_staff_video_call_availability(
  p_staff_id uuid,
  p_scheduled_at timestamptz,
  p_duration interval DEFAULT interval '30 minutes'
)
RETURNS boolean AS $$
DECLARE
  v_conflicts integer;
BEGIN
  -- Check for overlapping calls
  SELECT COUNT(*)
  INTO v_conflicts
  FROM video_calls
  WHERE staff_id = p_staff_id
    AND status = 'scheduled'
    AND tstzrange(scheduled_at, scheduled_at + interval '30 minutes') &&
        tstzrange(p_scheduled_at, p_scheduled_at + p_duration);

  RETURN v_conflicts = 0;
END;
$$ LANGUAGE plpgsql;

-- Create function to schedule recurring calls
CREATE OR REPLACE FUNCTION schedule_recurring_calls()
RETURNS void AS $$
DECLARE
  v_recurring record;
  v_next_date date;
BEGIN
  FOR v_recurring IN 
    SELECT * FROM recurring_calls 
    WHERE is_active = true 
    AND (last_scheduled_date IS NULL OR last_scheduled_date < CURRENT_DATE)
  LOOP
    -- Calculate next date based on frequency
    v_next_date := CASE v_recurring.frequency
      WHEN 'weekly' THEN v_recurring.last_scheduled_date + interval '1 week'
      WHEN 'biweekly' THEN v_recurring.last_scheduled_date + interval '2 weeks'
      WHEN 'monthly' THEN v_recurring.last_scheduled_date + interval '1 month'
      ELSE v_recurring.start_date
    END;

    -- Schedule next call if within end date
    IF v_recurring.end_date IS NULL OR v_next_date <= v_recurring.end_date THEN
      INSERT INTO video_calls (
        customer_id,
        staff_id,
        scheduled_at,
        status,
        recurring_schedule_id
      ) VALUES (
        v_recurring.customer_id,
        v_recurring.staff_id,
        v_next_date + v_recurring.time_of_day,
        'scheduled',
        v_recurring.id
      );

      -- Update last scheduled date
      UPDATE recurring_calls
      SET last_scheduled_date = v_next_date
      WHERE id = v_recurring.id;
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Insert default business hours
INSERT INTO video_call_rules (day_of_week, start_time, end_time, is_working_day) VALUES
  (0, '10:30', '14:00', true),  -- Sunday
  (1, '10:30', '20:00', true),  -- Monday
  (2, '10:30', '20:00', true),  -- Tuesday
  (3, '10:30', '20:00', true),  -- Wednesday
  (4, '10:30', '20:00', true),  -- Thursday
  (5, '10:30', '20:00', true),  -- Friday
  (6, '10:30', '20:00', true);  -- Saturday

-- Enable RLS
ALTER TABLE video_call_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE recurring_calls ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow staff read access on video_call_rules"
  ON video_call_rules FOR SELECT TO public USING (true);

CREATE POLICY "Allow staff read access on recurring_calls"
  ON recurring_calls FOR SELECT TO public USING (true);

CREATE POLICY "Allow staff insert access on recurring_calls"
  ON recurring_calls FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow staff update access on recurring_calls"
  ON recurring_calls FOR UPDATE TO public USING (true);

-- Add helpful comments
COMMENT ON TABLE video_call_rules IS 'Stores business hours and scheduling rules for video calls';
COMMENT ON TABLE recurring_calls IS 'Tracks recurring video call schedules for regular customers';
COMMENT ON FUNCTION validate_business_hours IS 'Validates if a video call can be scheduled at the given time';
COMMENT ON FUNCTION check_staff_video_call_availability IS 'Checks if staff member is available for a video call';
COMMENT ON FUNCTION schedule_recurring_calls IS 'Schedules the next set of recurring video calls';