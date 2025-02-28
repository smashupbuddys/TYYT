/*
  # Update RLS policies for products table

  1. Changes
    - Drop existing RLS policies
    - Create new policies allowing public access
    - Keep RLS enabled for future security implementation
*/

-- Drop existing policies
DROP POLICY IF EXISTS "Allow read access to authenticated users" ON products;
DROP POLICY IF EXISTS "Allow insert access to authenticated users" ON products;
DROP POLICY IF EXISTS "Allow update access to authenticated users" ON products;
DROP POLICY IF EXISTS "Allow delete access to authenticated users" ON products;

-- Create new policies for public access
CREATE POLICY "Allow public read access"
  ON products
  FOR SELECT
  TO public
  USING (true);

CREATE POLICY "Allow public insert access"
  ON products
  FOR INSERT
  TO public
  WITH CHECK (true);

CREATE POLICY "Allow public update access"
  ON products
  FOR UPDATE
  TO public
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow public delete access"
  ON products
  FOR DELETE
  TO public
  USING (true);
