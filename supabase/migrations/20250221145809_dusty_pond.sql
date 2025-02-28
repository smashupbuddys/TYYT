/*
  # Fix Company Settings Table

  1. Changes
    - Drop existing table and recreate with proper constraints
    - Add settings_key as primary key with default value 1
    - Add check constraint to ensure only one row
    - Add default values for all columns
    - Add proper RLS policies

  2. Security
    - Enable RLS
    - Add policies for public access
*/

-- Drop existing table if it exists
DROP TABLE IF EXISTS company_settings CASCADE;

-- Create company_settings table with proper constraints
CREATE TABLE company_settings (
  settings_key integer PRIMARY KEY DEFAULT 1 CHECK (settings_key = 1),
  name text NOT NULL DEFAULT 'Jewelry Management System',
  legal_name text NOT NULL DEFAULT 'JMS Pvt Ltd',
  address text NOT NULL DEFAULT '123 Diamond Street',
  city text NOT NULL DEFAULT 'Mumbai',
  state text NOT NULL DEFAULT 'Maharashtra',
  pincode text NOT NULL DEFAULT '400001',
  phone text NOT NULL DEFAULT '+91 98765 43210',
  email text NOT NULL DEFAULT 'contact@jms.com',
  website text DEFAULT 'www.jms.com',
  gst_number text DEFAULT '27AABCU9603R1ZX',
  pan_number text DEFAULT 'AABCU9603R',
  bank_details jsonb NOT NULL DEFAULT '{
    "bank_name": "HDFC Bank",
    "account_name": "JMS Pvt Ltd",
    "account_number": "50100123456789",
    "ifsc_code": "HDFC0001234",
    "branch": "Diamond District"
  }',
  video_call_settings jsonb NOT NULL DEFAULT '{
    "allow_retail": true,
    "allow_wholesale": true,
    "retail_notice_hours": 24,
    "wholesale_notice_hours": 48
  }',
  logo_url text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on company_settings"
  ON company_settings FOR SELECT TO public USING (true);

CREATE POLICY "Allow public update access on company_settings"
  ON company_settings FOR UPDATE TO public USING (true) WITH CHECK (settings_key = 1);

CREATE POLICY "Allow public insert access on company_settings"
  ON company_settings FOR INSERT TO public WITH CHECK (
    settings_key = 1 AND
    NOT EXISTS (SELECT 1 FROM company_settings)
  );

-- Insert default settings if table is empty
INSERT INTO company_settings (settings_key)
VALUES (1)
ON CONFLICT (settings_key) DO NOTHING;

-- Add helpful comment
COMMENT ON TABLE company_settings IS 'Stores company-wide settings. Only one row is allowed with settings_key = 1.';