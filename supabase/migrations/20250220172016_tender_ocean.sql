-- Drop existing functions first
DROP FUNCTION IF EXISTS format_phone_number(text, text);
DROP FUNCTION IF EXISTS format_phone_before_save();

-- First check and drop existing constraints and indexes
DO $$ 
BEGIN
  -- Drop email constraint if it exists
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'customers_email_key'
    AND table_name = 'customers'
  ) THEN
    ALTER TABLE customers DROP CONSTRAINT customers_email_key;
  END IF;

  -- Drop phone constraint if it exists
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'customers_phone_key'
    AND table_name = 'customers'
  ) THEN
    ALTER TABLE customers DROP CONSTRAINT customers_phone_key;
  END IF;

  -- Drop existing indexes if they exist
  IF EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE indexname = 'customers_email_unique'
  ) THEN
    DROP INDEX customers_email_unique;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE indexname = 'idx_customers_phone'
  ) THEN
    DROP INDEX idx_customers_phone;
  END IF;
END $$;

-- Make email nullable
ALTER TABLE customers
  ALTER COLUMN email DROP NOT NULL;

-- Add unique constraint for phone
ALTER TABLE customers
  ADD CONSTRAINT customers_phone_key UNIQUE (phone);

-- Create function to format phone numbers
CREATE FUNCTION format_phone_number(phone text, country_code text)
RETURNS text AS $$
DECLARE
  clean_number text;
  country_prefix text;
BEGIN
  -- Remove all non-digit characters
  clean_number := regexp_replace(phone, '\D', '', 'g');
  
  -- Get country prefix
  country_prefix := CASE country_code
    WHEN 'IN' THEN '91'
    WHEN 'US' THEN '1'
    WHEN 'GB' THEN '44'
    ELSE NULL
  END;

  -- If number already includes country code, use it as is
  IF phone LIKE '+%' THEN
    RETURN phone;
  END IF;

  -- Add country code
  IF country_prefix IS NOT NULL THEN
    RETURN '+' || country_prefix || clean_number;
  END IF;

  -- Default case: just add + if not present
  RETURN CASE 
    WHEN phone LIKE '+%' THEN phone
    ELSE '+' || clean_number
  END;
END;
$$ LANGUAGE plpgsql;

-- Create trigger function for phone formatting
CREATE FUNCTION format_phone_before_save()
RETURNS TRIGGER AS $$
BEGIN
  -- Format phone number
  NEW.phone := format_phone_number(NEW.phone, NEW.country_code);
  
  -- Clean up email
  IF NEW.email = '' THEN
    NEW.email := NULL;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS format_phone_trigger ON customers;
CREATE TRIGGER format_phone_trigger
  BEFORE INSERT OR UPDATE
  ON customers
  FOR EACH ROW
  EXECUTE FUNCTION format_phone_before_save();

-- Add indexes for better performance
CREATE UNIQUE INDEX customers_email_unique 
  ON customers (email)
  WHERE email IS NOT NULL;

CREATE INDEX idx_customers_phone 
  ON customers(phone);

-- Clean up existing data
UPDATE customers SET email = NULL WHERE email = '';
UPDATE customers SET phone = format_phone_number(phone, country_code);

-- Add helpful comments
COMMENT ON COLUMN customers.email IS 'Optional email address. Must be unique when provided.';
COMMENT ON COLUMN customers.phone IS 'Required phone number with country code. Must be unique.';