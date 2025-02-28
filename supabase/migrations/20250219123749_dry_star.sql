/*
  # GST Rates and Company Settings

  1. New Tables
    - gst_rates: Store GST rates for different jewelry categories
    - company_settings: Store company information and settings

  2. Changes
    - Add indexes for performance
    - Enable RLS
    - Add policies with existence checks
    - Insert default GST rates
*/

-- Create gst_rates table
CREATE TABLE IF NOT EXISTS gst_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category text NOT NULL,
  rate numeric NOT NULL CHECK (rate >= 0 AND rate <= 100),
  hsn_code text NOT NULL,
  description text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create company_settings table
CREATE TABLE IF NOT EXISTS company_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  legal_name text NOT NULL,
  address text NOT NULL,
  city text NOT NULL,
  state text NOT NULL,
  pincode text NOT NULL,
  phone text NOT NULL,
  email text NOT NULL,
  website text,
  gst_number text,
  pan_number text,
  bank_details jsonb NOT NULL DEFAULT '{
    "bank_name": "",
    "account_name": "",
    "account_number": "",
    "ifsc_code": "",
    "branch": ""
  }',
  logo_url text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_gst_rates_category ON gst_rates(category);
CREATE INDEX IF NOT EXISTS idx_gst_rates_hsn_code ON gst_rates(hsn_code);

-- Enable RLS
ALTER TABLE gst_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;

-- Create policies with existence checks
DO $$ 
BEGIN
  -- GST Rates policies
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'gst_rates' AND policyname = 'Allow public read access on gst_rates'
  ) THEN
    CREATE POLICY "Allow public read access on gst_rates"
      ON gst_rates FOR SELECT TO public USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'gst_rates' AND policyname = 'Allow public insert access on gst_rates'
  ) THEN
    CREATE POLICY "Allow public insert access on gst_rates"
      ON gst_rates FOR INSERT TO public WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'gst_rates' AND policyname = 'Allow public update access on gst_rates'
  ) THEN
    CREATE POLICY "Allow public update access on gst_rates"
      ON gst_rates FOR UPDATE TO public USING (true) WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'gst_rates' AND policyname = 'Allow public delete access on gst_rates'
  ) THEN
    CREATE POLICY "Allow public delete access on gst_rates"
      ON gst_rates FOR DELETE TO public USING (true);
  END IF;

  -- Company Settings policies
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'company_settings' AND policyname = 'Allow public read access on company_settings'
  ) THEN
    CREATE POLICY "Allow public read access on company_settings"
      ON company_settings FOR SELECT TO public USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'company_settings' AND policyname = 'Allow public insert access on company_settings'
  ) THEN
    CREATE POLICY "Allow public insert access on company_settings"
      ON company_settings FOR INSERT TO public WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'company_settings' AND policyname = 'Allow public update access on company_settings'
  ) THEN
    CREATE POLICY "Allow public update access on company_settings"
      ON company_settings FOR UPDATE TO public USING (true) WITH CHECK (true);
  END IF;
END $$;

-- Insert default GST rates
INSERT INTO gst_rates (category, rate, hsn_code, description) VALUES
  ('Gold Jewelry', 3, '7113', 'Gold jewelry and articles'),
  ('Silver Jewelry', 3, '7113', 'Silver jewelry and articles'),
  ('Precious Stones', 3, '7102', 'Diamonds and precious stones'),
  ('Semi-precious Stones', 5, '7103', 'Semi-precious stones'),
  ('Pearls', 5, '7101', 'Natural or cultured pearls'),
  ('Watches', 18, '9101', 'Wrist-watches, pocket-watches'),
  ('Costume Jewelry', 18, '7117', 'Imitation jewelry')
ON CONFLICT DO NOTHING;