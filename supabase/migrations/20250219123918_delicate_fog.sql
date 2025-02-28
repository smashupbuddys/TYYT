/*
  # Add Quotation Billing Fields

  1. Changes
    - Add billing-related columns to quotations table
    - Add indexes for performance
    - Add trigger for video call status updates
*/

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS quotation_video_call_update ON quotations;

-- Add missing columns if they don't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'quotations' AND column_name = 'bill_generated_at'
  ) THEN
    ALTER TABLE quotations 
      ADD COLUMN bill_generated_at timestamptz,
      ADD COLUMN bill_sent_at timestamptz,
      ADD COLUMN bill_paid_at timestamptz,
      ADD COLUMN bill_status text CHECK (bill_status IN ('pending', 'generated', 'sent', 'paid', 'overdue')) DEFAULT 'pending',
      ADD COLUMN quotation_number text;
  END IF;
END $$;

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_quotations_bill_status ON quotations(bill_status);
CREATE INDEX IF NOT EXISTS idx_quotations_quotation_number ON quotations(quotation_number);

-- Create function to update video call status when quotation changes
CREATE OR REPLACE FUNCTION update_video_call_on_quotation_change()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.video_call_id IS NOT NULL THEN
    UPDATE video_calls
    SET 
      quotation_id = NEW.id,
      bill_status = NEW.bill_status,
      bill_amount = NEW.total_amount,
      bill_generated_at = NEW.bill_generated_at,
      payment_status = CASE 
        WHEN NEW.bill_status = 'paid' THEN 'completed'
        WHEN NEW.bill_status = 'overdue' THEN 'overdue'
        ELSE 'pending'
      END
    WHERE id = NEW.video_call_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for quotation status updates
CREATE TRIGGER quotation_video_call_update
  AFTER INSERT OR UPDATE OF bill_status ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION update_video_call_on_quotation_change();