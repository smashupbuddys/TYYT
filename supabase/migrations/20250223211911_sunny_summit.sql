-- Drop existing workflow status constraint if it exists
DO $$ 
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'workflow_status_valid'
  ) THEN
    ALTER TABLE video_calls DROP CONSTRAINT workflow_status_valid;
  END IF;
END $$;

-- Create improved workflow status validation function
CREATE OR REPLACE FUNCTION validate_workflow_status_v9(status jsonb)
RETURNS boolean AS $$
BEGIN
  -- Return true for NULL status (will be initialized with defaults)
  IF status IS NULL THEN
    RETURN true;
  END IF;

  -- Check if status is a JSON object
  IF jsonb_typeof(status) != 'object' THEN
    RETURN false;
  END IF;

  -- Check if all required fields exist with valid values
  RETURN (
    status ? 'video_call' AND
    status ? 'quotation' AND
    status ? 'profiling' AND
    status ? 'payment' AND
    status ? 'qc' AND
    status ? 'packaging' AND
    status ? 'dispatch' AND
    status->>'video_call' IN ('pending', 'in_progress', 'completed', 'rejected', 'skipped') AND
    status->>'quotation' IN ('pending', 'in_progress', 'completed', 'rejected', 'skipped') AND
    status->>'profiling' IN ('pending', 'in_progress', 'completed', 'rejected', 'skipped') AND
    status->>'payment' IN ('pending', 'in_progress', 'completed', 'rejected', 'skipped') AND
    status->>'qc' IN ('pending', 'in_progress', 'completed', 'rejected', 'skipped') AND
    status->>'packaging' IN ('pending', 'in_progress', 'completed', 'rejected', 'skipped') AND
    status->>'dispatch' IN ('pending', 'in_progress', 'completed', 'rejected', 'skipped')
  );
END;
$$ LANGUAGE plpgsql;

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
   OR NOT validate_workflow_status_v9(workflow_status);

-- Add constraint with improved validation
ALTER TABLE video_calls
  ADD CONSTRAINT workflow_status_valid
  CHECK (validate_workflow_status_v9(workflow_status));

-- Create function to initialize workflow status
CREATE OR REPLACE FUNCTION initialize_workflow_status_v3()
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
DROP TRIGGER IF EXISTS initialize_workflow_status_trigger ON video_calls;
CREATE TRIGGER initialize_workflow_status_trigger
  BEFORE INSERT ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION initialize_workflow_status_v3();

-- Add helpful comment
COMMENT ON FUNCTION validate_workflow_status_v9 IS 'Validates video call workflow status with proper status values and required fields';