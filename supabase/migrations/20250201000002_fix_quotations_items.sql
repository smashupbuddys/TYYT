/*
  # Fix quotations table schema
  
  1. Changes
    - Update items column to use proper JSONB type
    - Add quotation_number column
    - Add proper indexes
*/

-- Modify quotations table
ALTER TABLE quotations
  ALTER COLUMN items SET DATA TYPE jsonb USING items::jsonb,
  ADD COLUMN IF NOT EXISTS quotation_number text;

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_quotations_customer_id ON quotations(customer_id);
CREATE INDEX IF NOT EXISTS idx_quotations_status ON quotations(status);
CREATE INDEX IF NOT EXISTS idx_quotations_quotation_number ON quotations(quotation_number);

-- Update existing quotations to ensure items is valid JSONB
UPDATE quotations 
SET items = '[]'::jsonb 
WHERE items IS NULL OR items = 'null';
