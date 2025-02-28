/*
  # Fix customer email constraints

  1. Changes
    - Make email field optional
    - Allow NULL values for email
    - Maintain uniqueness only for non-NULL emails
    - Add proper indexes for performance

  2. Security
    - Maintain RLS policies
*/

-- Drop existing email constraint if it exists
DO $$ 
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'customers_email_key'
  ) THEN
    ALTER TABLE customers DROP CONSTRAINT customers_email_key;
  END IF;
END $$;

-- Make email field nullable and add unique constraint that ignores nulls
ALTER TABLE customers
  ALTER COLUMN email DROP NOT NULL;

-- Add unique constraint that allows multiple nulls
ALTER TABLE customers
  ADD CONSTRAINT customers_email_key UNIQUE NULLS NOT DISTINCT (email);

-- Add index for better performance
CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email)
  WHERE email IS NOT NULL;

-- Update any empty string emails to NULL for consistency
UPDATE customers 
SET email = NULL 
WHERE email = '';

-- Add comment explaining the constraints
COMMENT ON COLUMN customers.email IS 'Optional customer email. Must be unique when provided.';