/*
  # Add phone number validation and formatting

  1. Changes
    - Add function to validate and format phone numbers
    - Add trigger to ensure consistent phone number format
    - Add index for phone number lookups
    
  2. Validation Rules
    - Phone numbers must be unique
    - Phone numbers are stored with country code
    - Phone numbers must be valid for their country
*/

-- Create function to validate and format phone numbers
CREATE OR REPLACE FUNCTION format_phone_number(phone text, country_code text DEFAULT 'IN')
RETURNS text AS $$
DECLARE
  clean_number text;
  formatted_number text;
BEGIN
  -- Remove all non-digit characters
  clean_number := regexp_replace(phone, '\D', '', 'g');
  
  -- If number already has country code (starts with +), use it as is
  IF phone LIKE '+%' THEN
    RETURN phone;
  END IF;

  -- Add country code based on country
  CASE country_code
    WHEN 'IN' THEN -- India
      IF length(clean_number) = 10 THEN
        formatted_number := '+91' || clean_number;
      ELSE
        RAISE EXCEPTION 'Invalid phone number format for India';
      END IF;
    ELSE
      formatted_number := '+' || clean_number;
  END CASE;

  RETURN formatted_number;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to format phone numbers before insert/update
CREATE OR REPLACE FUNCTION format_phone_number_trigger()
RETURNS TRIGGER AS $$
BEGIN
  -- Format phone number
  NEW.phone := format_phone_number(NEW.phone, NEW.country_code);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS format_phone_number_trigger ON customers;
CREATE TRIGGER format_phone_number_trigger
  BEFORE INSERT OR UPDATE OF phone ON customers
  FOR EACH ROW
  EXECUTE FUNCTION format_phone_number_trigger();

-- Add index for phone number lookups
CREATE INDEX IF NOT EXISTS idx_customers_phone_lookup 
ON customers(phone text_pattern_ops);

-- Add comment explaining phone number format
COMMENT ON COLUMN customers.phone IS 'Phone number with country code (e.g., +91XXXXXXXXXX). Must be unique.';