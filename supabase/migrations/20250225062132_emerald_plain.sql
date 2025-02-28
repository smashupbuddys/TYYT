-- Create video call logs table
CREATE TABLE video_call_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  video_call_id uuid REFERENCES video_calls(id) ON DELETE CASCADE,
  event_type text NOT NULL CHECK (event_type IN (
    'created',
    'rescheduled',
    'staff_assigned',
    'staff_changed',
    'status_changed',
    'workflow_updated',
    'cancelled',
    'deleted'
  )),
  old_data jsonb,
  new_data jsonb,
  changed_by uuid REFERENCES staff(id),
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE video_call_logs ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on video_call_logs"
  ON video_call_logs FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on video_call_logs"
  ON video_call_logs FOR INSERT TO public WITH CHECK (true);

-- Create function to log video call changes
CREATE OR REPLACE FUNCTION log_video_call_changes()
RETURNS TRIGGER AS $$
DECLARE
  v_event_type text;
  v_old_data jsonb;
  v_new_data jsonb;
  v_changed_by uuid;
BEGIN
  -- Get current user ID with fallback
  v_changed_by := COALESCE(
    current_setting('app.current_user_id', true)::uuid,
    NULL
  );

  -- Determine event type and data to log
  IF TG_OP = 'INSERT' THEN
    v_event_type := 'created';
    v_old_data := NULL;
    v_new_data := to_jsonb(NEW);
  ELSIF TG_OP = 'UPDATE' THEN
    -- Determine specific update type
    IF NEW.scheduled_at != OLD.scheduled_at THEN
      v_event_type := 'rescheduled';
      v_old_data := jsonb_build_object('scheduled_at', OLD.scheduled_at);
      v_new_data := jsonb_build_object('scheduled_at', NEW.scheduled_at);
    ELSIF NEW.staff_id != OLD.staff_id THEN
      v_event_type := CASE
        WHEN OLD.staff_id IS NULL THEN 'staff_assigned'
        ELSE 'staff_changed'
      END;
      v_old_data := jsonb_build_object(
        'staff_id', OLD.staff_id,
        'assigned_staff', OLD.assigned_staff
      );
      v_new_data := jsonb_build_object(
        'staff_id', NEW.staff_id,
        'assigned_staff', NEW.assigned_staff
      );
    ELSIF NEW.status != OLD.status THEN
      v_event_type := 'status_changed';
      v_old_data := jsonb_build_object('status', OLD.status);
      v_new_data := jsonb_build_object('status', NEW.status);
    ELSIF NEW.workflow_status != OLD.workflow_status THEN
      v_event_type := 'workflow_updated';
      v_old_data := jsonb_build_object('workflow_status', OLD.workflow_status);
      v_new_data := jsonb_build_object('workflow_status', NEW.workflow_status);
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    v_event_type := 'deleted';
    v_old_data := to_jsonb(OLD);
    v_new_data := NULL;
  END IF;

  -- Insert log entry if we have an event type
  IF v_event_type IS NOT NULL THEN
    INSERT INTO video_call_logs (
      video_call_id,
      event_type,
      old_data,
      new_data,
      changed_by
    ) VALUES (
      COALESCE(NEW.id, OLD.id),
      v_event_type,
      v_old_data,
      v_new_data,
      v_changed_by
    );
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Create triggers for logging
CREATE TRIGGER log_video_call_changes_trigger
  AFTER INSERT OR UPDATE OR DELETE ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION log_video_call_changes();

-- Create function to get video call logs
CREATE OR REPLACE FUNCTION get_video_call_logs(
  p_video_call_id uuid,
  p_start_date timestamptz DEFAULT NULL,
  p_end_date timestamptz DEFAULT NULL
)
RETURNS TABLE (
  event_type text,
  old_data jsonb,
  new_data jsonb,
  changed_by_name text,
  created_at timestamptz
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    l.event_type,
    l.old_data,
    l.new_data,
    s.name as changed_by_name,
    l.created_at
  FROM video_call_logs l
  LEFT JOIN staff s ON s.id = l.changed_by
  WHERE l.video_call_id = p_video_call_id
  AND (p_start_date IS NULL OR l.created_at >= p_start_date)
  AND (p_end_date IS NULL OR l.created_at <= p_end_date)
  ORDER BY l.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Add indexes for better performance
CREATE INDEX idx_video_call_logs_video_call_id ON video_call_logs(video_call_id);
CREATE INDEX idx_video_call_logs_event_type ON video_call_logs(event_type);
CREATE INDEX idx_video_call_logs_created_at ON video_call_logs(created_at);

-- Add helpful comments
COMMENT ON TABLE video_call_logs IS 'Stores audit logs for video call changes';
COMMENT ON FUNCTION log_video_call_changes IS 'Automatically logs changes to video calls';
COMMENT ON FUNCTION get_video_call_logs IS 'Retrieves formatted logs for a video call';