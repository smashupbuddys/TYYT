/*
  # Fix Video Calls Schema and Validation

  1. Changes
    - Add unique constraint for video call number
    - Add video call number generation
    - Fix staff ID handling
    - Add proper indexes

  2. Security
    - Maintain existing RLS policies
    - Add proper constraints
*/

-- Add video call number column if it doesn't exist
ALTER TABLE video_calls
  ADD COLUMN IF NOT EXISTS video_call_number text;

-- Create function to generate video call number
CREATE OR REPLACE FUNCTION generate_video_call_number()
RETURNS text AS $$
DECLARE
  new_number text;
  attempts integer := 0;
  max_attempts constant integer := 5;
BEGIN
  LOOP
    -- Generate number in format: VC-YYYYMMDD-XXX
    new_number := 'VC-' || 
                  to_char(CURRENT_DATE, 'YYYYMMDD') || '-' ||
                  LPAD(floor(random() * 1000)::text, 3, '0');
    
    -- Check if number already exists
    IF NOT EXISTS (
      SELECT 1 FROM video_calls 
      WHERE video_call_number = new_number
    ) THEN
      RETURN new_number;
    END IF;
    
    attempts := attempts + 1;
    IF attempts >= max_attempts THEN
      RAISE EXCEPTION 'Could not generate unique video call number after % attempts', max_attempts;
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create function to set video call number before insert
CREATE OR REPLACE FUNCTION set_video_call_number()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.video_call_number IS NULL THEN
    NEW.video_call_number := generate_video_call_number();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to set video call number
CREATE TRIGGER set_video_call_number_trigger
  BEFORE INSERT ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION set_video_call_number();

-- Add unique constraint for video call number
ALTER TABLE video_calls
  ADD CONSTRAINT video_calls_number_key UNIQUE (video_call_number);

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_video_calls_staff_id ON video_calls(staff_id);
CREATE INDEX IF NOT EXISTS idx_video_calls_customer_id ON video_calls(customer_id);
CREATE INDEX IF NOT EXISTS idx_video_calls_scheduled_at ON video_calls(scheduled_at);
CREATE INDEX IF NOT EXISTS idx_video_calls_status ON video_calls(status);

-- Update existing records with video call numbers
DO $$
DECLARE
  v_call record;
BEGIN
  FOR v_call IN SELECT id FROM video_calls WHERE video_call_number IS NULL
  LOOP
    UPDATE video_calls
    SET video_call_number = generate_video_call_number()
    WHERE id = v_call.id;
  END LOOP;
END $$;

-- Add helpful comment
COMMENT ON TABLE video_calls IS 'Stores video call appointments with unique call numbers and proper validation.';