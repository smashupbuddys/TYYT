/*
  # Add country code and timezone support

  1. Changes
    - Add country_code and timezone columns to customers table
    - Add time_zone, customer_time_zone, and time_zone_offset columns to video_calls table
    - Add indexes for better performance
    - Set default values for existing records

  2. Security
    - Maintain existing RLS policies
*/

-- Add country and timezone columns to customers
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS country_code text DEFAULT 'IN',
  ADD COLUMN IF NOT EXISTS timezone text DEFAULT 'Asia/Kolkata';

-- Add timezone columns to video_calls
ALTER TABLE video_calls
  ADD COLUMN IF NOT EXISTS time_zone text DEFAULT 'Asia/Kolkata',
  ADD COLUMN IF NOT EXISTS customer_time_zone text,
  ADD COLUMN IF NOT EXISTS time_zone_offset integer;

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_customers_country_code ON customers(country_code);
CREATE INDEX IF NOT EXISTS idx_video_calls_time_zone ON video_calls(time_zone);

-- Create function to handle timezone conversions
CREATE OR REPLACE FUNCTION convert_timezone(
  source_time timestamptz,
  source_zone text,
  target_zone text
) RETURNS timestamptz AS $$
BEGIN
  RETURN source_time AT TIME ZONE source_zone AT TIME ZONE target_zone;
END;
$$ LANGUAGE plpgsql;

-- Create function to update timezone offset
CREATE OR REPLACE FUNCTION update_timezone_offset()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.time_zone IS NOT NULL AND NEW.customer_time_zone IS NOT NULL THEN
    -- Calculate offset in minutes
    NEW.time_zone_offset := EXTRACT(EPOCH FROM (
      NEW.scheduled_at AT TIME ZONE NEW.customer_time_zone -
      NEW.scheduled_at AT TIME ZONE NEW.time_zone
    ))::integer / 60;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for timezone offset updates
DROP TRIGGER IF EXISTS video_calls_timezone_trigger ON video_calls;

CREATE TRIGGER video_calls_timezone_trigger
  BEFORE INSERT OR UPDATE OF time_zone, customer_time_zone, scheduled_at
  ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION update_timezone_offset();

-- Update existing records with default values
UPDATE customers
SET 
  country_code = 'IN',
  timezone = 'Asia/Kolkata'
WHERE country_code IS NULL;

UPDATE video_calls v
SET
  time_zone = 'Asia/Kolkata',
  customer_time_zone = COALESCE(
    (SELECT timezone FROM customers WHERE id = v.customer_id),
    'Asia/Kolkata'
  )
WHERE time_zone IS NULL;