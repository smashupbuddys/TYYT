/*
  # Fix email constraint in customers table
  
  1. Changes
    - Drop existing email constraint
    - Make email truly optional
    - Add proper unique constraint
    - Clean up any existing data
  
  2. Indexes
    - Add optimized index for email lookups
    
  3. Notes
    - This migration ensures email uniqueness only when provided
    - Multiple customers can have NULL email
*/

-- First drop any existing email constraints
DO $$ 
BEGIN
  -- Drop the constraint if it exists
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'customers_email_key'
    AND table_name = 'customers'
  ) THEN
    ALTER TABLE customers DROP CONSTRAINT customers_email_key;
  END IF;
END $$;

-- Make email nullable
ALTER TABLE customers
  ALTER COLUMN email DROP NOT NULL;

-- Add unique index that excludes nulls
CREATE UNIQUE INDEX customers_email_unique 
  ON customers (email)
  WHERE email IS NOT NULL;

-- Clean up existing data
UPDATE customers 
SET email = NULL 
WHERE email = '' OR email IS NULL;

-- Add optimized index for email lookups
DROP INDEX IF EXISTS idx_customers_email;
CREATE INDEX idx_customers_email ON customers(email) 
WHERE email IS NOT NULL;

-- Add helpful comment
COMMENT ON COLUMN customers.email IS 'Optional email address. Must be unique when provided.';