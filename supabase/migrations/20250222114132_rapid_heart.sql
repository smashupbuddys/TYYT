-- Add notification preferences columns to staff table
ALTER TABLE staff
  ADD COLUMN IF NOT EXISTS phone text,
  ADD COLUMN IF NOT EXISTS notification_preferences jsonb DEFAULT '{
    "whatsapp_enabled": false,
    "email_enabled": true,
    "sound_enabled": true,
    "speech_enabled": true,
    "desktop_notifications": true,
    "notification_types": {
      "video_call_reminder": true,
      "payment_overdue": true,
      "workflow_update": true
    }
  }';

-- Add index for better performance
CREATE INDEX IF NOT EXISTS idx_staff_phone ON staff(phone);

-- Update demo staff with notification preferences
UPDATE staff
SET 
  notification_preferences = '{
    "whatsapp_enabled": true,
    "email_enabled": true,
    "sound_enabled": true,
    "speech_enabled": true,
    "desktop_notifications": true,
    "notification_types": {
      "video_call_reminder": true,
      "payment_overdue": true,
      "workflow_update": true
    }
  }'::jsonb
WHERE id IN (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000003'
);

-- Add helpful comment
COMMENT ON COLUMN staff.notification_preferences IS 'JSON object containing staff notification preferences and settings';