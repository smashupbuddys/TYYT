-- Create RPC function to get markup settings
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
  SELECT 
    ms.id,
    ms.type,
    ms.name,
    ms.code,
    ms.markup,
    ms.created_at,
    ms.updated_at
  FROM markup_settings ms
  ORDER BY ms.type, ms.name;
END;
$$ LANGUAGE plpgsql;

-- Add helpful comment
COMMENT ON FUNCTION get_markup_settings IS 'Gets all markup settings ordered by type and name';