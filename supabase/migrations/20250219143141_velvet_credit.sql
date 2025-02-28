/*
  # Add timezone support to video calls

  1. Changes
    - Add time_zone column to video_calls table
    - Add customer_time_zone column to video_calls table
    - Add time_zone_offset column to video_calls table
*/

-- Add timezone columns to video_calls
ALTER TABLE video_calls
  ADD COLUMN IF NOT EXISTS time_zone text,
  ADD COLUMN IF NOT EXISTS customer_time_zone text,
  ADD COLUMN IF NOT EXISTS time_zone_offset integer;

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