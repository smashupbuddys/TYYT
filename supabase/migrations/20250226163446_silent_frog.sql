-- Drop existing function
DROP FUNCTION IF EXISTS get_markup_settings();

-- Create simplified function that returns a table
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

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_markup_settings() TO PUBLIC;

-- Add helpful comment
COMMENT ON FUNCTION get_markup_settings IS 'Gets all markup settings ordered by type and name';

-- Ensure the markup_settings table exists and has the correct schema
CREATE TABLE IF NOT EXISTS markup_settings (
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

-- Ensure default data exists
INSERT INTO markup_settings (type, name, code, markup) VALUES
  ('manufacturer', 'Cartier', 'PJ02', 0.30),
  ('manufacturer', 'Mohini', 'MO07', 0.25),
  ('manufacturer', 'DS BHAI', 'PJ01', 0.25),
  ('manufacturer', 'SUHAG', 'PJ03', 0.25),
  ('manufacturer', 'SGJ', 'PJ04', 0.25),
  ('category', 'Rings', 'RG', 0.25),
  ('category', 'Necklaces', 'NE', 0.30),
  ('category', 'Earrings', 'ER', 0.28),
  ('category', 'Bracelets', 'BR', 0.32),
  ('category', 'Watches', 'WT', 0.40),
  ('category', 'Pendants', 'PE', 0.30)
ON CONFLICT (type, name) DO UPDATE
SET code = EXCLUDED.code,
    markup = EXCLUDED.markup;

-- Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';