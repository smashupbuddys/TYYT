/*
  # Create products table

  1. New Tables
    - `products`
      - `id` (uuid, primary key)
      - `name` (text, required)
      - `description` (text)
      - `manufacturer` (text, required)
      - `sku` (text, unique, required)
      - `buy_price` (numeric, required)
      - `wholesale_price` (numeric, required)
      - `retail_price` (numeric, required)
      - `stock_level` (integer, required)
      - `category` (text, required)
      - `image_url` (text)
      - `qr_code` (text)
      - `code128` (text)
      - `cipher` (text)
      - `additional_info` (text)
      - `created_at` (timestamptz)
      - `updated_at` (timestamptz)

  2. Security
    - Enable RLS on `products` table
    - Add policies for authenticated users to perform CRUD operations
*/

CREATE TABLE IF NOT EXISTS products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  manufacturer text NOT NULL,
  sku text UNIQUE NOT NULL,
  buy_price numeric NOT NULL,
  wholesale_price numeric NOT NULL,
  retail_price numeric NOT NULL,
  stock_level integer NOT NULL DEFAULT 0,
  category text NOT NULL,
  image_url text,
  qr_code text,
  code128 text,
  cipher text,
  additional_info text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- Allow read access to authenticated users
CREATE POLICY "Allow read access to authenticated users"
  ON products
  FOR SELECT
  TO authenticated
  USING (true);

-- Allow insert access to authenticated users
CREATE POLICY "Allow insert access to authenticated users"
  ON products
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Allow update access to authenticated users
CREATE POLICY "Allow update access to authenticated users"
  ON products
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Allow delete access to authenticated users
CREATE POLICY "Allow delete access to authenticated users"
  ON products
  FOR DELETE
  TO authenticated
  USING (true);
