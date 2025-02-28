/*
  # Add overdue payment tracking

  1. New Features
    - Staff notes for overdue payments
    - Payment promise tracking
    - Follow-up reminders
    - Customer communication history

  2. Changes
    - Add payment_tracking table for detailed payment history
    - Add payment_promises table for tracking payment commitments
    - Add staff_notes table for payment follow-ups
    - Add reminder system for payment promises
*/

-- Create payment_tracking table
CREATE TABLE IF NOT EXISTS payment_tracking (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quotation_id uuid REFERENCES quotations(id) ON DELETE CASCADE,
  status text NOT NULL CHECK (status IN ('pending', 'overdue', 'partially_paid', 'paid')),
  amount_due numeric NOT NULL,
  amount_paid numeric DEFAULT 0,
  last_payment_date timestamptz,
  next_payment_date timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create payment_promises table
CREATE TABLE IF NOT EXISTS payment_promises (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_tracking_id uuid REFERENCES payment_tracking(id) ON DELETE CASCADE,
  promised_date date NOT NULL,
  promised_amount numeric NOT NULL,
  reason text,
  status text NOT NULL CHECK (status IN ('pending', 'fulfilled', 'broken')),
  staff_id uuid NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Create staff_notes table
CREATE TABLE IF NOT EXISTS staff_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_tracking_id uuid REFERENCES payment_tracking(id) ON DELETE CASCADE,
  staff_id uuid NOT NULL,
  note text NOT NULL,
  follow_up_date date,
  created_at timestamptz DEFAULT now()
);

-- Create payment_reminders table
CREATE TABLE IF NOT EXISTS payment_reminders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_promise_id uuid REFERENCES payment_promises(id) ON DELETE CASCADE,
  reminder_date date NOT NULL,
  status text NOT NULL CHECK (status IN ('pending', 'sent', 'cancelled')),
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE payment_tracking ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_promises ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_reminders ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on payment_tracking"
  ON payment_tracking FOR SELECT TO public USING (true);

CREATE POLICY "Allow public read access on payment_promises"
  ON payment_promises FOR SELECT TO public USING (true);

CREATE POLICY "Allow public read access on staff_notes"
  ON staff_notes FOR SELECT TO public USING (true);

CREATE POLICY "Allow public read access on payment_reminders"
  ON payment_reminders FOR SELECT TO public USING (true);

-- Create indexes
CREATE INDEX idx_payment_tracking_quotation ON payment_tracking(quotation_id);
CREATE INDEX idx_payment_tracking_status ON payment_tracking(status);
CREATE INDEX idx_payment_promises_tracking ON payment_promises(payment_tracking_id);
CREATE INDEX idx_staff_notes_tracking ON staff_notes(payment_tracking_id);
CREATE INDEX idx_payment_reminders_promise ON payment_reminders(payment_promise_id);

-- Create function to handle payment promises
CREATE OR REPLACE FUNCTION handle_payment_promise()
RETURNS TRIGGER AS $$
BEGIN
  -- Create reminders for the payment promise
  INSERT INTO payment_reminders (
    payment_promise_id,
    reminder_date,
    status
  ) VALUES
    (NEW.id, NEW.promised_date - interval '1 day', 'pending'),
    (NEW.id, NEW.promised_date, 'pending');

  -- Update payment tracking next payment date
  UPDATE payment_tracking
  SET next_payment_date = NEW.promised_date
  WHERE id = NEW.payment_tracking_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for payment promises
CREATE TRIGGER payment_promise_trigger
  AFTER INSERT ON payment_promises
  FOR EACH ROW
  EXECUTE FUNCTION handle_payment_promise();

-- Create function to handle staff notes
CREATE OR REPLACE FUNCTION handle_staff_note()
RETURNS TRIGGER AS $$
BEGIN
  -- If follow-up date is set, create a reminder
  IF NEW.follow_up_date IS NOT NULL THEN
    INSERT INTO payment_reminders (
      payment_promise_id,
      reminder_date,
      status
    ) VALUES
      ((SELECT id FROM payment_promises 
        WHERE payment_tracking_id = NEW.payment_tracking_id 
        ORDER BY created_at DESC 
        LIMIT 1),
       NEW.follow_up_date,
       'pending');
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for staff notes
CREATE TRIGGER staff_note_trigger
  AFTER INSERT ON staff_notes
  FOR EACH ROW
  EXECUTE FUNCTION handle_staff_note();