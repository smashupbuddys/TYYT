-- Drop existing policies if they exist
DO $$ 
BEGIN
  -- Drop policies if they exist
  DROP POLICY IF EXISTS "Allow public read access on notifications" ON notifications;
  DROP POLICY IF EXISTS "Allow public insert access on notifications" ON notifications;
  DROP POLICY IF EXISTS "Allow public update access on notifications" ON notifications;
END $$;

-- Create notifications table if it doesn't exist
CREATE TABLE IF NOT EXISTS notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  type text NOT NULL,
  title text NOT NULL,
  message text NOT NULL,
  data jsonb DEFAULT '{}',
  read boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on notifications"
  ON notifications FOR SELECT TO public
  USING (true);

CREATE POLICY "Allow public insert access on notifications"
  ON notifications FOR INSERT TO public
  WITH CHECK (true);

CREATE POLICY "Allow public update access on notifications"
  ON notifications FOR UPDATE TO public
  USING (true)
  WITH CHECK (true);

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at);
CREATE INDEX IF NOT EXISTS idx_notifications_read ON notifications(read) WHERE NOT read;

-- Create function to create notification
CREATE OR REPLACE FUNCTION create_notification(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_message text,
  p_data jsonb DEFAULT '{}'
)
RETURNS uuid AS $$
DECLARE
  v_notification_id uuid;
BEGIN
  INSERT INTO notifications (
    user_id,
    type,
    title,
    message,
    data
  ) VALUES (
    p_user_id,
    p_type,
    p_title,
    p_message,
    p_data
  )
  RETURNING id INTO v_notification_id;

  RETURN v_notification_id;
END;
$$ LANGUAGE plpgsql;

-- Create function to mark notifications as read
CREATE OR REPLACE FUNCTION mark_notifications_read(
  p_user_id uuid,
  p_notification_ids uuid[] DEFAULT NULL
)
RETURNS void AS $$
BEGIN
  UPDATE notifications
  SET read = true
  WHERE user_id = p_user_id
  AND (p_notification_ids IS NULL OR id = ANY(p_notification_ids));
END;
$$ LANGUAGE plpgsql;

-- Add helpful comments
COMMENT ON TABLE notifications IS 'Stores system notifications for users';
COMMENT ON FUNCTION create_notification IS 'Creates a new notification for a user';
COMMENT ON FUNCTION mark_notifications_read IS 'Marks notifications as read for a user';