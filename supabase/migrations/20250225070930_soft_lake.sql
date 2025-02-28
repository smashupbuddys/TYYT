-- Create template_tags table if it doesn't exist
CREATE TABLE IF NOT EXISTS template_tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  description text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE template_tags ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Enable read access for all users" ON template_tags;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON template_tags;
DROP POLICY IF EXISTS "Enable update for authenticated users" ON template_tags;
DROP POLICY IF EXISTS "Enable delete for authenticated users" ON template_tags;

-- Create simplified policies that allow all operations
CREATE POLICY "Allow all operations on template_tags"
  ON template_tags
  FOR ALL
  TO public
  USING (true)
  WITH CHECK (true);

-- Add index for better performance
CREATE INDEX IF NOT EXISTS idx_template_tags_name ON template_tags(name);

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
ON CONFLICT (name) DO UPDATE
SET description = EXCLUDED.description;

-- Add helpful comment
COMMENT ON TABLE template_tags IS 'Stores available template tags for scenario templates with public access';