/*
  # Enhance Video Call System with Staff Assignment and Billing

  1. Changes
    - Add staff assignment tracking to video_calls
    - Add billing status tracking
    - Add customer profiling trigger
    
  2. Security
    - Add policies for new columns
*/

-- Add staff assignment columns to video_calls
ALTER TABLE video_calls
  ADD COLUMN IF NOT EXISTS assigned_staff_id uuid,
  ADD COLUMN IF NOT EXISTS assignment_status text CHECK (assignment_status IN ('pending', 'accepted', 'rejected', 'completed')) DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS assignment_notes text,
  ADD COLUMN IF NOT EXISTS bill_amount numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS bill_status text CHECK (bill_status IN ('pending', 'generated', 'sent', 'paid', 'overdue')) DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS bill_generated_at timestamptz,
  ADD COLUMN IF NOT EXISTS bill_sent_at timestamptz,
  ADD COLUMN IF NOT EXISTS bill_paid_at timestamptz;

-- Create function to update customer profiling
CREATE OR REPLACE FUNCTION update_customer_profiling()
RETURNS TRIGGER AS $$
BEGIN
  -- Update customer profiling based on purchase
  IF NEW.bill_status = 'paid' AND OLD.bill_status != 'paid' THEN
    UPDATE customers
    SET 
      total_purchases = total_purchases + NEW.bill_amount,
      last_purchase_date = NEW.bill_paid_at,
      preferences = jsonb_set(
        preferences,
        '{profiled}',
        'true'
      )
    WHERE id = NEW.customer_id;
    
    -- Create a notification for successful payment
    INSERT INTO notifications (
      user_id,
      type,
      title,
      message,
      data
    ) VALUES (
      NEW.customer_id,
      'payment_completed',
      'Payment Received',
      'Thank you for your payment. Your video consultation bill has been settled.',
      jsonb_build_object(
        'video_call_id', NEW.id,
        'amount', NEW.bill_amount,
        'paid_at', NEW.bill_paid_at
      )
    );
  END IF;
  
  -- Create overdue notification
  IF NEW.bill_status = 'overdue' AND OLD.bill_status != 'overdue' THEN
    INSERT INTO notifications (
      user_id,
      type,
      title,
      message,
      data
    ) VALUES (
      NEW.customer_id,
      'payment_overdue',
      'Payment Overdue',
      'Your video consultation payment is overdue. Please settle the bill as soon as possible.',
      jsonb_build_object(
        'video_call_id', NEW.id,
        'amount', NEW.bill_amount,
        'due_date', NEW.payment_due_date
      )
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for customer profiling updates
DROP TRIGGER IF EXISTS video_call_profiling_trigger ON video_calls;

CREATE TRIGGER video_call_profiling_trigger
  AFTER UPDATE OF bill_status ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION update_customer_profiling();

-- Create function to check overdue payments
CREATE OR REPLACE FUNCTION check_overdue_payments()
RETURNS void AS $$
BEGIN
  UPDATE video_calls
  SET bill_status = 'overdue'
  WHERE 
    payment_due_date < NOW() 
    AND bill_status = 'pending'
    AND quotation_required = true;
END;
$$ LANGUAGE plpgsql;
