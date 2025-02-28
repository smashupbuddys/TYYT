/*
  # Update Payment Tracking System

  1. Changes
    - Add payment tracking fields to quotations table
    - Add payment status tracking with alerts
    - Add staff response tracking
    - Add admin alert system
    - Add payment timeline tracking

  2. New Fields
    - bill_generated_at: When the bill was generated after video call
    - payment_timeline: Array of payment status changes with timestamps
    - staff_responses: Array of staff responses to payment status
    - admin_alerts: Array of alerts sent to admin
    - alert_levels: Payment alert levels (3 days, 7 days, admin)
*/

-- Add new payment tracking fields to quotations
ALTER TABLE quotations
  ADD COLUMN IF NOT EXISTS bill_generated_at timestamptz,
  ADD COLUMN IF NOT EXISTS payment_timeline jsonb DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS staff_responses jsonb DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS admin_alerts jsonb DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS alert_levels jsonb DEFAULT '{
    "first_alert": 3,
    "suspicious_alert": 7,
    "admin_alert": 10
  }';

-- Create function to handle payment alerts
CREATE OR REPLACE FUNCTION handle_payment_alerts()
RETURNS TRIGGER AS $$
DECLARE
  days_since_bill integer;
  current_status record;
BEGIN
  -- Only process if bill has been generated
  IF NEW.bill_generated_at IS NOT NULL THEN
    days_since_bill := EXTRACT(DAY FROM (NOW() - NEW.bill_generated_at));
    
    -- Get current alert levels
    SELECT * INTO current_status FROM jsonb_to_record(NEW.alert_levels) AS x(
      first_alert integer,
      suspicious_alert integer,
      admin_alert integer
    );

    -- First alert after 3 days
    IF days_since_bill >= current_status.first_alert AND 
       NOT EXISTS (
         SELECT 1 FROM jsonb_array_elements(NEW.payment_timeline) AS x(item)
         WHERE x.item->>'type' = 'first_alert'
       ) THEN
      NEW.payment_timeline = NEW.payment_timeline || jsonb_build_object(
        'type', 'first_alert',
        'timestamp', NOW(),
        'message', 'First payment reminder sent'
      );
    END IF;

    -- Mark as suspicious after 7 days if no staff response
    IF days_since_bill >= current_status.suspicious_alert AND 
       NOT EXISTS (
         SELECT 1 FROM jsonb_array_elements(NEW.payment_timeline) AS x(item)
         WHERE x.item->>'type' = 'suspicious_alert'
       ) AND
       NOT EXISTS (
         SELECT 1 FROM jsonb_array_elements(NEW.staff_responses) AS x(item)
         WHERE x.item->>'type' = 'payment_follow_up'
       ) THEN
      NEW.payment_timeline = NEW.payment_timeline || jsonb_build_object(
        'type', 'suspicious_alert',
        'timestamp', NOW(),
        'message', 'Marked as suspicious due to no staff response'
      );
    END IF;

    -- Alert admin after 10 days if still no response
    IF days_since_bill >= current_status.admin_alert AND 
       NOT EXISTS (
         SELECT 1 FROM jsonb_array_elements(NEW.payment_timeline) AS x(item)
         WHERE x.item->>'type' = 'admin_alert'
       ) THEN
      NEW.admin_alerts = NEW.admin_alerts || jsonb_build_object(
        'type', 'payment_overdue',
        'timestamp', NOW(),
        'message', 'Payment severely overdue, requires immediate attention',
        'days_overdue', days_since_bill
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for payment alerts
DROP TRIGGER IF EXISTS payment_alerts_trigger ON quotations;

CREATE TRIGGER payment_alerts_trigger
  BEFORE UPDATE OF bill_status ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION handle_payment_alerts();

-- Create function to record staff responses
CREATE OR REPLACE FUNCTION record_staff_response()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.staff_responses IS DISTINCT FROM OLD.staff_responses THEN
    -- Update payment timeline with staff response
    NEW.payment_timeline = NEW.payment_timeline || jsonb_build_object(
      'type', 'staff_response',
      'timestamp', NOW(),
      'message', 'Staff member responded to payment status',
      'response', NEW.staff_responses->-1 -- Get the latest response
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for staff responses
DROP TRIGGER IF EXISTS staff_response_trigger ON quotations;

CREATE TRIGGER staff_response_trigger
  BEFORE UPDATE OF staff_responses ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION record_staff_response();

-- Create index for bill_generated_at for better performance
CREATE INDEX IF NOT EXISTS idx_quotations_bill_generated_at 
  ON quotations(bill_generated_at);

-- Add comment explaining the payment tracking system
COMMENT ON TABLE quotations IS 'Stores quotation data with payment tracking. Payment alerts are triggered based on time since bill generation, not video call completion. Staff responses and admin alerts are tracked separately.';