-- Drop existing trigger and function
DROP TRIGGER IF EXISTS counter_sale_validation ON quotations;
DROP FUNCTION IF EXISTS validate_counter_sale();

-- Create improved validation function
CREATE OR REPLACE FUNCTION validate_counter_sale()
RETURNS TRIGGER AS $$
BEGIN
  -- For counter sales (no customer_id), require buyer details only if payment is pending
  IF NEW.customer_id IS NULL AND NEW.payment_details->>'payment_status' = 'pending' THEN
    IF (NEW.buyer_name IS NULL OR NEW.buyer_name = '' OR
        NEW.buyer_phone IS NULL OR NEW.buyer_phone = '') THEN
      RAISE EXCEPTION 'Buyer name and phone are required for counter sales with pending payment';
    END IF;
  END IF;

  -- For wholesaler counter sales with pending payment, require buyer details
  IF NEW.customer_id IS NULL AND 
     NEW.payment_details->>'payment_status' = 'pending' AND
     NEW.payment_details->>'total_amount' > (NEW.payment_details->>'paid_amount')::numeric THEN
    IF NEW.buyer_name IS NULL OR NEW.buyer_phone IS NULL THEN
      RAISE EXCEPTION 'Buyer details required for wholesaler counter sales with pending payment';
    END IF;
  END IF;

  -- For retail counter sales, set payment as completed
  IF NEW.customer_id IS NULL AND NEW.payment_details->>'payment_status' = 'pending' THEN
    NEW.payment_details = jsonb_set(
      NEW.payment_details,
      '{payment_status}',
      '"completed"'
    );
    NEW.payment_details = jsonb_set(
      NEW.payment_details,
      '{paid_amount}',
      (NEW.payment_details->>'total_amount')::jsonb
    );
    NEW.payment_details = jsonb_set(
      NEW.payment_details,
      '{pending_amount}',
      '0'
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for counter sale validation
CREATE TRIGGER counter_sale_validation
  BEFORE INSERT OR UPDATE ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION validate_counter_sale();

-- Add helpful comment
COMMENT ON FUNCTION validate_counter_sale() IS 'Validates counter sale quotations and ensures proper payment handling';