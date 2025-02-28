-- First drop the constraint that depends on the function
ALTER TABLE video_calls
  DROP CONSTRAINT IF EXISTS workflow_status_valid;

-- Now we can safely drop the function
DROP FUNCTION IF EXISTS validate_workflow_status_v5(jsonb);

-- Create type for workflow step status
DO $$ BEGIN
  CREATE TYPE workflow_step_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected', 'skipped');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Create type for workflow step
DO $$ BEGIN
  CREATE TYPE workflow_step AS ENUM (
    'video_call',
    'quotation',
    'profiling',
    'payment',
    'qc',
    'packaging',
    'dispatch'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Create improved workflow status validation
CREATE OR REPLACE FUNCTION validate_workflow_status_v6(status jsonb)
RETURNS boolean AS $$
DECLARE
  step workflow_step;
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

  -- Check each workflow step
  FOR step IN SELECT unnest(enum_range(NULL::workflow_step)) LOOP
    -- Check if step exists
    IF NOT status ? step::text THEN
      RETURN false;
    END IF;

    -- Get step status
    step_status := status->>step::text;

    -- Check if status is valid
    IF step_status IS NULL OR NOT step_status = ANY(ARRAY['pending', 'in_progress', 'completed', 'rejected', 'skipped']) THEN
      RETURN false;
    END IF;
  END LOOP;

  RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Create function to handle workflow transitions
CREATE OR REPLACE FUNCTION handle_workflow_transition_v2(
  p_video_call_id uuid,
  p_step workflow_step,
  p_new_status workflow_step_status,
  p_notes text DEFAULT NULL
) RETURNS jsonb AS $$
DECLARE
  v_workflow_status jsonb;
  v_customer_type text;
BEGIN
  -- Get current workflow status and customer type
  SELECT 
    vc.workflow_status,
    c.type
  INTO 
    v_workflow_status,
    v_customer_type
  FROM video_calls vc
  JOIN customers c ON c.id = vc.customer_id
  WHERE vc.id = p_video_call_id;

  -- Handle video call completion
  IF p_step = 'video_call' AND p_new_status = 'completed' THEN
    -- Always set quotation to pending after video call
    v_workflow_status := jsonb_set(
      v_workflow_status,
      '{video_call}',
      '"completed"'
    );
    v_workflow_status := jsonb_set(
      v_workflow_status,
      '{quotation}',
      '"pending"'
    );
  -- Handle quotation completion
  ELSIF p_step = 'quotation' AND p_new_status = 'completed' THEN
    -- Skip profiling for retail customers or if already profiled
    IF v_customer_type = 'retail' OR (v_workflow_status->>'profiling_required')::boolean = false THEN
      v_workflow_status := jsonb_set(
        jsonb_set(
          v_workflow_status,
          '{quotation}',
          '"completed"'
        ),
        '{profiling}',
        '"skipped"'
      );
      -- Set payment to pending
      v_workflow_status := jsonb_set(
        v_workflow_status,
        '{payment}',
        '"pending"'
      );
    ELSE
      -- Set profiling to pending for wholesale customers
      v_workflow_status := jsonb_set(
        jsonb_set(
          v_workflow_status,
          '{quotation}',
          '"completed"'
        ),
        '{profiling}',
        '"pending"'
      );
    END IF;
  -- Handle payment completion
  ELSIF p_step = 'payment' AND p_new_status = 'completed' THEN
    -- Set QC to pending after payment
    v_workflow_status := jsonb_set(
      jsonb_set(
        v_workflow_status,
        '{payment}',
        '"completed"'
      ),
      '{qc}',
      '"pending"'
    );
  -- Handle QC completion
  ELSIF p_step = 'qc' AND p_new_status = 'completed' THEN
    -- Set packaging to pending after QC
    v_workflow_status := jsonb_set(
      jsonb_set(
        v_workflow_status,
        '{qc}',
        '"completed"'
      ),
      '{packaging}',
      '"pending"'
    );
  -- Handle packaging completion
  ELSIF p_step = 'packaging' AND p_new_status = 'completed' THEN
    -- Set dispatch to pending after packaging
    v_workflow_status := jsonb_set(
      jsonb_set(
        v_workflow_status,
        '{packaging}',
        '"completed"'
      ),
      '{dispatch}',
      '"pending"'
    );
  -- Handle other steps
  ELSE
    v_workflow_status := jsonb_set(
      v_workflow_status,
      array[p_step::text],
      to_jsonb(p_new_status::text)
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
      'dispatch', 'pending',
      'quotation_required', COALESCE(NEW.quotation_required, false),
      'profiling_required', false
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
  EXECUTE FUNCTION initialize_workflow_status();

-- Add constraint with improved validation
ALTER TABLE video_calls
  ADD CONSTRAINT workflow_status_valid
  CHECK (validate_workflow_status_v6(workflow_status));

-- Update existing records with correct JSON structure
UPDATE video_calls
SET workflow_status = jsonb_build_object(
  'video_call', COALESCE(workflow_status->>'video_call', 'pending'),
  'quotation', COALESCE(workflow_status->>'quotation', 'pending'),
  'profiling', COALESCE(workflow_status->>'profiling', 'pending'),
  'payment', COALESCE(workflow_status->>'payment', 'pending'),
  'qc', COALESCE(workflow_status->>'qc', 'pending'),
  'packaging', COALESCE(workflow_status->>'packaging', 'pending'),
  'dispatch', COALESCE(workflow_status->>'dispatch', 'pending'),
  'quotation_required', COALESCE(quotation_required, false),
  'profiling_required', false
)
WHERE workflow_status IS NULL 
   OR NOT validate_workflow_status_v6(workflow_status);