/*
  # Fix Inventory Table Schema

  1. Changes
    - Add missing columns for product tracking
    - Add proper constraints and defaults
    - Update column types for better data integrity
    - Add indexes for performance

  2. New Columns
    - `barcode` (text, unique) for physical barcode scanning
    - `supplier_id` (uuid) for supplier tracking
    - `min_stock_level` (integer) for inventory alerts
    - `max_stock_level` (integer) for inventory management
    - `last_ordered_at` (timestamptz) for order tracking
    - `last_received_at` (timestamptz) for receiving tracking
    - `location` (text) for physical storage location
    - `unit` (text) for measurement unit
    - `weight` (numeric) for product weight
    - `dimensions` (jsonb) for product dimensions
    - `tags` (text[]) for product categorization
    - `metadata` (jsonb) for additional data

  3. Indexes
    - Add indexes for commonly queried fields
    - Add GIN index for tags and metadata search
*/

-- Add new columns with safe migrations
DO $$ 
BEGIN
  -- Add barcode column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'barcode'
  ) THEN
    ALTER TABLE products ADD COLUMN barcode text UNIQUE;
  END IF;

  -- Add supplier_id column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'supplier_id'
  ) THEN
    ALTER TABLE products ADD COLUMN supplier_id uuid;
  END IF;

  -- Add min_stock_level column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'min_stock_level'
  ) THEN
    ALTER TABLE products ADD COLUMN min_stock_level integer DEFAULT 5;
  END IF;

  -- Add max_stock_level column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'max_stock_level'
  ) THEN
    ALTER TABLE products ADD COLUMN max_stock_level integer DEFAULT 100;
  END IF;

  -- Add last_ordered_at column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'last_ordered_at'
  ) THEN
    ALTER TABLE products ADD COLUMN last_ordered_at timestamptz;
  END IF;

  -- Add last_received_at column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'last_received_at'
  ) THEN
    ALTER TABLE products ADD COLUMN last_received_at timestamptz;
  END IF;

  -- Add location column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'location'
  ) THEN
    ALTER TABLE products ADD COLUMN location text;
  END IF;

  -- Add unit column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'unit'
  ) THEN
    ALTER TABLE products ADD COLUMN unit text DEFAULT 'piece';
  END IF;

  -- Add weight column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'weight'
  ) THEN
    ALTER TABLE products ADD COLUMN weight numeric;
  END IF;

  -- Add dimensions column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'dimensions'
  ) THEN
    ALTER TABLE products ADD COLUMN dimensions jsonb DEFAULT '{"length": 0, "width": 0, "height": 0}'::jsonb;
  END IF;

  -- Add tags column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'tags'
  ) THEN
    ALTER TABLE products ADD COLUMN tags text[] DEFAULT '{}';
  END IF;

  -- Add metadata column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'metadata'
  ) THEN
    ALTER TABLE products ADD COLUMN metadata jsonb DEFAULT '{}'::jsonb;
  END IF;
END $$;

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_products_name ON products USING btree (name);
CREATE INDEX IF NOT EXISTS idx_products_sku ON products USING btree (sku);
CREATE INDEX IF NOT EXISTS idx_products_category ON products USING btree (category);
CREATE INDEX IF NOT EXISTS idx_products_manufacturer ON products USING btree (manufacturer);
CREATE INDEX IF NOT EXISTS idx_products_barcode ON products USING btree (barcode);
CREATE INDEX IF NOT EXISTS idx_products_tags ON products USING gin (tags);
CREATE INDEX IF NOT EXISTS idx_products_metadata ON products USING gin (metadata);

-- Add check constraints
DO $$ 
BEGIN
  -- Check constraint for stock levels
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.constraint_column_usage
    WHERE table_name = 'products' AND constraint_name = 'check_stock_levels'
  ) THEN
    ALTER TABLE products 
    ADD CONSTRAINT check_stock_levels 
    CHECK (min_stock_level <= max_stock_level);
  END IF;

  -- Check constraint for prices
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.constraint_column_usage
    WHERE table_name = 'products' AND constraint_name = 'check_prices'
  ) THEN
    ALTER TABLE products 
    ADD CONSTRAINT check_prices 
    CHECK (
      buy_price <= wholesale_price 
      AND wholesale_price <= retail_price
      AND buy_price > 0
    );
  END IF;

  -- Check constraint for weight
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.constraint_column_usage
    WHERE table_name = 'products' AND constraint_name = 'check_weight'
  ) THEN
    ALTER TABLE products 
    ADD CONSTRAINT check_weight 
    CHECK (weight >= 0);
  END IF;
END $$;
