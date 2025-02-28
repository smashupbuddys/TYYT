/*
  # Fix customer table constraints

  1. Changes
    - Make address fields optional in customers table
    - Ensure phone number is unique and required
    - Add appropriate indexes

  2. Security
    - Maintain existing RLS policies
*/

-- Make address fields optional
ALTER TABLE customers
  ALTER COLUMN address DROP NOT NULL,
  ALTER COLUMN city DROP NOT NULL,
  ALTER COLUMN state DROP NOT NULL,
  ALTER COLUMN pincode DROP NOT NULL;

-- Ensure phone number is unique and required
DO $$ 
BEGIN
  -- Drop existing phone constraint if it exists
  IF EXISTS (
    SELECT 1 
    FROM information_schema.table_constraints 
    WHERE constraint_name = 'customers_phone_key'
  ) THEN
    ALTER TABLE customers 
      DROP CONSTRAINT customers_phone_key;
  END IF;

  -- Add unique constraint for phone
  ALTER TABLE customers
    ADD CONSTRAINT customers_phone_key UNIQUE (phone);
END $$;

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone);
CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name);

-- Update any existing records with empty strings to NULL
UPDATE customers 
SET address = NULLIF(address, ''),
    city = NULLIF(city, ''),
    state = NULLIF(state, ''),
    pincode = NULLIF(pincode, '');