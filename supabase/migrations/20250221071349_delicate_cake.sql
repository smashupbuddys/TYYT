-- Ensure numeric types for all price and quantity fields
ALTER TABLE quotations
  ALTER COLUMN total_amount TYPE numeric USING total_amount::numeric,
  ALTER COLUMN payment_details TYPE jsonb USING jsonb_build_object(
    'total_amount', COALESCE((payment_details->>'total_amount')::numeric, total_amount),
    'paid_amount', COALESCE((payment_details->>'paid_amount')::numeric, 0),
    'pending_amount', COALESCE((payment_details->>'pending_amount')::numeric, total_amount),
    'payment_status', COALESCE(payment_details->>'payment_status', 'pending'),
    'payments', COALESCE(payment_details->'payments', '[]'::jsonb)
  );

-- Create function to validate numeric fields
CREATE OR REPLACE FUNCTION validate_quotation_amounts()
RETURNS TRIGGER AS $$
BEGIN
  -- Ensure all numeric fields are actually numeric
  IF NOT (
    NEW.total_amount IS NULL OR 
    (NEW.total_amount IS NOT NULL AND NEW.total_amount::text ~ '^[0-9]*\.?[0-9]*$')
  ) THEN
    RAISE EXCEPTION 'total_amount must be numeric';
  END IF;

  -- Validate payment details
  IF NEW.payment_details IS NOT NULL THEN
    IF NOT (
      (NEW.payment_details->>'total_amount')::text ~ '^[0-9]*\.?[0-9]*$' AND
      (NEW.payment_details->>'paid_amount')::text ~ '^[0-9]*\.?[0-9]*$' AND
      (NEW.payment_details->>'pending_amount')::text ~ '^[0-9]*\.?[0-9]*$'
    ) THEN
      RAISE EXCEPTION 'payment amounts must be numeric';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for amount validation
DROP TRIGGER IF EXISTS validate_quotation_amounts_trigger ON quotations;
CREATE TRIGGER validate_quotation_amounts_trigger
  BEFORE INSERT OR UPDATE
  ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION validate_quotation_amounts();