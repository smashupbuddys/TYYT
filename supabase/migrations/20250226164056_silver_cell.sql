-- Drop existing markup_settings table and recreate with proper schema
DROP TABLE IF EXISTS markup_settings CASCADE;

CREATE TABLE markup_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL CHECK (type IN ('manufacturer', 'category')),
  name text NOT NULL,
  code text NOT NULL,
  markup numeric NOT NULL CHECK (markup >= 0 AND markup <= 1),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT markup_settings_type_name_key UNIQUE (type, name),
  CONSTRAINT markup_settings_manufacturer_code_key UNIQUE (code) 
  WHERE type = 'manufacturer'
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

-- Insert manufacturers with proper codes
INSERT INTO markup_settings (type, name, code, markup) VALUES
  ('manufacturer', 'Cartier', 'PJ02', 0.30),
  ('manufacturer', 'Mohini', 'MO07', 0.25),
  ('manufacturer', 'DS BHAI', 'PJ01', 0.25),
  ('manufacturer', 'SUHAG', 'PJ03', 0.25),
  ('manufacturer', 'SGJ', 'PJ04', 0.25)
ON CONFLICT (type, name) DO UPDATE
SET code = EXCLUDED.code,
    markup = EXCLUDED.markup;

-- Insert categories with proper codes
INSERT INTO markup_settings (type, name, code, markup) VALUES
  ('category', 'Rings', 'RG', 0.25),
  ('category', 'Necklaces', 'NE', 0.30),
  ('category', 'Earrings', 'ER', 0.28),
  ('category', 'Bracelets', 'BR', 0.32),
  ('category', 'Watches', 'WT', 0.40),
  ('category', 'Pendants', 'PE', 0.30)
ON CONFLICT (type, name) DO UPDATE
SET code = EXCLUDED.code,
    markup = EXCLUDED.markup;

-- Create function to get markup settings
CREATE OR REPLACE FUNCTION get_markup_settings()
RETURNS TABLE (
  id uuid,
  type text,
  name text,
  code text,
  markup numeric,
  created_at timestamptz,
  updated_at timestamptz
) AS $$
BEGIN
  RETURN QUERY
  SELECT m.id, m.type, m.name, m.code, m.markup, m.created_at, m.updated_at
  FROM markup_settings m
  ORDER BY m.type, m.name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create function to get manufacturer code
CREATE OR REPLACE FUNCTION get_manufacturer_code(
  p_manufacturer text
)
RETURNS text AS $$
DECLARE
  v_code text;
BEGIN
  -- Get manufacturer code
  SELECT code INTO v_code
  FROM markup_settings
  WHERE type = 'manufacturer' AND name = p_manufacturer;

  IF v_code IS NULL THEN
    RAISE EXCEPTION 'Manufacturer code not found for %', p_manufacturer;
  END IF;

  RETURN v_code;
END;
$$ LANGUAGE plpgsql;

-- Create function to validate SKU before product insert/update
CREATE OR REPLACE FUNCTION validate_product_sku()
RETURNS TRIGGER AS $$
BEGIN
  -- If SKU is not provided, generate it
  IF NEW.sku IS NULL THEN
    -- Get manufacturer code
    DECLARE
      mfr_code text;
    BEGIN
      SELECT code INTO mfr_code
      FROM markup_settings
      WHERE type = 'manufacturer' AND name = NEW.manufacturer;

      IF mfr_code IS NULL THEN
        RAISE EXCEPTION 'Manufacturer code not found for %', NEW.manufacturer;
      END IF;

      -- Generate SKU
      NEW.sku := format('%s/%s-%s-%s',
        NEW.category,
        mfr_code,
        lpad(floor(NEW.retail_price)::text, 4, '0'),
        upper(substring(md5(random()::text) from 1 for 5))
      );
    END;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for SKU validation
DROP TRIGGER IF EXISTS validate_product_sku_trigger ON products;
CREATE TRIGGER validate_product_sku_trigger
  BEFORE INSERT OR UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION validate_product_sku();

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_markup_settings() TO PUBLIC;
GRANT EXECUTE ON FUNCTION get_manufacturer_code(text) TO PUBLIC;

-- Add helpful comments
COMMENT ON TABLE markup_settings IS 'Stores markup percentages and codes for manufacturers and categories';
COMMENT ON FUNCTION get_markup_settings IS 'Gets all markup settings ordered by type and name';
COMMENT ON FUNCTION get_manufacturer_code IS 'Gets the manufacturer code used for SKU generation';
COMMENT ON FUNCTION validate_product_sku IS 'Validates and generates SKUs for products';