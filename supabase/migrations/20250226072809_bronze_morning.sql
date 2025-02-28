-- Create markup_settings table if it doesn't exist
CREATE TABLE IF NOT EXISTS markup_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL CHECK (type IN ('manufacturer', 'category')),
  name text NOT NULL,
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
  ON markup_settings FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on markup_settings"
  ON markup_settings FOR UPDATE TO public USING (true);

CREATE POLICY "Allow public delete access on markup_settings"
  ON markup_settings FOR DELETE TO public USING (true);

-- Add unique constraint for type + name combination
ALTER TABLE markup_settings
  ADD CONSTRAINT markup_settings_type_name_key UNIQUE (type, name);

-- Add indexes for better performance
CREATE INDEX idx_markup_settings_type ON markup_settings(type);
CREATE INDEX idx_markup_settings_name ON markup_settings(name);

-- Insert default manufacturer markup settings
INSERT INTO markup_settings (type, name, markup) VALUES
  ('manufacturer', 'Cartier', 0.30),
  ('manufacturer', 'Tiffany', 0.35),
  ('manufacturer', 'Pandora', 0.25),
  ('manufacturer', 'Swarovski', 0.28),
  ('manufacturer', 'Local', 0.20)
ON CONFLICT (type, name) DO UPDATE
SET markup = EXCLUDED.markup;

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
COMMENT ON TABLE markup_settings IS 'Stores markup percentages for manufacturers and categories';
COMMENT ON FUNCTION get_product_markup IS 'Gets the appropriate markup percentage for a product based on manufacturer or category';