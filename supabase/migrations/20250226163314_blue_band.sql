-- Drop existing RPC function if it exists
DROP FUNCTION IF EXISTS get_markup_settings();

-- Create improved RPC function with proper return type
CREATE OR REPLACE FUNCTION get_markup_settings()
RETURNS SETOF markup_settings 
LANGUAGE sql SECURITY DEFINER
STABLE -- Add STABLE modifier to improve caching
AS $$
  SELECT * FROM markup_settings ORDER BY type, name;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_markup_settings() TO PUBLIC;

-- Add helpful comment
COMMENT ON FUNCTION get_markup_settings IS 'Gets all markup settings ordered by type and name';

-- Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';