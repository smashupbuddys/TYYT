/*
  # Fix Company Settings RLS Policies

  1. Changes
    - Drop existing RLS policies
    - Create new policies that allow all operations
    - Keep single row constraint
    - Add proper indexes

  2. Security
    - Enable RLS but allow all operations for development
    - Maintain single row constraint via CHECK
*/

-- Drop existing policies
DROP POLICY IF EXISTS "Allow public read access on company_settings" ON company_settings;
DROP POLICY IF EXISTS "Allow public update access on company_settings" ON company_settings;
DROP POLICY IF EXISTS "Allow public insert access on company_settings" ON company_settings;

-- Create new policies that allow all operations
CREATE POLICY "Allow all operations on company_settings"
  ON company_settings
  FOR ALL
  TO public
  USING (true)
  WITH CHECK (true);

-- Add index for better performance
CREATE INDEX IF NOT EXISTS idx_company_settings_updated_at 
  ON company_settings(updated_at);

-- Add helpful comment
COMMENT ON TABLE company_settings IS 'Stores company-wide settings. Only one row is allowed with settings_key = 1. All operations are allowed during development.';