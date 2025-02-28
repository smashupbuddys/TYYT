/*
  # Create Markup Settings Table

  1. New Tables
    - markup_settings
      - id (uuid, primary key)
      - type (text, either 'manufacturer' or 'category')
      - name (text)
      - markup (numeric)
      - created_at (timestamptz)
      - updated_at (timestamptz)

  2. Security
    - Enable RLS
    - Add policies for public access
*/

-- Create markup_settings table
CREATE TABLE IF NOT EXISTS markup_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL CHECK (type IN ('manufacturer', 'category')),
  name text NOT NULL,
  markup numeric NOT NULL CHECK (markup >= 0 AND markup <= 1),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_markup_settings_type_name ON markup_settings(type, name);

-- Enable RLS
ALTER TABLE markup_settings ENABLE ROW LEVEL SECURITY;

-- Create policies with existence checks
DO $$ 
BEGIN
  -- Check and create read policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'markup_settings' AND policyname = 'Allow public read access on markup_settings'
  ) THEN
    CREATE POLICY "Allow public read access on markup_settings"
      ON markup_settings FOR SELECT TO public USING (true);
  END IF;

  -- Check and create insert policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'markup_settings' AND policyname = 'Allow public insert access on markup_settings'
  ) THEN
    CREATE POLICY "Allow public insert access on markup_settings"
      ON markup_settings FOR INSERT TO public WITH CHECK (true);
  END IF;

  -- Check and create update policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'markup_settings' AND policyname = 'Allow public update access on markup_settings'
  ) THEN
    CREATE POLICY "Allow public update access on markup_settings"
      ON markup_settings FOR UPDATE TO public USING (true) WITH CHECK (true);
  END IF;

  -- Check and create delete policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'markup_settings' AND policyname = 'Allow public delete access on markup_settings'
  ) THEN
    CREATE POLICY "Allow public delete access on markup_settings"
      ON markup_settings FOR DELETE TO public USING (true);
  END IF;
END $$;

-- Insert default markup settings
INSERT INTO markup_settings (type, name, markup) VALUES
  -- Manufacturer markups
  ('manufacturer', 'Cartier', 0.30),
  ('manufacturer', 'Tiffany', 0.35),
  ('manufacturer', 'Pandora', 0.25),
  ('manufacturer', 'Swarovski', 0.28),
  ('manufacturer', 'Local', 0.20),
  -- Category markups
  ('category', 'Rings', 0.25),
  ('category', 'Necklaces', 0.30),
  ('category', 'Earrings', 0.28),
  ('category', 'Bracelets', 0.32),
  ('category', 'Watches', 0.40)
ON CONFLICT DO NOTHING;