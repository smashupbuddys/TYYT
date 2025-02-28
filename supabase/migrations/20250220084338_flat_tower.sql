/*
  # Fix customer constraints

  1. Changes
    - Make email field optional in customers table
    - Add unique constraint for phone number safely
    - Add index on phone number for better performance

  2. Security
    - Maintain existing RLS policies
*/

-- Drop existing constraints if they exist
DO $$ 
BEGIN
  -- Drop email not null constraint
  ALTER TABLE customers 
    ALTER COLUMN email DROP NOT NULL;

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
  IF NOT EXISTS (
    SELECT 1 
    FROM information_schema.table_constraints 
    WHERE constraint_name = 'customers_phone_key'
  ) THEN
    ALTER TABLE customers
      ADD CONSTRAINT customers_phone_key UNIQUE (phone);
  END IF;
END $$;

-- Add index for phone lookups if it doesn't exist
CREATE INDEX IF NOT EXISTS idx_customers_phone 
  ON customers(phone);

-- Update existing null emails to NULL
UPDATE customers 
SET email = NULL 
WHERE email = '';