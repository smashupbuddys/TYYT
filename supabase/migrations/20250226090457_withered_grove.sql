-- Drop existing voice_templates table and recreate with correct schema
DROP TABLE IF EXISTS voice_templates CASCADE;

CREATE TABLE voice_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  voice_uri text NOT NULL,
  language text NOT NULL,
  text text NOT NULL,
  pitch numeric NOT NULL DEFAULT 1 CHECK (pitch >= 0.5 AND pitch <= 2),
  rate numeric NOT NULL DEFAULT 1 CHECK (rate >= 0.5 AND rate <= 2),
  volume numeric NOT NULL DEFAULT 1 CHECK (volume >= 0 AND volume <= 1),
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
INSERT INTO voice_templates (name, voice_uri, language, text, is_default) VALUES
  ('Default Hindi', 'Microsoft Swara', 'hi-IN', '{{staff}}, aapki call {{customer}} ke saath {{time}} minute mein hai! Ready ho jaiye!', true),
  ('Professional Hindi', 'Google हिन्दी', 'hi-IN', '{{staff}} ji, {{customer}} ke saath aapki video call {{time}} minute mein scheduled hai. Kripya taiyar rahein.', false),
  ('Casual Hindi', 'hi-IN', 'hi-IN', 'Hello {{staff}}, {{customer}} ke saath video call {{time}} minute mein start hone wali hai!', false)
ON CONFLICT DO NOTHING;

-- Create demo staff if they don't exist
INSERT INTO staff (id, name, email, role, active)
VALUES 
  ('00000000-0000-0000-0000-000000000001', 'Admin User', 'admin@example.com', 'admin', true),
  ('00000000-0000-0000-0000-000000000002', 'Manager User', 'manager@example.com', 'manager', true),
  ('00000000-0000-0000-0000-000000000003', 'Sales User', 'sales@example.com', 'sales', true)
ON CONFLICT (id) DO UPDATE
SET 
  name = EXCLUDED.name,
  role = EXCLUDED.role,
  active = true;

-- Update staff notification preferences
UPDATE staff
SET notification_preferences = jsonb_build_object(
  'whatsapp_enabled', COALESCE((notification_preferences->>'whatsapp_enabled')::boolean, false),
  'email_enabled', COALESCE((notification_preferences->>'email_enabled')::boolean, true),
  'sound_enabled', COALESCE((notification_preferences->>'sound_enabled')::boolean, true),
  'speech_enabled', COALESCE((notification_preferences->>'speech_enabled')::boolean, true),
  'desktop_notifications', COALESCE((notification_preferences->>'desktop_notifications')::boolean, true),
  'voice_settings', jsonb_build_object(
    'voice', 'Microsoft Swara',
    'language', 'hi-IN',
    'pitch', 1,
    'rate', 1,
    'volume', 0.8
  ),
  'notification_types', jsonb_build_object(
    'video_call_reminder', true,
    'payment_overdue', true,
    'workflow_update', true
  )
)
WHERE id IN (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000003'
);

-- Add helpful comments
COMMENT ON TABLE voice_templates IS 'Stores voice configuration templates for notifications';
COMMENT ON COLUMN voice_templates.text IS 'Template text with placeholders for dynamic content';
COMMENT ON COLUMN staff.notification_preferences IS 'JSON object containing staff notification preferences and voice settings';