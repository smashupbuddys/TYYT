-- Drop existing markup_settings table and recreate with proper schema
DROP TABLE IF EXISTS markup_settings CASCADE;

CREATE TABLE markup_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL CHECK (type IN ('manufacturer', 'category')),
  name text NOT NULL,
  code text NOT NULL, -- Make code required
  markup numeric NOT NULL CHECK (markup >= 0 AND markup <= 1),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE markup_settings ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on markup_settings"
  ON markup_settings FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on markup_settings"
  FOR INSERT ON markup_settings
  TO public
  WITH CHECK (true);

CREATE POLICY "Allow public update access on markup_settings"
  FOR UPDATE ON markup_settings
  TO public
  USING (true)
  WITH CHECK (true);

-- Add unique constraints
ALTER TABLE markup_settings
  ADD CONSTRAINT markup_settings_type_name_key UNIQUE (type, name),
  ADD CONSTRAINT markup_settings_manufacturer_code_key UNIQUE (code) 
  WHERE type = 'manufacturer';

-- Insert manufacturers with proper codes
INSERT INTO markup_settings (type, name, code, markup) VALUES
  ('manufacturer', 'Cartier', 'CA02', 0.30),
  ('manufacturer', 'Mohini', 'MO01', 0.25),
  ('manufacturer', 'DS BHAI', 'DS01', 0.25),
  ('manufacturer', 'SUHAG', 'SU01', 0.25),
  ('manufacturer', 'SGJ', 'SG01', 0.25)
ON CONFLICT (type, name) DO UPDATE
SET code = EXCLUDED.code,
    markup = EXCLUDED.markup;

-- Insert categories
INSERT INTO markup_settings (type, name, code, markup) VALUES
  ('category', 'Rings', 'RG', 0.25),
  ('category', 'Necklaces', 'NK', 0.30),
  ('category', 'Earrings', 'ER', 0.28),
  ('category', 'Bracelets', 'BR', 0.32),
  ('category', 'Watches', 'WT', 0.40)
ON CONFLICT (type, name) DO UPDATE
SET code = EXCLUDED.code,
    markup = EXCLUDED.markup;

-- Create function to get markup for product
CREATE OR REPLACE FUNCTION get_product_markup(
  p_manufacturer text,
  p_category text
)
RETURNS numeric AS $$
DECLARE
  v_manufacturer_markup numeric;
  v_category_markup numeric;
BEGIN
  -- Get manufacturer markup
  SELECT markup INTO v_manufacturer_markup
  FROM markup_settings
  WHERE type = 'manufacturer' AND name = p_manufacturer;

  -- Get category markup
  SELECT markup INTO v_category_markup
  FROM markup_settings
  WHERE type = 'category' AND name = p_category;

  -- Return manufacturer markup if available, otherwise category markup, or default 0.2 (20%)
  RETURN COALESCE(v_manufacturer_markup, v_category_markup, 0.2);
END;
$$ LANGUAGE plpgsql;

-- Add helpful comments
COMMENT ON TABLE markup_settings IS 'Stores markup percentages and manufacturer codes using manufacturer initials (e.g., CA02 for Cartier, DS01 for DS BHAI)';
COMMENT ON COLUMN markup_settings.code IS 'Required code for manufacturers (e.g., CA02) and categories (e.g., RG)';
COMMENT ON FUNCTION get_product_markup IS 'Gets the appropriate markup percentage for a product based on manufacturer or category';