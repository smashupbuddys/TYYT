/*
  # Add additional info column to products table

  1. Changes
    - Add additional_info column to products table
*/

DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'additional_info'
  ) THEN
    ALTER TABLE products ADD COLUMN additional_info text;
  END IF;
END $$;
