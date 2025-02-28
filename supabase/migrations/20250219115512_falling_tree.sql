/*
  # Add GST Rates Table and Default Data

  1. New Tables
    - `gst_rates`
      - `id` (uuid, primary key)
      - `category` (text)
      - `rate` (numeric)
      - `hsn_code` (text)
      - `description` (text)
      - `created_at` (timestamptz)
      - `updated_at` (timestamptz)

  2. Security
    - Enable RLS on `gst_rates` table
    - Add policies for public access
    
  3. Default Data
    - Insert common jewelry GST rates
*/

-- Drop existing table and policies if they exist
DROP TABLE IF EXISTS gst_rates CASCADE;

-- Create gst_rates table
CREATE TABLE gst_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category text NOT NULL,
  rate numeric NOT NULL CHECK (rate >= 0 AND rate <= 100),
  hsn_code text NOT NULL,
  description text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Add indexes for better performance
CREATE INDEX idx_gst_rates_category ON gst_rates(category);
CREATE INDEX idx_gst_rates_hsn_code ON gst_rates(hsn_code);

-- Enable RLS
ALTER TABLE gst_rates ENABLE ROW LEVEL SECURITY;

-- Create policies for public access
CREATE POLICY "Allow public read access on gst_rates"
  ON gst_rates FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on gst_rates"
  ON gst_rates FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on gst_rates"
  ON gst_rates FOR UPDATE TO public USING (true) WITH CHECK (true);

CREATE POLICY "Allow public delete access on gst_rates"
  ON gst_rates FOR DELETE TO public USING (true);

-- Insert default GST rates for common jewelry categories
INSERT INTO gst_rates (category, rate, hsn_code, description) VALUES
  ('Gold Jewelry', 3, '7113', 'Gold jewelry and articles'),
  ('Silver Jewelry', 3, '7113', 'Silver jewelry and articles'),
  ('Precious Stones', 3, '7102', 'Diamonds and precious stones'),
  ('Semi-precious Stones', 5, '7103', 'Semi-precious stones'),
  ('Pearls', 5, '7101', 'Natural or cultured pearls'),
  ('Watches', 18, '9101', 'Wrist-watches, pocket-watches'),
  ('Costume Jewelry', 18, '7117', 'Imitation jewelry');