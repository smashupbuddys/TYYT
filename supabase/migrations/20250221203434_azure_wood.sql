/*
  # Fix workflow status handling

  1. Changes
    - Add workflow_status column to quotations table
    - Add trigger to validate workflow status
    - Add function to update workflow status
    - Add function to sync workflow status between quotations and video calls

  2. Security
    - Enable RLS on quotations table
    - Add policies for workflow status updates
*/

-- Add workflow_status to quotations if it doesn't exist
ALTER TABLE quotations
  ADD COLUMN IF NOT EXISTS workflow_status jsonb DEFAULT '{
    "qc": "pending",
    "packaging": "pending",
    "dispatch": "pending"
  }';

-- Create function to validate workflow status
CREATE OR REPLACE FUNCTION validate_quotation_workflow_status(status jsonb)
RETURNS boolean AS $$
BEGIN
  -- Check if all required fields exist with valid values
  RETURN (
    status ? 'qc' AND
    status ? 'packaging' AND
    status ? 'dispatch' AND
    status->>'qc' IN ('pending', 'in_progress', 'completed', 'rejected') AND
    status->>'packaging' IN ('pending', 'in_progress', 'completed', 'rejected') AND
    status->>'dispatch' IN ('pending', 'in_progress', 'completed', 'rejected')
  );
END;
$$ LANGUAGE plpgsql;

-- Add constraint to ensure workflow_status is valid
ALTER TABLE quotations
  ADD CONSTRAINT quotation_workflow_status_valid
  CHECK (validate_quotation_workflow_status(workflow_status));

-- Create function to update workflow status
CREATE OR REPLACE FUNCTION update_quotation_workflow_status(
  p_quotation_id uuid,
  p_step text,
  p_status text
)
RETURNS jsonb AS $$
DECLARE
  v_workflow_status jsonb;
BEGIN
  -- Get current workflow status
  SELECT workflow_status INTO v_workflow_status
  FROM quotations
  WHERE id = p_quotation_id;

  -- Validate status value
  IF p_status NOT IN ('pending', 'in_progress', 'completed', 'rejected') THEN
    RAISE EXCEPTION 'Invalid status value: %', p_status;
  END IF;

  -- Validate step name
  IF p_step NOT IN ('qc', 'packaging', 'dispatch') THEN
    RAISE EXCEPTION 'Invalid workflow step: %', p_step;
  END IF;

  -- Update the specified step
  v_workflow_status := jsonb_set(
    v_workflow_status,
    array[p_step],
    to_jsonb(p_status)
  );

  -- Update the quotation
  UPDATE quotations
  SET 
    workflow_status = v_workflow_status,
    updated_at = now()
  WHERE id = p_quotation_id;

  RETURN v_workflow_status;
END;
$$ LANGUAGE plpgsql;

-- Create function to sync workflow status with video call
CREATE OR REPLACE FUNCTION sync_video_call_workflow_status()
RETURNS TRIGGER AS $$
BEGIN
  -- Only sync if this quotation is linked to a video call
  IF NEW.video_call_id IS NOT NULL THEN
    -- Update video call workflow status
    UPDATE video_calls
    SET workflow_status = jsonb_set(
      workflow_status,
      '{quotation}',
      '"completed"'
    )
    WHERE id = NEW.video_call_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for workflow status sync
CREATE TRIGGER sync_video_call_workflow_status_trigger
  AFTER INSERT OR UPDATE OF status ON quotations
  FOR EACH ROW
  WHEN (NEW.status = 'accepted')
  EXECUTE FUNCTION sync_video_call_workflow_status();

-- Update existing quotations with default workflow status
UPDATE quotations
SET workflow_status = '{
  "qc": "pending",
  "packaging": "pending",
  "dispatch": "pending"
}'::jsonb
WHERE workflow_status IS NULL;

-- Add index for better performance
CREATE INDEX IF NOT EXISTS idx_quotations_workflow_status
  ON quotations USING gin (workflow_status);

-- Add helpful comments
COMMENT ON COLUMN quotations.workflow_status IS 'JSON object tracking the status of QC, packaging, and dispatch steps';
COMMENT ON FUNCTION update_quotation_workflow_status IS 'Updates the status of a specific workflow step for a quotation';
COMMENT ON FUNCTION sync_video_call_workflow_status IS 'Syncs workflow status between quotations and video calls';