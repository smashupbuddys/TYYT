/*
  # Fix payment status handling

  1. Changes
    - Modify payment_details structure to use numeric comparisons
    - Add validation for payment amounts and status
    - Update existing records for consistency

  2. Validation
    - Ensures payment amounts are non-negative
    - Validates payment status values
    - Checks that amounts match correctly
*/

-- Modify quotations table to ensure consistent payment details
ALTER TABLE quotations
  ALTER COLUMN payment_details SET DEFAULT jsonb_build_object(
    'total_amount', 0,
    'paid_amount', 0,
    'pending_amount', 0,
    'payment_status', 'pending',
    'payments', '[]'
  );

-- Create function to validate payment details
CREATE OR REPLACE FUNCTION validate_payment_details()
RETURNS TRIGGER AS $$
BEGIN
  -- Set default payment details if NULL
  IF NEW.payment_details IS NULL THEN
    NEW.payment_details := jsonb_build_object(
      'total_amount', NEW.total_amount,
      'paid_amount', 0,
      'pending_amount', NEW.total_amount,
      'payment_status', 'pending',
      'payments', '[]'
    );
  END IF;

  -- Ensure all required fields exist with correct types
  IF NOT (
    (NEW.payment_details->>'total_amount')::numeric >= 0 AND
    (NEW.payment_details->>'paid_amount')::numeric >= 0 AND
    (NEW.payment_details->>'pending_amount')::numeric >= 0 AND
    NEW.payment_details->>'payment_status' IN ('pending', 'partially_paid', 'paid', 'overdue') AND
    jsonb_typeof(NEW.payment_details->'payments') = 'array'
  ) THEN
    RAISE EXCEPTION 'Invalid payment details structure';
  END IF;

  -- Validate amounts match
  IF (NEW.payment_details->>'total_amount')::numeric != NEW.total_amount OR
     (NEW.payment_details->>'total_amount')::numeric != 
     ((NEW.payment_details->>'paid_amount')::numeric + (NEW.payment_details->>'pending_amount')::numeric) THEN
    NEW.payment_details := jsonb_set(
      NEW.payment_details,
      '{total_amount}',
      to_jsonb(NEW.total_amount)
    );
    NEW.payment_details := jsonb_set(
      NEW.payment_details,
      '{pending_amount}',
      to_jsonb(NEW.total_amount - (NEW.payment_details->>'paid_amount')::numeric)
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for payment details validation
DROP TRIGGER IF EXISTS validate_payment_details_trigger ON quotations;

CREATE TRIGGER validate_payment_details_trigger
  BEFORE INSERT OR UPDATE
  ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION validate_payment_details();

-- Update existing records to ensure consistent data
UPDATE quotations
SET payment_details = jsonb_build_object(
  'total_amount', total_amount,
  'paid_amount', COALESCE((payment_details->>'paid_amount')::numeric, 0),
  'pending_amount', COALESCE(total_amount - (payment_details->>'paid_amount')::numeric, total_amount),
  'payment_status', COALESCE(payment_details->>'payment_status', 'pending'),
  'payments', COALESCE(payment_details->'payments', '[]'::jsonb)
)
WHERE payment_details IS NULL 
   OR payment_details = '{}'::jsonb
   OR NOT (payment_details ? 'total_amount' 
           AND payment_details ? 'paid_amount'
           AND payment_details ? 'pending_amount'
           AND payment_details ? 'payment_status'
           AND payment_details ? 'payments');