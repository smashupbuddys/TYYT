-- Drop existing workflow status constraint if it exists
ALTER TABLE video_calls
  DROP CONSTRAINT IF EXISTS workflow_status_valid;

-- Create improved workflow status validation function
CREATE OR REPLACE FUNCTION validate_workflow_status_v8(status jsonb)
RETURNS boolean AS $$
DECLARE
  valid_statuses text[] := ARRAY['pending', 'in_progress', 'completed', 'rejected', 'skipped'];
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

-- Create function to handle workflow transitions
CREATE OR REPLACE FUNCTION handle_workflow_transition_v3(
  p_video_call_id uuid,
  p_step text,
  p_new_status text,
  p_notes text DEFAULT NULL
) RETURNS jsonb AS $$
DECLARE
  v_workflow_status jsonb;
  v_customer_type text;
  v_quotation_required boolean;
BEGIN
  -- Get current workflow status and customer details
  SELECT 
    vc.workflow_status,
    c.type,
    vc.quotation_required
  INTO 
    v_workflow_status,
    v_customer_type,
    v_quotation_required
  FROM video_calls vc
  JOIN customers c ON c.id = vc.customer_id
  WHERE vc.id = p_video_call_id;

  -- Initialize workflow status if NULL
  IF v_workflow_status IS NULL THEN
    v_workflow_status := jsonb_build_object(
      'video_call', 'pending',
      'quotation', 'pending',
      'profiling', 'pending',
      'payment', 'pending',
      'qc', 'pending',
      'packaging', 'pending',
      'dispatch', 'pending'
    );
  END IF;

  -- Special handling for video call completion
  IF p_step = 'video_call' AND p_new_status = 'completed' THEN
    -- Set video call to completed
    v_workflow_status := jsonb_set(
      v_workflow_status,
      '{video_call}',
      '"completed"'
    );
    
    -- Always set quotation to pending after video call completion
    v_workflow_status := jsonb_set(
      v_workflow_status,
      '{quotation}',
      '"pending"'
    );
  -- Handle other workflow steps
  ELSE
    v_workflow_status := jsonb_set(
      v_workflow_status,
      array[p_step],
      to_jsonb(p_new_status)
    );
  END IF;

  -- Update the video call
  UPDATE video_calls
  SET 
    workflow_status = v_workflow_status,
    updated_at = now(),
    notes = CASE 
      WHEN p_notes IS NOT NULL THEN 
        COALESCE(notes, '') || E'\n' || p_notes
      ELSE notes
    END
  WHERE id = p_video_call_id;

  RETURN v_workflow_status;
END;
$$ LANGUAGE plpgsql;

-- Add constraint with improved validation
ALTER TABLE video_calls
  ADD CONSTRAINT workflow_status_valid
  CHECK (validate_workflow_status_v8(workflow_status));

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
   OR NOT validate_workflow_status_v8(workflow_status);