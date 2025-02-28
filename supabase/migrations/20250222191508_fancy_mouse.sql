-- Drop existing workflow status constraint if it exists
ALTER TABLE video_calls
  DROP CONSTRAINT IF EXISTS workflow_status_valid;

-- Create improved workflow status validation function
CREATE OR REPLACE FUNCTION validate_workflow_status_v4(status jsonb)
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
  CHECK (validate_workflow_status_v4(workflow_status));

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
   OR NOT validate_workflow_status_v4(workflow_status);