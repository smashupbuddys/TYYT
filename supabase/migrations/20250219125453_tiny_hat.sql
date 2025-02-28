/*
  # Enhance Counter Sales

  1. New Columns
    - Add delivery_method to quotations table
    - Add buyer_name and buyer_phone for counter sales
    - Add payment_details for tracking partial payments
    - Add workflow_status for order processing

  2. Changes
    - Update quotations table with new columns
    - Add check constraints for delivery_method
    - Add validation for buyer details
*/

-- Add new columns to quotations table
ALTER TABLE quotations
  ADD COLUMN IF NOT EXISTS delivery_method text CHECK (delivery_method IN ('hand_carry', 'dispatch')) DEFAULT 'dispatch',
  ADD COLUMN IF NOT EXISTS buyer_name text,
  ADD COLUMN IF NOT EXISTS buyer_phone text,
  ADD COLUMN IF NOT EXISTS payment_details jsonb DEFAULT '{
    "total_amount": 0,
    "paid_amount": 0,
    "pending_amount": 0,
    "payment_status": "pending",
    "payments": []
  }',
  ADD COLUMN IF NOT EXISTS workflow_status jsonb DEFAULT '{
    "qc": "pending",
    "packaging": "pending",
    "dispatch": "pending"
  }';

-- Create function to validate counter sale details
CREATE OR REPLACE FUNCTION validate_counter_sale()
RETURNS TRIGGER AS $$
BEGIN
  -- For counter sales (no customer_id), require buyer details
  IF NEW.customer_id IS NULL AND (
    (NEW.buyer_name IS NULL OR NEW.buyer_name = '') OR
    (NEW.buyer_phone IS NULL OR NEW.buyer_phone = '')
  ) THEN
    RAISE EXCEPTION 'Buyer name and phone are required for counter sales';
  END IF;

  -- For wholesaler counter sales with pending payment, require buyer details
  IF NEW.customer_id IS NULL AND 
     NEW.payment_details->>'payment_status' = 'pending' AND
     NEW.payment_details->>'total_amount' > (NEW.payment_details->>'paid_amount')::numeric THEN
    IF NEW.buyer_name IS NULL OR NEW.buyer_phone IS NULL THEN
      RAISE EXCEPTION 'Buyer details required for wholesaler counter sales with pending payment';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for counter sale validation
DROP TRIGGER IF EXISTS counter_sale_validation ON quotations;

CREATE TRIGGER counter_sale_validation
  BEFORE INSERT OR UPDATE ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION validate_counter_sale();