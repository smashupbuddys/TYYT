-- Drop existing table and recreate with simplified structure
DROP TABLE IF EXISTS gst_rates CASCADE;

CREATE TABLE gst_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rate numeric NOT NULL DEFAULT 18 CHECK (rate >= 0 AND rate <= 100),
  description text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE gst_rates ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on gst_rates"
  ON gst_rates FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on gst_rates"
  ON gst_rates FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on gst_rates"
  ON gst_rates FOR UPDATE TO public USING (true) WITH CHECK (true);

CREATE POLICY "Allow public delete access on gst_rates"
  ON gst_rates FOR DELETE TO public USING (true);

-- Insert default GST rate
INSERT INTO gst_rates (rate, description)
VALUES (18, 'Default GST rate')
ON CONFLICT DO NOTHING;