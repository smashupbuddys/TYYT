-- Drop existing workflow status constraint if it exists
ALTER TABLE video_calls
  DROP CONSTRAINT IF EXISTS workflow_status_valid;

-- Drop existing functions to avoid conflicts
DROP FUNCTION IF EXISTS validate_workflow_status(jsonb);
DROP FUNCTION IF EXISTS update_workflow_status(uuid, text, text);
DROP FUNCTION IF EXISTS get_workflow_step_status(uuid, text);

-- Create function to validate workflow status
CREATE OR REPLACE FUNCTION validate_workflow_status_v3(status jsonb)
RETURNS boolean AS $$
BEGIN
  -- Check if all required fields exist with valid values
  RETURN (
    status ? 'video_call' AND
    status ? 'quotation' AND
    status ? 'profiling' AND
    status ? 'payment' AND
    status ? 'qc' AND
    status ? 'packaging' AND
    status ? 'dispatch' AND
    status->>'video_call' IN ('pending', 'in_progress', 'completed', 'rejected') AND
    status->>'quotation' IN ('pending', 'in_progress', 'completed', 'rejected') AND
    status->>'profiling' IN ('pending', 'in_progress', 'completed', 'rejected') AND
    status->>'payment' IN ('pending', 'in_progress', 'completed', 'rejected') AND
    status->>'qc' IN ('pending', 'in_progress', 'completed', 'rejected') AND
    status->>'packaging' IN ('pending', 'in_progress', 'completed', 'rejected') AND
    status->>'dispatch' IN ('pending', 'in_progress', 'completed', 'rejected')
  );
END;
$$ LANGUAGE plpgsql;

-- Add constraint to ensure workflow_status is valid
ALTER TABLE video_calls
  ADD CONSTRAINT workflow_status_valid
  CHECK (validate_workflow_status_v3(workflow_status));

-- Update existing records with correct JSON structure
UPDATE video_calls
SET workflow_status = jsonb_build_object(
  'video_call', COALESCE(workflow_status->>'video_call', 'pending'),
  'quotation', COALESCE(workflow_status->>'quotation', 'pending'),
  'profiling', COALESCE(workflow_status->>'profiling', 'pending'),
  'payment', COALESCE(workflow_status->>'payment', 'pending'),
  'qc', COALESCE(workflow_status->>'qc', 'pending'),
  'packaging', COALESCE(workflow_status->>'packaging', 'pending'),
  'dispatch', COALESCE(workflow_status->>'dispatch', 'pending')
)
WHERE workflow_status IS NULL 
   OR NOT validate_workflow_status_v3(workflow_status);

-- Create function to update workflow status
CREATE OR REPLACE FUNCTION update_workflow_status_v3(
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

-- Create function to get workflow step status
CREATE OR REPLACE FUNCTION get_workflow_step_status_v3(
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
COMMENT ON FUNCTION update_workflow_status_v3 IS 'Updates the status of a specific workflow step for a video call';
COMMENT ON FUNCTION get_workflow_step_status_v3 IS 'Gets the current status of a specific workflow step for a video call';