-- Drop existing RPC function
DROP FUNCTION IF EXISTS get_markup_settings();

-- Create improved RPC function with proper return type
CREATE OR REPLACE FUNCTION get_markup_settings()
RETURNS TABLE (
  id uuid,
  type text,
  name text,
  code text,
  markup numeric,
  created_at timestamptz,
  updated_at timestamptz
) SECURITY DEFINER
LANGUAGE sql AS $$
  SELECT * FROM markup_settings ORDER BY type, name;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_markup_settings() TO PUBLIC;

-- Update manufacturer codes to match required format
UPDATE markup_settings 
SET code = CASE name
  WHEN 'Cartier' THEN 'PJ02'
  WHEN 'Mohini' THEN 'PJ07'
  WHEN 'DS BHAI' THEN 'PJ01'
  WHEN 'SUHAG' THEN 'PJ03'
  WHEN 'SGJ' THEN 'PJ04'
  ELSE code
END
WHERE type = 'manufacturer';

-- Add helpful comment
COMMENT ON FUNCTION get_markup_settings IS 'Gets all markup settings ordered by type and name. Returns full table rows.';