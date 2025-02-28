/*
  # Update customers table schema
  
  1. Changes
    - Make email optional
    - Make address fields optional
    - Update preferences JSON structure
    - Add profiling-related fields
  
  2. Security
    - Enable RLS
    - Add public access policies (if they don't exist)
*/

-- First, modify the table structure
CREATE TABLE IF NOT EXISTS customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text,
  phone text NOT NULL,
  type text NOT NULL CHECK (type IN ('wholesaler', 'retailer')),
  address text,
  city text,
  state text,
  pincode text,
  gstNumber text,
  panNumber text,
  preferences jsonb NOT NULL DEFAULT '{
    "categories": [],
    "priceRange": {"min": 0, "max": 100000},
    "preferredContact": "phone",
    "profiled": false,
    "deviceId": null,
    "lastProfilingAttempt": null
  }'::jsonb,
  notes text,
  total_purchases numeric NOT NULL DEFAULT 0,
  last_purchase_date timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS if not already enabled
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist and create new ones
DO $$ 
BEGIN
    -- Drop existing policies if they exist
    DROP POLICY IF EXISTS "Allow public read access" ON customers;
    DROP POLICY IF EXISTS "Allow public insert access" ON customers;
    DROP POLICY IF EXISTS "Allow public update access" ON customers;
    DROP POLICY IF EXISTS "Allow public delete access" ON customers;
    
    -- Create new policies
    CREATE POLICY "Allow public read access"
      ON customers
      FOR SELECT
      TO public
      USING (true);

    CREATE POLICY "Allow public insert access"
      ON customers
      FOR INSERT
      TO public
      WITH CHECK (true);

    CREATE POLICY "Allow public update access"
      ON customers
      FOR UPDATE
      TO public
      USING (true)
      WITH CHECK (true);

    CREATE POLICY "Allow public delete access"
      ON customers
      FOR DELETE
      TO public
      USING (true);
END $$;
