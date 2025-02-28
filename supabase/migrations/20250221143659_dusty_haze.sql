-- Drop existing trigger and function
DROP TRIGGER IF EXISTS counter_sale_validation ON quotations;
DROP FUNCTION IF EXISTS validate_counter_sale();

-- Create improved validation function
CREATE OR REPLACE FUNCTION validate_counter_sale()
RETURNS TRIGGER AS $$
DECLARE
  is_retail boolean;
BEGIN
  -- Determine if this is a retail sale
  is_retail := COALESCE(
    (NEW.payment_details->>'customer_type')::text = 'retailer',
    true  -- Default to retail if not specified
  );

  -- For counter sales (no customer_id)
  IF NEW.customer_id IS NULL THEN
    -- For retail counter sales, auto-complete payment
    IF is_retail THEN
      NEW.payment_details = jsonb_set(
        COALESCE(NEW.payment_details, '{}'::jsonb),
        '{payment_status}',
        '"completed"'::jsonb
      );
      NEW.payment_details = jsonb_set(
        NEW.payment_details,
        '{paid_amount}',
        to_jsonb(COALESCE((NEW.payment_details->>'total_amount')::numeric, NEW.total_amount))
      );
      NEW.payment_details = jsonb_set(
        NEW.payment_details,
        '{pending_amount}',
        '0'::jsonb
      );
      -- No buyer details required for retail counter sales
      RETURN NEW;
    ELSE
      -- For wholesale counter sales with pending payment
      IF NEW.payment_details->>'payment_status' = 'pending' OR
         (NEW.payment_details->>'total_amount')::numeric > COALESCE((NEW.payment_details->>'paid_amount')::numeric, 0) THEN
        -- Require buyer details
        IF NEW.buyer_name IS NULL OR NEW.buyer_name = '' OR
           NEW.buyer_phone IS NULL OR NEW.buyer_phone = '' THEN
          RAISE EXCEPTION 'Buyer name and phone are required for wholesale counter sales with pending payment';
        END IF;
      END IF;
    END IF;
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
COMMENT ON FUNCTION validate_counter_sale() IS 'Validates counter sale quotations and ensures proper payment handling. Retail counter sales are auto-completed while wholesale counter sales require buyer details for pending payments.';