-- Drop existing workflow status constraint if it exists
ALTER TABLE video_calls
  DROP CONSTRAINT IF EXISTS workflow_status_valid;

-- Create improved workflow status validation function
CREATE OR REPLACE FUNCTION validate_workflow_status_v5(status jsonb)
RETURNS boolean AS $$
DECLARE
  valid_statuses text[] := ARRAY['pending', 'in_progress', 'completed', 'rejected'];
  required_steps text[] := ARRAY['video_call', 'quotation', 'profiling', 'payment', 'qc', 'packaging', 'dispatch'];
  step text;
  step_status text;
BEGIN
  -- Return true for NULL status (will be initialized with defaults)
  IF status IS NULL THEN
    RETURN true;
  END IF;

  -- Check if status is a JSON object
  IF jsonb_typeof(status) != 'object' THEN
    RETURN false;
  END IF;

  -- Check each required step
  FOREACH step IN ARRAY required_steps LOOP
    -- Check if step exists
    IF NOT status ? step THEN
      RETURN false;
    END IF;

    -- Get step status
    step_status := status->>step;

    -- Check if status is valid
    IF step_status IS NULL OR NOT step_status = ANY(valid_statuses) THEN
      RETURN false;
    END IF;
  END LOOP;

  RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Add constraint with improved validation
ALTER TABLE video_calls
  ADD CONSTRAINT workflow_status_valid
  CHECK (validate_workflow_status_v5(workflow_status));

-- Create function to initialize workflow status
CREATE OR REPLACE FUNCTION initialize_workflow_status()
RETURNS trigger AS $$
BEGIN
  IF NEW.workflow_status IS NULL THEN
    NEW.workflow_status := jsonb_build_object(
      'video_call', 'pending',
      'quotation', 'pending',
      'profiling', 'pending',
      'payment', 'pending',
      'qc', 'pending',
      'packaging', 'pending',
      'dispatch', 'pending'
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to initialize workflow status
CREATE TRIGGER initialize_workflow_status_trigger
  BEFORE INSERT ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION initialize_workflow_status();

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
   OR NOT validate_workflow_status_v5(workflow_status);