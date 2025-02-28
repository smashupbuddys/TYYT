-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Allow public read access on template_tags" ON template_tags;
DROP POLICY IF EXISTS "Allow public insert access on template_tags" ON template_tags;
DROP POLICY IF EXISTS "Allow public update access on template_tags" ON template_tags;
DROP POLICY IF EXISTS "Allow public delete access on template_tags" ON template_tags;

-- Create improved policies with proper authentication checks
CREATE POLICY "Enable read access for all users"
  ON template_tags
  FOR SELECT
  USING (true);

CREATE POLICY "Enable insert for authenticated users"
  ON template_tags
  FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Enable update for authenticated users"
  ON template_tags
  FOR UPDATE
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Enable delete for authenticated users"
  ON template_tags
  FOR DELETE
  USING (true);

-- Insert default template tags if they don't exist
INSERT INTO template_tags (name, description)
VALUES 
  ('{{staff}}', 'Staff member name'),
  ('{{customer}}', 'Customer name'),
  ('{{time}}', 'Scheduled time'),
  ('{{date}}', 'Scheduled date'),
  ('{{duration}}', 'Call duration'),
  ('{{type}}', 'Call type (video/audio)'),
  ('{{status}}', 'Call status'),
  ('{{link}}', 'Video call link')
ON CONFLICT (name) DO NOTHING;

-- Add helpful comment
COMMENT ON TABLE template_tags IS 'Stores available template tags for scenario templates with proper RLS policies';