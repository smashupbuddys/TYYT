/*
  # GST Rates Setup

  1. New Tables
    - gst_rates: Store GST rates for different jewelry categories
    
  2. Changes
    - Add indexes for performance
    - Enable RLS
    - Add policies with existence checks
    - Insert default GST rates
*/

-- Create gst_rates table if it doesn't exist
CREATE TABLE IF NOT EXISTS gst_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category text NOT NULL,
  rate numeric NOT NULL CHECK (rate >= 0 AND rate <= 100),
  hsn_code text NOT NULL,
  description text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_gst_rates_category ON gst_rates(category);
CREATE INDEX IF NOT EXISTS idx_gst_rates_hsn_code ON gst_rates(hsn_code);

-- Enable RLS
ALTER TABLE gst_rates ENABLE ROW LEVEL SECURITY;

-- Create policies with existence checks
DO $$ 
BEGIN
  -- Check and create read policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'gst_rates' AND policyname = 'Allow public read access on gst_rates'
  ) THEN
    CREATE POLICY "Allow public read access on gst_rates"
      ON gst_rates FOR SELECT TO public USING (true);
  END IF;

  -- Check and create insert policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'gst_rates' AND policyname = 'Allow public insert access on gst_rates'
  ) THEN
    CREATE POLICY "Allow public insert access on gst_rates"
      ON gst_rates FOR INSERT TO public WITH CHECK (true);
  END IF;

  -- Check and create update policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'gst_rates' AND policyname = 'Allow public update access on gst_rates'
  ) THEN
    CREATE POLICY "Allow public update access on gst_rates"
      ON gst_rates FOR UPDATE TO public USING (true) WITH CHECK (true);
  END IF;

  -- Check and create delete policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'gst_rates' AND policyname = 'Allow public delete access on gst_rates'
  ) THEN
    CREATE POLICY "Allow public delete access on gst_rates"
      ON gst_rates FOR DELETE TO public USING (true);
  END IF;
END $$;

-- Insert default GST rates for common jewelry categories
INSERT INTO gst_rates (category, rate, hsn_code, description) VALUES
  ('Gold Jewelry', 3, '7113', 'Gold jewelry and articles'),
  ('Silver Jewelry', 3, '7113', 'Silver jewelry and articles'),
  ('Precious Stones', 3, '7102', 'Diamonds and precious stones'),
  ('Semi-precious Stones', 5, '7103', 'Semi-precious stones'),
  ('Pearls', 5, '7101', 'Natural or cultured pearls'),
  ('Watches', 18, '9101', 'Wrist-watches, pocket-watches'),
  ('Costume Jewelry', 18, '7117', 'Imitation jewelry')
ON CONFLICT DO NOTHING;