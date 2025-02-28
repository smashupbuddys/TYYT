-- Create function to handle staff availability on video call deletion
CREATE OR REPLACE FUNCTION handle_video_call_deletion()
RETURNS TRIGGER AS $$
DECLARE
  v_staff_id uuid;
  v_staff_name text;
BEGIN
  -- Get staff ID from assigned_staff if available, otherwise use staff_id
  v_staff_id := COALESCE(
    (OLD.assigned_staff->>'primary')::uuid,
    OLD.staff_id
  );

  -- Get staff name
  v_staff_name := OLD.assigned_staff->>'staff_name';

  -- If there was an assigned staff member
  IF v_staff_id IS NOT NULL THEN
    -- Create notification about staff becoming available
    INSERT INTO notifications (
      user_id,
      type,
      title,
      message,
      data
    ) VALUES (
      v_staff_id,
      'staff_availability',
      'Video Call Deleted',
      format(
        'The video call scheduled for %s has been deleted. You are now available for other assignments.',
        to_char(OLD.scheduled_at, 'DD Mon YYYY HH24:MI')
      ),
      jsonb_build_object(
        'video_call_number', OLD.video_call_number,
        'scheduled_at', OLD.scheduled_at,
        'customer_name', COALESCE((SELECT name FROM customers WHERE id = OLD.customer_id), 'Unknown Customer')
      )
    );

    -- Log the change in workflow history
    INSERT INTO workflow_history (
      video_call_id,
      step,
      old_status,
      new_status,
      changed_by,
      notes
    ) VALUES (
      OLD.id,
      'video_call',
      OLD.status,
      'deleted',
      current_setting('app.current_user_id', true)::uuid,
      format('Video call deleted. Staff member %s is now available.', v_staff_name)
    );
  END IF;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for staff availability on video call deletion
DROP TRIGGER IF EXISTS handle_video_call_deletion_trigger ON video_calls;
CREATE TRIGGER handle_video_call_deletion_trigger
  BEFORE DELETE ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION handle_video_call_deletion();

-- Add helpful comment
COMMENT ON FUNCTION handle_video_call_deletion IS 'Handles staff availability and notifications when a video call is deleted';