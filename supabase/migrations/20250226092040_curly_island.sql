-- Drop existing markup_settings table and recreate with proper schema
DROP TABLE IF EXISTS markup_settings CASCADE;

CREATE TABLE markup_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL CHECK (type IN ('manufacturer', 'category')),
  name text NOT NULL,
  code text,
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

-- Insert default manufacturer markup settings with proper codes
INSERT INTO markup_settings (type, name, code, markup) VALUES
  ('manufacturer', 'Cartier', 'PJ02', 0.30),
  ('manufacturer', 'Tiffany', 'PJ03', 0.35),
  ('manufacturer', 'Pandora', 'PJ04', 0.25),
  ('manufacturer', 'Swarovski', 'PJ05', 0.28),
  ('manufacturer', 'Local', 'PJ01', 0.20),
  ('manufacturer', 'Mohini', 'MO07', 0.25)
ON CONFLICT (type, name) DO UPDATE
SET code = EXCLUDED.code,
    markup = EXCLUDED.markup;

-- Insert default category markup settings
INSERT INTO markup_settings (type, name, markup) VALUES
  ('category', 'Rings', 0.25),
  ('category', 'Necklaces', 0.30),
  ('category', 'Earrings', 0.28),
  ('category', 'Bracelets', 0.32),
  ('category', 'Watches', 0.40)
ON CONFLICT (type, name) DO UPDATE
SET markup = EXCLUDED.markup;

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
COMMENT ON TABLE markup_settings IS 'Stores markup percentages and manufacturer codes';
COMMENT ON COLUMN markup_settings.code IS 'Unique code for manufacturers used in SKU generation';
COMMENT ON FUNCTION get_product_markup IS 'Gets the appropriate markup percentage for a product based on manufacturer or category';