-- Drop existing primary key if it exists
DO $$ 
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'company_settings_pkey'
    AND table_name = 'company_settings'
  ) THEN
    ALTER TABLE company_settings DROP CONSTRAINT company_settings_pkey;
  END IF;
END $$;

-- Create temporary table to store latest settings
CREATE TEMP TABLE latest_settings AS
SELECT DISTINCT ON (name) *
FROM company_settings
ORDER BY name, created_at DESC;

-- Delete all rows from company_settings
DELETE FROM company_settings;

-- Add settings_key column
ALTER TABLE company_settings
  ADD COLUMN IF NOT EXISTS settings_key integer DEFAULT 1;

-- Insert only the latest settings back
INSERT INTO company_settings (
  settings_key,
  name,
  legal_name,
  address,
  city,
  state,
  pincode,
  phone,
  email,
  website,
  gst_number,
  pan_number,
  bank_details,
  video_call_settings
)
SELECT
  1,
  'Jewelry Management System',
  'JMS Pvt Ltd',
  '123 Diamond Street',
  'Mumbai',
  'Maharashtra',
  '400001',
  '+91 98765 43210',
  'contact@jms.com',
  'www.jms.com',
  '27AABCU9603R1ZX',
  'AABCU9603R',
  jsonb_build_object(
    'bank_name', 'HDFC Bank',
    'account_name', 'JMS Pvt Ltd',
    'account_number', '50100123456789',
    'ifsc_code', 'HDFC0001234',
    'branch', 'Diamond District'
  ),
  jsonb_build_object(
    'allow_retail', true,
    'allow_wholesale', true,
    'retail_notice_hours', 24,
    'wholesale_notice_hours', 48
  )
WHERE NOT EXISTS (SELECT 1 FROM company_settings);

-- Add primary key constraint
ALTER TABLE company_settings
  ADD PRIMARY KEY (settings_key);

-- Add check constraint to ensure settings_key is always 1
ALTER TABLE company_settings
  ADD CONSTRAINT settings_key_must_be_one CHECK (settings_key = 1);

-- Add helpful comment
COMMENT ON TABLE company_settings IS 'Stores company-wide settings. Only one row is allowed via primary key constraint.';