-- Create voice_templates table
CREATE TABLE IF NOT EXISTS voice_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  voice_uri text NOT NULL,
  language text NOT NULL,
  pitch numeric NOT NULL DEFAULT 1 CHECK (pitch >= 0.5 AND pitch <= 2),
  rate numeric NOT NULL DEFAULT 1 CHECK (rate >= 0.5 AND rate <= 2),
  volume numeric NOT NULL DEFAULT 1 CHECK (volume >= 0 AND volume <= 1),
  is_default boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create scenario_templates table
CREATE TABLE IF NOT EXISTS scenario_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  voice_template_id uuid REFERENCES voice_templates(id) ON DELETE CASCADE,
  template_text text NOT NULL,
  context text,
  priority integer NOT NULL DEFAULT 1,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create template_tags table
CREATE TABLE IF NOT EXISTS template_tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create scenario_template_tags table
CREATE TABLE IF NOT EXISTS scenario_template_tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scenario_template_id uuid REFERENCES scenario_templates(id) ON DELETE CASCADE,
  tag_id uuid REFERENCES template_tags(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE voice_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE scenario_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE template_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE scenario_template_tags ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on voice_templates"
  ON voice_templates FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on voice_templates"
  ON voice_templates FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on voice_templates"
  ON voice_templates FOR UPDATE TO public USING (true);

CREATE POLICY "Allow public delete access on voice_templates"
  ON voice_templates FOR DELETE TO public USING (true);

CREATE POLICY "Allow public read access on scenario_templates"
  ON scenario_templates FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on scenario_templates"
  ON scenario_templates FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on scenario_templates"
  ON scenario_templates FOR UPDATE TO public USING (true);

CREATE POLICY "Allow public delete access on scenario_templates"
  ON scenario_templates FOR DELETE TO public USING (true);

CREATE POLICY "Allow public read access on template_tags"
  ON template_tags FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on template_tags"
  ON template_tags FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on template_tags"
  ON template_tags FOR UPDATE TO public USING (true);

CREATE POLICY "Allow public delete access on template_tags"
  ON template_tags FOR DELETE TO public USING (true);

CREATE POLICY "Allow public read access on scenario_template_tags"
  ON scenario_template_tags FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on scenario_template_tags"
  ON scenario_template_tags FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public delete access on scenario_template_tags"
  ON scenario_template_tags FOR DELETE TO public USING (true);

-- Create function to ensure only one default template
CREATE OR REPLACE FUNCTION ensure_single_default_template()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_default THEN
    UPDATE voice_templates
    SET is_default = false
    WHERE id != NEW.id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for default template management
CREATE TRIGGER ensure_single_default_template_trigger
  BEFORE INSERT OR UPDATE OF is_default ON voice_templates
  FOR EACH ROW
  WHEN (NEW.is_default = true)
  EXECUTE FUNCTION ensure_single_default_template();

-- Add indexes for better performance
CREATE INDEX idx_voice_templates_language ON voice_templates(language);
CREATE INDEX idx_voice_templates_is_default ON voice_templates(is_default);
CREATE INDEX idx_scenario_templates_priority ON scenario_templates(priority);
CREATE INDEX idx_scenario_templates_voice_template_id ON scenario_templates(voice_template_id);
CREATE INDEX idx_template_tags_name ON template_tags(name);
CREATE INDEX idx_scenario_template_tags_scenario_template_id ON scenario_template_tags(scenario_template_id);
CREATE INDEX idx_scenario_template_tags_tag_id ON scenario_template_tags(tag_id);

-- Insert default template tags
INSERT INTO template_tags (name, description) VALUES
  ('{{staff}}', 'Replaced with staff member name'),
  ('{{customer}}', 'Replaced with customer name'),
  ('{{time}}', 'Replaced with scheduled time'),
  ('{{date}}', 'Replaced with scheduled date'),
  ('{{duration}}', 'Replaced with call duration'),
  ('{{type}}', 'Replaced with call type (video/audio)'),
  ('{{status}}', 'Replaced with call status'),
  ('{{link}}', 'Replaced with video call link');

-- Insert default voice templates
INSERT INTO voice_templates (name, voice_uri, language, pitch, rate, volume, is_default)
VALUES 
  ('Default Hindi', 'Microsoft Swara', 'hi-IN', 1, 1, 1, true),
  ('Professional Hindi', 'Microsoft Madhur', 'hi-IN', 1.1, 0.9, 1, false),
  ('Casual Hindi', 'Microsoft Hemant', 'hi-IN', 0.9, 1.1, 1, false);

-- Insert default scenario templates
INSERT INTO scenario_templates (name, voice_template_id, template_text, context, priority)
SELECT 
  'Professional Meeting',
  id,
  'Hello {{staff}}, you have a professional video call scheduled with {{customer}} at {{time}} on {{date}}. Please ensure you are ready 5 minutes before the scheduled time.',
  'For formal business meetings and presentations',
  1
FROM voice_templates
WHERE name = 'Professional Hindi';

INSERT INTO scenario_templates (name, voice_template_id, template_text, context, priority)
SELECT 
  'Casual Conversation',
  id,
  'Hi {{staff}}, {{customer}} will be joining you for a video call in 5 minutes. The call is scheduled for {{time}}.',
  'For informal discussions and customer interactions',
  2
FROM voice_templates
WHERE name = 'Casual Hindi';

-- Add helpful comments
COMMENT ON TABLE voice_templates IS 'Stores voice configuration templates for video calls';
COMMENT ON TABLE scenario_templates IS 'Stores scenario-specific voice settings and context';
COMMENT ON TABLE template_tags IS 'Stores available template tags for scenario templates';
COMMENT ON TABLE scenario_template_tags IS 'Links scenario templates with their used tags';
COMMENT ON COLUMN voice_templates.voice_uri IS 'URI identifier for the specific voice to use';
COMMENT ON COLUMN voice_templates.pitch IS 'Voice pitch (0.5 to 2.0)';
COMMENT ON COLUMN voice_templates.rate IS 'Speech rate (0.5 to 2.0)';
COMMENT ON COLUMN voice_templates.volume IS 'Voice volume (0 to 1)';
COMMENT ON COLUMN scenario_templates.priority IS 'Order in which templates appear (lower numbers first)';
COMMENT ON COLUMN scenario_templates.template_text IS 'Template text with placeholders that will be replaced with actual values';