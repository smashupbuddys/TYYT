/*
  # Create customers table

  1. New Tables
    - `customers`
      - `id` (uuid, primary key)
      - `name` (text)
      - `email` (text, unique)
      - `phone` (text)
      - `type` (text)
      - `address` (text)
      - `city` (text)
      - `state` (text)
      - `pincode` (text)
      - `gst_number` (text, nullable)
      - `pan_number` (text, nullable)
      - `preferences` (jsonb)
      - `notes` (text)
      - `total_purchases` (numeric)
      - `last_purchase_date` (timestamptz)
      - `created_at` (timestamptz)
      - `updated_at` (timestamptz)

  2. Security
    - Enable RLS on `customers` table
    - Add policies for public access (temporary for development)
*/

CREATE TABLE IF NOT EXISTS customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text UNIQUE NOT NULL,
  phone text NOT NULL,
  type text NOT NULL CHECK (type IN ('wholesaler', 'retailer')),
  address text NOT NULL,
  city text NOT NULL,
  state text NOT NULL,
  pincode text NOT NULL,
  gst_number text,
  pan_number text,
  preferences jsonb NOT NULL DEFAULT '{
    "categories": [],
    "priceRange": {"min": 0, "max": 100000},
    "preferredContact": "phone"
  }',
  notes text,
  total_purchases numeric NOT NULL DEFAULT 0,
  last_purchase_date timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

-- Create policies for public access (temporary for development)
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
