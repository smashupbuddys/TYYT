-- Add staff assignment tracking to video_calls
ALTER TABLE video_calls
  ADD COLUMN IF NOT EXISTS assigned_staff jsonb DEFAULT '{
    "primary": null,
    "backup": null,
    "history": []
  }';

-- Create staff_availability table
CREATE TABLE IF NOT EXISTS staff_availability (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid REFERENCES staff(id) ON DELETE CASCADE,
  date date NOT NULL,
  time_slots jsonb NOT NULL DEFAULT '[]',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create staff_notifications table
CREATE TABLE IF NOT EXISTS staff_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid REFERENCES staff(id) ON DELETE CASCADE,
  type text NOT NULL,
  title text NOT NULL,
  message text NOT NULL,
  data jsonb DEFAULT '{}',
  read boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE staff_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_notifications ENABLE ROW LEVEL SECURITY;

-- Create policies with existence checks
DO $$ 
BEGIN
  -- Staff Availability Policies
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'staff_availability' AND policyname = 'Allow public read access on staff_availability'
  ) THEN
    CREATE POLICY "Allow public read access on staff_availability"
      ON staff_availability FOR SELECT TO public USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'staff_availability' AND policyname = 'Allow public insert access on staff_availability'
  ) THEN
    CREATE POLICY "Allow public insert access on staff_availability"
      ON staff_availability FOR INSERT TO public WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'staff_availability' AND policyname = 'Allow public update access on staff_availability'
  ) THEN
    CREATE POLICY "Allow public update access on staff_availability"
      ON staff_availability FOR UPDATE TO public USING (true);
  END IF;

  -- Staff Notifications Policies
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'staff_notifications' AND policyname = 'Allow public read access on staff_notifications'
  ) THEN
    CREATE POLICY "Allow public read access on staff_notifications"
      ON staff_notifications FOR SELECT TO public USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'staff_notifications' AND policyname = 'Allow public insert access on staff_notifications'
  ) THEN
    CREATE POLICY "Allow public insert access on staff_notifications"
      ON staff_notifications FOR INSERT TO public WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'staff_notifications' AND policyname = 'Allow public update access on staff_notifications'
  ) THEN
    CREATE POLICY "Allow public update access on staff_notifications"
      ON staff_notifications FOR UPDATE TO public USING (true);
  END IF;
END $$;

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
    WHERE (assigned_staff->>'primary')::uuid = p_staff_id
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

-- Create function to assign staff to video call
CREATE OR REPLACE FUNCTION assign_staff_to_call()
RETURNS TRIGGER AS $$
BEGIN
  -- Add assignment to history
  NEW.assigned_staff = jsonb_set(
    COALESCE(NEW.assigned_staff, '{}'::jsonb),
    '{history}',
    COALESCE(NEW.assigned_staff->'history', '[]'::jsonb) || jsonb_build_object(
      'staff_id', NEW.staff_id,
      'assigned_at', now(),
      'assigned_by', current_user
    )
  );

  -- Create notification for assigned staff
  INSERT INTO staff_notifications (
    staff_id,
    type,
    title,
    message,
    data
  ) VALUES (
    NEW.staff_id,
    'video_call_assignment',
    'New Video Call Assignment',
    format('You have been assigned to a video call with %s on %s',
      (SELECT name FROM customers WHERE id = NEW.customer_id),
      to_char(NEW.scheduled_at, 'DD Mon YYYY HH24:MI')
    ),
    jsonb_build_object(
      'video_call_id', NEW.id,
      'scheduled_at', NEW.scheduled_at,
      'customer_id', NEW.customer_id
    )
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for staff assignment
DROP TRIGGER IF EXISTS video_call_staff_assignment ON video_calls;
CREATE TRIGGER video_call_staff_assignment
  BEFORE INSERT OR UPDATE OF staff_id ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION assign_staff_to_call();

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_video_calls_assigned_staff ON video_calls USING btree ((assigned_staff->>'primary'));
CREATE INDEX IF NOT EXISTS idx_staff_availability_date ON staff_availability(date);
CREATE INDEX IF NOT EXISTS idx_staff_notifications_staff_id ON staff_notifications(staff_id);

-- Update existing video calls with default values
UPDATE video_calls
SET assigned_staff = COALESCE(
  assigned_staff,
  jsonb_build_object(
    'primary', staff_id,
    'backup', NULL,
    'history', jsonb_build_array(
      jsonb_build_object(
        'staff_id', staff_id,
        'assigned_at', created_at,
        'assigned_by', 'system'
      )
    )
  )
)
WHERE assigned_staff IS NULL;