-- Add new payment tracking fields to quotations
ALTER TABLE quotations
  ADD COLUMN IF NOT EXISTS payment_notes jsonb DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS next_follow_up jsonb DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS payment_reminders jsonb DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS staff_follow_ups jsonb DEFAULT '[]';

-- Create type for payment note status
DO $$ BEGIN
  CREATE TYPE payment_note_status AS ENUM (
    'customer_request',
    'staff_follow_up',
    'payment_promise',
    'payment_failed',
    'payment_partial',
    'customer_issue'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Create function to handle payment notes and reminders
CREATE OR REPLACE FUNCTION handle_payment_tracking()
RETURNS TRIGGER AS $$
DECLARE
  latest_note jsonb;
  next_date date;
BEGIN
  -- Get the latest payment note if any new notes were added
  IF NEW.payment_notes IS DISTINCT FROM OLD.payment_notes AND 
     jsonb_array_length(NEW.payment_notes) > 0 THEN
    latest_note := NEW.payment_notes->-1;
    
    -- If the note includes a new payment date, update next_follow_up
    IF latest_note->>'next_payment_date' IS NOT NULL THEN
      NEW.next_follow_up := jsonb_build_object(
        'date', latest_note->>'next_payment_date',
        'reason', latest_note->>'note',
        'status', latest_note->>'status',
        'set_by', latest_note->>'staff_id',
        'set_at', NOW()
      );
      
      -- Create a reminder for the new payment date
      next_date := (latest_note->>'next_payment_date')::date;
      
      -- Add reminders for 1 day before and on the day
      NEW.payment_reminders := jsonb_build_array(
        jsonb_build_object(
          'date', (next_date - interval '1 day')::date,
          'type', 'day_before',
          'message', 'Payment due tomorrow as per customer request',
          'status', 'pending'
        ),
        jsonb_build_object(
          'date', next_date,
          'type', 'due_date',
          'message', 'Payment due today as per customer request',
          'status', 'pending'
        )
      );
    END IF;

    -- Add staff follow-up record
    NEW.staff_follow_ups := NEW.staff_follow_ups || jsonb_build_object(
      'timestamp', NOW(),
      'staff_id', latest_note->>'staff_id',
      'action', latest_note->>'status',
      'note', latest_note->>'note',
      'next_action_date', latest_note->>'next_payment_date'
    );
  END IF;

  -- Check if any reminders are due and create notifications
  IF NEW.payment_reminders IS NOT NULL AND 
     jsonb_array_length(NEW.payment_reminders) > 0 THEN
    FOR i IN 0..jsonb_array_length(NEW.payment_reminders) - 1 LOOP
      IF (NEW.payment_reminders->i->>'date')::date = CURRENT_DATE AND
         NEW.payment_reminders->i->>'status' = 'pending' THEN
        -- Create notification
        INSERT INTO notifications (
          user_id,
          type,
          title,
          message,
          data
        ) VALUES (
          NEW.customer_id,
          'payment_reminder',
          CASE 
            WHEN NEW.payment_reminders->i->>'type' = 'day_before' THEN 'Payment Due Tomorrow'
            ELSE 'Payment Due Today'
          END,
          NEW.payment_reminders->i->>'message',
          jsonb_build_object(
            'quotation_id', NEW.id,
            'amount', NEW.total_amount,
            'due_date', NEW.payment_reminders->i->>'date'
          )
        );
        
        -- Update reminder status to sent
        NEW.payment_reminders := jsonb_set(
          NEW.payment_reminders,
          ARRAY[i::text, 'status'],
          '"sent"'
        );
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for payment tracking
DROP TRIGGER IF EXISTS payment_tracking_trigger ON quotations;

CREATE TRIGGER payment_tracking_trigger
  BEFORE UPDATE OF payment_notes, payment_reminders
  ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION handle_payment_tracking();

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_quotations_next_follow_up 
  ON quotations USING gin (next_follow_up);

CREATE INDEX IF NOT EXISTS idx_quotations_payment_notes 
  ON quotations USING gin (payment_notes);

-- Add comment explaining the payment tracking system
COMMENT ON TABLE quotations IS 'Stores quotation data with enhanced payment tracking including staff notes, custom payment dates, and reminders.';