/*
  # Improve Customer Data Retention
  
  1. New Tables
    - `retention_settings` table to store retention periods for different data types
    - `customer_archives` table to store historical customer data
  
  2. Changes
    - Add archival flags and dates to customers table
    - Add trigger to automatically archive customer data
    
  3. Security
    - Enable RLS on new tables
    - Add policies for data access
*/

-- Create retention settings table
CREATE TABLE retention_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  data_type text NOT NULL,
  retention_period interval NOT NULL,
  archive_period interval NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create customer archives table
CREATE TABLE customer_archives (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL,
  customer_data jsonb NOT NULL,
  archived_at timestamptz DEFAULT now(),
  delete_after timestamptz NOT NULL,
  reason text
);

-- Add archival columns to customers
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS archived boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS archived_at timestamptz,
  ADD COLUMN IF NOT EXISTS archive_reason text;

-- Enable RLS
ALTER TABLE retention_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_archives ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on retention_settings"
  ON retention_settings FOR SELECT TO public USING (true);

CREATE POLICY "Allow public read access on customer_archives"
  ON customer_archives FOR SELECT TO public USING (true);

-- Insert default retention settings
INSERT INTO retention_settings (data_type, retention_period, archive_period) VALUES
  ('active_customers', '10 years', '30 years'),
  ('inactive_customers', '5 years', '20 years'),
  ('quotations', '2 years', '10 years'),
  ('transactions', '2 years', '10 years');

-- Create function to archive customer data
CREATE OR REPLACE FUNCTION archive_customer_data()
RETURNS trigger AS $$
BEGIN
  -- Store complete customer data in archives
  INSERT INTO customer_archives (
    customer_id,
    customer_data,
    delete_after
  ) VALUES (
    OLD.id,
    to_jsonb(OLD),
    CASE
      WHEN OLD.total_purchases > 0 THEN 
        now() + (SELECT archive_period FROM retention_settings WHERE data_type = 'active_customers' LIMIT 1)
      ELSE
        now() + (SELECT archive_period FROM retention_settings WHERE data_type = 'inactive_customers' LIMIT 1)
    END
  );
  
  -- Update customer record
  NEW.archived := true;
  NEW.archived_at := now();
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for customer archival
CREATE TRIGGER customer_archive_trigger
  BEFORE UPDATE OF archived ON customers
  FOR EACH ROW
  WHEN (NEW.archived = true AND OLD.archived = false)
  EXECUTE FUNCTION archive_customer_data();

-- Create function to clean up archived data
CREATE OR REPLACE FUNCTION cleanup_archived_data()
RETURNS void AS $$
BEGIN
  -- Delete expired archives
  DELETE FROM customer_archives
  WHERE delete_after < now();
  
  -- Archive inactive customers
  UPDATE customers
  SET archived = true,
    archive_reason = 'Inactive customer'
  WHERE 
    NOT archived AND
    last_purchase_date < now() - (
      SELECT retention_period 
      FROM retention_settings 
      WHERE data_type = 'inactive_customers' 
      LIMIT 1
    );
END;
$$ LANGUAGE plpgsql;