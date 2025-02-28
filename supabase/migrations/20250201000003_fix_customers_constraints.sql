-- Update customers table constraints
ALTER TABLE customers
  DROP CONSTRAINT IF EXISTS customers_email_key,
  DROP CONSTRAINT IF EXISTS customers_phone_key;

-- Add constraints with proper handling of null values
ALTER TABLE customers
  ADD CONSTRAINT customers_email_key UNIQUE NULLS NOT DISTINCT (email),
  ADD CONSTRAINT customers_phone_key UNIQUE (phone);

-- Add index for better performance
CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone);
CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email);
