-- Add notification preferences to staff table if not exists
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'staff' AND column_name = 'notification_preferences'
  ) THEN
    ALTER TABLE staff
      ADD COLUMN notification_preferences jsonb DEFAULT '{
        "whatsapp_enabled": false,
        "email_enabled": true,
        "sound_enabled": true,
        "speech_enabled": true,
        "desktop_notifications": true,
        "voice_settings": {
          "voice": "Microsoft Swara",
          "language": "hi-IN",
          "pitch": 1,
          "rate": 1,
          "volume": 0.8
        },
        "notification_types": {
          "video_call_reminder": true,
          "payment_overdue": true,
          "workflow_update": true
        }
      }';
  END IF;
END $$;

-- Create voice_templates table
CREATE TABLE IF NOT EXISTS voice_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  voice_uri text NOT NULL,
  language text NOT NULL,
  pitch numeric NOT NULL DEFAULT 1 CHECK (pitch >= 0.5 AND pitch <= 2),
  rate numeric NOT NULL DEFAULT 1 CHECK (rate >= 0.5 AND rate <= 2),
  volume numeric NOT NULL DEFAULT 1 CHECK (volume >= 0 AND volume <= 1),
  template_text text NOT NULL,
  is_default boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE voice_templates ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on voice_templates"
  ON voice_templates FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on voice_templates"
  ON voice_templates FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on voice_templates"
  ON voice_templates FOR UPDATE TO public USING (true);

-- Insert default voice templates
INSERT INTO voice_templates (name, voice_uri, language, template_text, is_default) VALUES
  ('Default Hindi', 'Microsoft Swara', 'hi-IN', '{{staff}}, aapki call {{customer}} ke saath {{time}} minute mein hai! Ready ho jaiye!', true),
  ('Professional Hindi', 'Google हिन्दी', 'hi-IN', '{{staff}} ji, {{customer}} ke saath aapki video call {{time}} minute mein scheduled hai. Kripya taiyar rahein.', false),
  ('Casual Hindi', 'hi-IN', 'hi-IN', 'Hello {{staff}}, {{customer}} ke saath video call {{time}} minute mein start hone wali hai!', false)
ON CONFLICT DO NOTHING;

-- Update demo staff with notification preferences
UPDATE staff
SET notification_preferences = '{
  "whatsapp_enabled": true,
  "email_enabled": true,
  "sound_enabled": true,
  "speech_enabled": true,
  "desktop_notifications": true,
  "voice_settings": {
    "voice": "Microsoft Swara",
    "language": "hi-IN",
    "pitch": 1,
    "rate": 1,
    "volume": 0.8
  },
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

-- Add helpful comments
COMMENT ON TABLE voice_templates IS 'Stores voice configuration templates for notifications';
COMMENT ON COLUMN staff.notification_preferences IS 'JSON object containing staff notification preferences and voice settings';