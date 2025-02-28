-- Add payment status type
DO $$ BEGIN
  CREATE TYPE payment_status AS ENUM (
    'pending',
    'partially_paid',
    'paid',
    'overdue'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Modify quotations table to use the new type
ALTER TABLE quotations
  ALTER COLUMN payment_details TYPE jsonb USING jsonb_build_object(
    'total_amount', COALESCE((payment_details->>'total_amount')::numeric, total_amount),
    'paid_amount', COALESCE((payment_details->>'paid_amount')::numeric, 0),
    'pending_amount', COALESCE((payment_details->>'pending_amount')::numeric, total_amount),
    'payment_status', COALESCE(payment_details->>'payment_status', 'pending'),
    'payments', COALESCE(payment_details->'payments', '[]'::jsonb)
  );

-- Create function to validate payment details
CREATE OR REPLACE FUNCTION validate_payment_details()
RETURNS TRIGGER AS $$
BEGIN
  -- Ensure all required fields exist
  IF NOT (
    NEW.payment_details ? 'total_amount' AND
    NEW.payment_details ? 'paid_amount' AND
    NEW.payment_details ? 'pending_amount' AND
    NEW.payment_details ? 'payment_status' AND
    NEW.payment_details ? 'payments'
  ) THEN
    RAISE EXCEPTION 'Invalid payment details structure';
  END IF;

  -- Validate numeric fields
  IF NOT (
    (NEW.payment_details->>'total_amount')::numeric >= 0 AND
    (NEW.payment_details->>'paid_amount')::numeric >= 0 AND
    (NEW.payment_details->>'pending_amount')::numeric >= 0
  ) THEN
    RAISE EXCEPTION 'Payment amounts must be non-negative';
  END IF;

  -- Validate payment status
  IF NOT (NEW.payment_details->>'payment_status' IN ('pending', 'partially_paid', 'paid', 'overdue')) THEN
    RAISE EXCEPTION 'Invalid payment status';
  END IF;

  -- Validate amounts match
  IF (NEW.payment_details->>'total_amount')::numeric != 
     ((NEW.payment_details->>'paid_amount')::numeric + (NEW.payment_details->>'pending_amount')::numeric) THEN
    RAISE EXCEPTION 'Total amount must equal paid amount plus pending amount';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for payment details validation
DROP TRIGGER IF EXISTS validate_payment_details_trigger ON quotations;

CREATE TRIGGER validate_payment_details_trigger
  BEFORE INSERT OR UPDATE OF payment_details
  ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION validate_payment_details();

-- Add indexes for better performance
CREATE INDEX idx_quotations_payment_status 
  ON quotations ((payment_details->>'payment_status'));

CREATE INDEX idx_quotations_paid_amount 
  ON quotations (((payment_details->>'paid_amount')::numeric));

-- Update existing records to ensure consistent data
UPDATE quotations
SET payment_details = jsonb_build_object(
  'total_amount', COALESCE((payment_details->>'total_amount')::numeric, total_amount),
  'paid_amount', COALESCE((payment_details->>'paid_amount')::numeric, 0),
  'pending_amount', COALESCE((payment_details->>'pending_amount')::numeric, total_amount),
  'payment_status', COALESCE(payment_details->>'payment_status', 'pending'),
  'payments', COALESCE(payment_details->'payments', '[]'::jsonb)
)
WHERE payment_details IS NULL OR payment_details = '{}'::jsonb;