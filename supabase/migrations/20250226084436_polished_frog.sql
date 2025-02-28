-- Add code column to markup_settings table if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'markup_settings' AND column_name = 'code'
  ) THEN
    ALTER TABLE markup_settings
      ADD COLUMN code text;
  END IF;
END $$;

-- Update existing manufacturer records with codes
UPDATE markup_settings
SET code = CASE name
  WHEN 'Cartier' THEN 'PJ02'
  WHEN 'Tiffany' THEN 'PJ03'
  WHEN 'Pandora' THEN 'PJ04'
  WHEN 'Swarovski' THEN 'PJ05'
  WHEN 'Local' THEN 'PJ01'
  ELSE 'PJ' || LPAD(FLOOR(RANDOM() * 99 + 1)::text, 2, '0')
END
WHERE type = 'manufacturer' AND (code IS NULL OR code = '');

-- Add unique constraint for manufacturer codes
ALTER TABLE markup_settings
  ADD CONSTRAINT markup_settings_manufacturer_code_key 
  UNIQUE (code) 
  WHERE type = 'manufacturer';

-- Create function to generate manufacturer code
CREATE OR REPLACE FUNCTION generate_manufacturer_code(name text)
RETURNS text AS $$
DECLARE
  counter integer := 1;
  final_code text;
BEGIN
  -- Generate base code in format PJxx
  final_code := 'PJ' || LPAD(counter::text, 2, '0');
  
  -- Try to find unique code
  WHILE EXISTS (
    SELECT 1 FROM markup_settings 
    WHERE type = 'manufacturer' AND code = final_code
  ) LOOP
    counter := counter + 1;
    final_code := 'PJ' || LPAD(counter::text, 2, '0');
    
    -- Prevent infinite loop
    IF counter > 99 THEN
      RAISE EXCEPTION 'No available manufacturer codes';
    END IF;
  END LOOP;
  
  RETURN final_code;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically generate manufacturer code
CREATE OR REPLACE FUNCTION set_manufacturer_code()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.type = 'manufacturer' AND (NEW.code IS NULL OR NEW.code = '') THEN
    NEW.code := generate_manufacturer_code(NEW.name);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for auto-generating codes
DROP TRIGGER IF EXISTS set_manufacturer_code_trigger ON markup_settings;
CREATE TRIGGER set_manufacturer_code_trigger
  BEFORE INSERT OR UPDATE ON markup_settings
  FOR EACH ROW
  WHEN (NEW.type = 'manufacturer')
  EXECUTE FUNCTION set_manufacturer_code();

-- Add helpful comments
COMMENT ON COLUMN markup_settings.code IS 'Manufacturer code in format PJxx (e.g., PJ01 for Local)';
COMMENT ON FUNCTION generate_manufacturer_code IS 'Generates a unique manufacturer code in format PJxx';