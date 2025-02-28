-- Add code column to markup_settings table
ALTER TABLE markup_settings
  ADD COLUMN code text;

-- Update existing manufacturer records with codes
UPDATE markup_settings
SET code = CASE name
  WHEN 'Cartier' THEN 'CART'
  WHEN 'Tiffany' THEN 'TIFF'
  WHEN 'Pandora' THEN 'PAND'
  WHEN 'Swarovski' THEN 'SWAR'
  WHEN 'Local' THEN 'LOCAL'
  ELSE UPPER(SUBSTRING(name FROM 1 FOR 4))
END
WHERE type = 'manufacturer';

-- Add unique constraint for manufacturer codes
ALTER TABLE markup_settings
  ADD CONSTRAINT markup_settings_manufacturer_code_key 
  UNIQUE (code) 
  WHERE type = 'manufacturer';

-- Create function to generate manufacturer code
CREATE OR REPLACE FUNCTION generate_manufacturer_code(name text)
RETURNS text AS $$
DECLARE
  base_code text;
  counter integer := 0;
  final_code text;
BEGIN
  -- Generate base code from first 4 letters
  base_code := UPPER(SUBSTRING(REGEXP_REPLACE(name, '[^a-zA-Z]', '', 'g') FROM 1 FOR 4));
  
  -- Ensure base code is at least 2 characters
  IF LENGTH(base_code) < 2 THEN
    base_code := RPAD(base_code, 2, 'X');
  END IF;
  
  -- Try to find unique code
  final_code := base_code;
  WHILE EXISTS (
    SELECT 1 FROM markup_settings 
    WHERE type = 'manufacturer' AND code = final_code
  ) LOOP
    counter := counter + 1;
    final_code := base_code || LPAD(counter::text, 2, '0');
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

CREATE TRIGGER set_manufacturer_code_trigger
  BEFORE INSERT OR UPDATE ON markup_settings
  FOR EACH ROW
  WHEN (NEW.type = 'manufacturer')
  EXECUTE FUNCTION set_manufacturer_code();

-- Add helpful comments
COMMENT ON COLUMN markup_settings.code IS 'Unique code for manufacturers (e.g., CART for Cartier)';
COMMENT ON FUNCTION generate_manufacturer_code IS 'Generates a unique code for manufacturers based on their name';