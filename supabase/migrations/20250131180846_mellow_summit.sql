/*
  # Enhance Video Calls System - Part 2

  1. Changes
    - Add notification trigger function
    - Add notification trigger
*/

-- Create function to handle payment notifications
CREATE OR REPLACE FUNCTION handle_payment_notification()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.payment_status = 'pending' THEN
    INSERT INTO notifications (
      user_id,
      type,
      title,
      message,
      data
    ) VALUES (
      NEW.customer_id,
      'payment_pending',
      'Payment Pending',
      'You have a pending payment for your recent video consultation.',
      jsonb_build_object(
        'video_call_id', NEW.id,
        'quotation_id', NEW.quotation_id,
        'due_date', NEW.payment_due_date
      )
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for payment notifications
DROP TRIGGER IF EXISTS video_call_payment_notification ON video_calls;

CREATE TRIGGER video_call_payment_notification
  AFTER UPDATE OF payment_status ON video_calls
  FOR EACH ROW
  WHEN (OLD.payment_status IS DISTINCT FROM NEW.payment_status)
  EXECUTE FUNCTION handle_payment_notification();
