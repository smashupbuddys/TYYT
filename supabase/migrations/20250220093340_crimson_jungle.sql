/*
  # Add video call settings

  1. Changes
    - Add video_call_settings column to company_settings table
    - Add default values for video call settings
    - Add validation function for video call settings
*/

-- Add video call settings to company_settings
ALTER TABLE company_settings
  ADD COLUMN IF NOT EXISTS video_call_settings jsonb DEFAULT '{
    "allow_retail": true,
    "allow_wholesale": true,
    "retail_notice_hours": 24,
    "wholesale_notice_hours": 48
  }';

-- Create function to validate video call settings
CREATE OR REPLACE FUNCTION validate_video_call_settings()
RETURNS TRIGGER AS $$
BEGIN
  -- Ensure all required fields are present
  IF NOT (
    NEW.video_call_settings ? 'allow_retail' AND
    NEW.video_call_settings ? 'allow_wholesale' AND
    NEW.video_call_settings ? 'retail_notice_hours' AND
    NEW.video_call_settings ? 'wholesale_notice_hours'
  ) THEN
    RAISE EXCEPTION 'Video call settings must include all required fields';
  END IF;

  -- Validate notice hours
  IF (NEW.video_call_settings->>'retail_notice_hours')::integer < 0 OR
     (NEW.video_call_settings->>'wholesale_notice_hours')::integer < 0 THEN
    RAISE EXCEPTION 'Notice hours must be non-negative';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for video call settings validation
DROP TRIGGER IF EXISTS validate_video_call_settings_trigger ON company_settings;

CREATE TRIGGER validate_video_call_settings_trigger
  BEFORE INSERT OR UPDATE OF video_call_settings
  ON company_settings
  FOR EACH ROW
  EXECUTE FUNCTION validate_video_call_settings();

-- Update existing records with default settings
UPDATE company_settings
SET video_call_settings = '{
  "allow_retail": true,
  "allow_wholesale": true,
  "retail_notice_hours": 24,
  "wholesale_notice_hours": 48
}'::jsonb
WHERE video_call_settings IS NULL;