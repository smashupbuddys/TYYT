/*
  # Fix timezone columns in video_calls table

  1. Changes
    - Add timezone columns with proper defaults
    - Add function for timezone conversion
    - Update existing records
*/

-- Add timezone columns if they don't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'video_calls' AND column_name = 'time_zone'
  ) THEN
    ALTER TABLE video_calls
      ADD COLUMN time_zone text DEFAULT 'UTC',
      ADD COLUMN customer_time_zone text,
      ADD COLUMN time_zone_offset integer;
  END IF;
END $$;

-- Update existing records to use UTC
UPDATE video_calls
SET time_zone = 'UTC'
WHERE time_zone IS NULL;

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

-- Create index for better performance
CREATE INDEX IF NOT EXISTS idx_video_calls_time_zone 
ON video_calls(time_zone);

-- Add trigger to update time_zone_offset when timezones change
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

DROP TRIGGER IF EXISTS video_calls_timezone_trigger ON video_calls;

CREATE TRIGGER video_calls_timezone_trigger
  BEFORE INSERT OR UPDATE OF time_zone, customer_time_zone, scheduled_at
  ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION update_timezone_offset();