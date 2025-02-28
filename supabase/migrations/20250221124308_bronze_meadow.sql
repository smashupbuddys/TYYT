/*
  # Add product creation date tracking

  1. Changes
    - Add created_at column to products table
    - Add trigger to automatically set created_at on insert
    - Add index for better performance
*/

-- Add created_at column if it doesn't exist
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

-- Create index for better performance
CREATE INDEX IF NOT EXISTS idx_products_created_at ON products(created_at);

-- Add comment explaining the column
COMMENT ON COLUMN products.created_at IS 'Timestamp when the product was first added to inventory';