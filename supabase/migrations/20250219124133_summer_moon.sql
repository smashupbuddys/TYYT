/*
  # Add Manufacturers Table

  1. New Tables
    - manufacturers
      - id (uuid, primary key)
      - name (text)
      - code (text)
      - active (boolean)
      - created_at (timestamptz)
      - updated_at (timestamptz)

  2. Security
    - Enable RLS
    - Add policies for public access
*/

-- Create manufacturers table
CREATE TABLE IF NOT EXISTS manufacturers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  code text UNIQUE NOT NULL,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_manufacturers_name ON manufacturers(name);
CREATE INDEX IF NOT EXISTS idx_manufacturers_code ON manufacturers(code);

-- Enable RLS
ALTER TABLE manufacturers ENABLE ROW LEVEL SECURITY;

-- Create policies
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'manufacturers' AND policyname = 'Allow public read access on manufacturers'
  ) THEN
    CREATE POLICY "Allow public read access on manufacturers"
      ON manufacturers FOR SELECT TO public USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'manufacturers' AND policyname = 'Allow public insert access on manufacturers'
  ) THEN
    CREATE POLICY "Allow public insert access on manufacturers"
      ON manufacturers FOR INSERT TO public WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'manufacturers' AND policyname = 'Allow public update access on manufacturers'
  ) THEN
    CREATE POLICY "Allow public update access on manufacturers"
      ON manufacturers FOR UPDATE TO public USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Insert default manufacturers
INSERT INTO manufacturers (name, code) VALUES
  ('Cartier', 'CART'),
  ('Tiffany', 'TIFF'),
  ('Pandora', 'PAND'),
  ('Swarovski', 'SWAR'),
  ('Local', 'LOCAL')
ON CONFLICT (code) DO NOTHING;