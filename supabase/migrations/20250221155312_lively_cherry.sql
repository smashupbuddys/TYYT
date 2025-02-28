/*
  # Fix Workflow Status Handling

  1. Changes
    - Add proper JSON validation for workflow_status
    - Update existing records with correct JSON structure
    - Add helper functions for workflow status updates

  2. Validation
    - Ensures workflow_status is valid JSON
    - Validates status values
    - Maintains data consistency
*/

-- Create function to validate workflow status JSON
CREATE OR REPLACE FUNCTION validate_workflow_status(status jsonb)
RETURNS boolean AS $$
BEGIN
  -- Check if all required fields exist
  IF NOT (
    status ? 'video_call' AND
    status ? 'quotation' AND
    status ? 'profiling' AND
    status ? 'payment' AND
    status ? 'qc' AND
    status ? 'packaging' AND
    status ? 'dispatch'
  ) THEN
    RETURN false;
  END IF;

  -- Check if all status values are valid
  IF NOT (
    status->>'video_call' IN ('pending', 'in_progress', 'completed', 'rejected') AND
    status->>'quotation' IN ('pending', 'in_progress', 'completed', 'rejected') AND
    status->>'profiling' IN ('pending', 'in_progress', 'completed', 'rejected') AND
    status->>'payment' IN ('pending', 'in_progress', 'completed', 'rejected') AND
    status->>'qc' IN ('pending', 'in_progress', 'completed', 'rejected') AND
    status->>'packaging' IN ('pending', 'in_progress', 'completed', 'rejected') AND
    status->>'dispatch' IN ('pending', 'in_progress', 'completed', 'rejected')
  ) THEN
    RETURN false;
  END IF;

  RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Add constraint to ensure workflow_status is valid
DO $$ 
BEGIN
  ALTER TABLE video_calls
    ADD CONSTRAINT workflow_status_valid
    CHECK (validate_workflow_status(workflow_status));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Update existing records with correct JSON structure
UPDATE video_calls
SET workflow_status = '{
  "video_call": "pending",
  "quotation": "pending",
  "profiling": "pending",
  "payment": "pending",
  "qc": "pending",
  "packaging": "pending",
  "dispatch": "pending"
}'::jsonb
WHERE workflow_status IS NULL OR NOT validate_workflow_status(workflow_status);

-- Create function to update workflow status
CREATE OR REPLACE FUNCTION update_workflow_status_v2(
  p_video_call_id uuid,
  p_step text,
  p_status text
)
RETURNS jsonb AS $$
DECLARE
  v_workflow_status jsonb;
BEGIN
  -- Get current workflow status
  SELECT workflow_status INTO v_workflow_status
  FROM video_calls
  WHERE id = p_video_call_id;

  -- Validate status value
  IF p_status NOT IN ('pending', 'in_progress', 'completed', 'rejected') THEN
    RAISE EXCEPTION 'Invalid status value: %', p_status;
  END IF;

  -- Validate step name
  IF p_step NOT IN ('video_call', 'quotation', 'profiling', 'payment', 'qc', 'packaging', 'dispatch') THEN
    RAISE EXCEPTION 'Invalid workflow step: %', p_step;
  END IF;

  -- Update the specified step
  v_workflow_status := jsonb_set(
    v_workflow_status,
    array[p_step],
    to_jsonb(p_status)
  );

  -- Update the video call
  UPDATE video_calls
  SET 
    workflow_status = v_workflow_status,
    updated_at = now()
  WHERE id = p_video_call_id;

  RETURN v_workflow_status;
END;
$$ LANGUAGE plpgsql;

-- Create function to check workflow step status
CREATE OR REPLACE FUNCTION get_workflow_step_status_v2(
  p_video_call_id uuid,
  p_step text
)
RETURNS text AS $$
DECLARE
  v_status text;
BEGIN
  -- Validate step name
  IF p_step NOT IN ('video_call', 'quotation', 'profiling', 'payment', 'qc', 'packaging', 'dispatch') THEN
    RAISE EXCEPTION 'Invalid workflow step: %', p_step;
  END IF;

  SELECT workflow_status->>p_step INTO v_status
  FROM video_calls
  WHERE id = p_video_call_id;

  RETURN v_status;
END;
$$ LANGUAGE plpgsql;

-- Add index for better performance
CREATE INDEX IF NOT EXISTS idx_video_calls_workflow_status
  ON video_calls USING gin (workflow_status);

-- Add helpful comments
COMMENT ON COLUMN video_calls.workflow_status IS 'JSON object tracking the status of each step in the video call workflow';
COMMENT ON FUNCTION update_workflow_status_v2 IS 'Updates the status of a specific workflow step for a video call';
COMMENT ON FUNCTION get_workflow_step_status_v2 IS 'Gets the current status of a specific workflow step for a video call';