/*
  # Update quotations table schema
  
  1. Changes
    - Add video_call_id column
    - Add foreign key constraint
    - Add bill_status and related columns
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
      ADD COLUMN bill_status text CHECK (bill_status IN ('pending', 'generated', 'sent', 'paid', 'overdue')) DEFAULT 'pending',
      ADD COLUMN bill_generated_at timestamptz,
      ADD COLUMN bill_sent_at timestamptz,
      ADD COLUMN bill_paid_at timestamptz;
  END IF;
END $$;

-- Update existing quotations to set default values
UPDATE quotations 
SET bill_status = 'pending' 
WHERE bill_status IS NULL;

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_quotations_video_call_id ON quotations(video_call_id);
CREATE INDEX IF NOT EXISTS idx_quotations_bill_status ON quotations(bill_status);

-- Add trigger to update video_calls when quotation status changes
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

DROP TRIGGER IF EXISTS quotation_video_call_update ON quotations;

CREATE TRIGGER quotation_video_call_update
  AFTER INSERT OR UPDATE OF bill_status ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION update_video_call_on_quotation_change();
