/*
  # Update GST Settings

  1. Changes
    - Remove category requirement from GST rates
    - Make rate the only required field
    - Add default GST rate
    - Update existing data

  2. Security
    - Maintain existing RLS policies
*/

-- Modify gst_rates table
ALTER TABLE gst_rates
  ALTER COLUMN category DROP NOT NULL,
  ALTER COLUMN hsn_code DROP NOT NULL,
  ALTER COLUMN rate SET DEFAULT 18;

-- Update existing records to use default rate if needed
UPDATE gst_rates
SET rate = 18
WHERE rate IS NULL;

-- Add constraint to ensure rate is between 0 and 100
ALTER TABLE gst_rates
  DROP CONSTRAINT IF EXISTS gst_rates_rate_check,
  ADD CONSTRAINT gst_rates_rate_check 
  CHECK (rate >= 0 AND rate <= 100);

-- Insert default GST rate if table is empty
INSERT INTO gst_rates (rate, description)
SELECT 18, 'Default GST rate'
WHERE NOT EXISTS (SELECT 1 FROM gst_rates);

-- Create or replace function to get GST rate
CREATE OR REPLACE FUNCTION get_gst_rate(category text DEFAULT NULL)
RETURNS numeric AS $$
BEGIN
  -- First try to find a rate for the specific category
  RETURN COALESCE(
    (SELECT rate FROM gst_rates WHERE category = $1 LIMIT 1),
    (SELECT rate FROM gst_rates WHERE category IS NULL ORDER BY created_at DESC LIMIT 1),
    18
  );
END;
$$ LANGUAGE plpgsql;