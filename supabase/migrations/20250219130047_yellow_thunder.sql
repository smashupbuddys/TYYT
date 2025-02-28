/*
  # Enhance Counter Sales and Customer Tracking

  1. Add Columns
    - Add counter_sale_details to customers table
    - Add pending_payments to customers table
    - Add order_history to customers table

  2. Changes
    - Update customers table with new columns
    - Add function to update customer details on quotation completion
*/

-- Add new columns to customers table
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS counter_sale_details jsonb DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS pending_payments jsonb DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS order_history jsonb DEFAULT '[]';

-- Create function to update customer details on quotation completion
CREATE OR REPLACE FUNCTION update_customer_on_quotation()
RETURNS TRIGGER AS $$
BEGIN
  -- For counter sales, create or update customer record
  IF NEW.customer_id IS NULL AND NEW.buyer_name IS NOT NULL AND NEW.buyer_phone IS NOT NULL THEN
    -- Check if customer exists with this phone number
    WITH customer_upsert AS (
      INSERT INTO customers (
        name,
        phone,
        type,
        counter_sale_details,
        total_purchases,
        last_purchase_date
      )
      VALUES (
        NEW.buyer_name,
        NEW.buyer_phone,
        CASE 
          WHEN NEW.payment_details->>'payment_status' = 'pending' THEN 'wholesaler'
          ELSE 'retailer'
        END,
        jsonb_build_array(jsonb_build_object(
          'quotation_id', NEW.id,
          'amount', NEW.total_amount,
          'date', NEW.created_at
        )),
        NEW.total_amount,
        NEW.created_at
      )
      ON CONFLICT (phone) DO UPDATE SET
        counter_sale_details = customers.counter_sale_details || 
          jsonb_build_array(jsonb_build_object(
            'quotation_id', NEW.id,
            'amount', NEW.total_amount,
            'date', NEW.created_at
          )),
        total_purchases = customers.total_purchases + NEW.total_amount,
        last_purchase_date = NEW.created_at
      RETURNING id
    )
    SELECT id INTO NEW.customer_id FROM customer_upsert;
  END IF;

  -- For pending payments, update customer's pending_payments
  IF NEW.payment_details->>'payment_status' = 'pending' THEN
    UPDATE customers
    SET pending_payments = pending_payments || 
      jsonb_build_array(jsonb_build_object(
        'quotation_id', NEW.id,
        'total_amount', NEW.payment_details->>'total_amount',
        'paid_amount', NEW.payment_details->>'paid_amount',
        'pending_amount', NEW.payment_details->>'pending_amount',
        'date', NEW.created_at
      ))
    WHERE id = NEW.customer_id OR phone = NEW.buyer_phone;
  END IF;

  -- Update order history
  UPDATE customers
  SET order_history = order_history || 
    jsonb_build_array(jsonb_build_object(
      'quotation_id', NEW.id,
      'amount', NEW.total_amount,
      'date', NEW.created_at,
      'payment_status', NEW.payment_details->>'payment_status',
      'delivery_method', NEW.delivery_method
    ))
  WHERE id = NEW.customer_id OR phone = NEW.buyer_phone;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for customer updates
DROP TRIGGER IF EXISTS quotation_customer_update ON quotations;

CREATE TRIGGER quotation_customer_update
  BEFORE INSERT OR UPDATE ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION update_customer_on_quotation();