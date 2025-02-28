/*
  # Fix Video Call and Quotation Relationships

  1. Changes
    - Add missing video_call_id column to quotations table
    - Add missing quotation_number column to quotations table
    - Add missing bill_status and related columns to quotations table
    - Add indexes for better performance
    - Add trigger to update video call status when quotation changes

  2. Security
    - Maintain existing RLS policies
*/

-- Add video_call_id column if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'quotations' AND column_name = 'video_call_id'
  ) THEN
    ALTER TABLE quotations 
      ADD COLUMN video_call_id uuid REFERENCES video_calls(id),
      ADD COLUMN quotation_number text,
      ADD COLUMN bill_status text CHECK (bill_status IN ('pending', 'generated', 'sent', 'paid', 'overdue')) DEFAULT 'pending',
      ADD COLUMN bill_generated_at timestamptz,
      ADD COLUMN bill_sent_at timestamptz,
      ADD COLUMN bill_paid_at timestamptz;
  END IF;
END $$;

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_quotations_video_call_id ON quotations(video_call_id);
CREATE INDEX IF NOT EXISTS idx_quotations_quotation_number ON quotations(quotation_number);
CREATE INDEX IF NOT EXISTS idx_quotations_bill_status ON quotations(bill_status);

-- Create function to update video call status when quotation changes
CREATE OR REPLACE FUNCTION update_video_call_quotation_status()
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
DROP TRIGGER IF EXISTS quotation_status_trigger ON quotations;

CREATE TRIGGER quotation_status_trigger
  AFTER INSERT OR UPDATE OF bill_status ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION update_video_call_quotation_status();