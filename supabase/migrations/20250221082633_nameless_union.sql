-- Drop existing policies
DROP POLICY IF EXISTS "Allow public read access on manufacturer_analytics" ON manufacturer_analytics;

-- Create more granular policies
CREATE POLICY "Allow insert access on manufacturer_analytics"
  ON manufacturer_analytics
  FOR INSERT
  TO public
  WITH CHECK (true);

CREATE POLICY "Allow update access on manufacturer_analytics"
  ON manufacturer_analytics
  FOR UPDATE
  TO public
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow select access on manufacturer_analytics"
  ON manufacturer_analytics
  FOR SELECT
  TO public
  USING (true);

CREATE POLICY "Allow delete access on manufacturer_analytics"
  ON manufacturer_analytics
  FOR DELETE
  TO public
  USING (true);

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_manufacturer_analytics_updated 
  ON manufacturer_analytics(updated_at);

-- Add helpful comment
COMMENT ON TABLE manufacturer_analytics IS 'Stores manufacturer analytics data with full public access for development.';