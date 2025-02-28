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
ALTER TABLE template_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE scenario_template_tags ENABLE ROW LEVEL SECURITY;

-- Create policies
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

-- Add indexes for better performance
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

-- Add template_text column to scenario_templates
ALTER TABLE scenario_templates
  ADD COLUMN template_text text;

-- Update existing scenario templates with template text
UPDATE scenario_templates
SET template_text = CASE
  WHEN name = 'Professional Meeting' THEN
    'Hello {{staff}}, you have a professional video call scheduled with {{customer}} at {{time}} on {{date}}. Please ensure you are ready 5 minutes before the scheduled time.'
  WHEN name = 'Casual Conversation' THEN
    'Hi {{staff}}, {{customer}} will be joining you for a video call in 5 minutes. The call is scheduled for {{time}}.'
  ELSE
    'Video call with {{customer}} scheduled for {{time}}'
END;

-- Add helpful comments
COMMENT ON TABLE template_tags IS 'Stores available template tags for scenario templates';
COMMENT ON TABLE scenario_template_tags IS 'Links scenario templates with their used tags';
COMMENT ON COLUMN scenario_templates.template_text IS 'Template text with placeholders that will be replaced with actual values';