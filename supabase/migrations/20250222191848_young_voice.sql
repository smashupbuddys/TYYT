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

-- Create function to check workflow dependencies
CREATE OR REPLACE FUNCTION check_workflow_dependencies(
  workflow_status jsonb,
  step workflow_step
) RETURNS boolean AS $$
DECLARE
  step_order workflow_step[] := ARRAY[
    'video_call',
    'quotation',
    'profiling',
    'payment',
    'qc',
    'packaging',
    'dispatch'
  ]::workflow_step[];
  current_index integer;
  previous_step workflow_step;
BEGIN
  -- Get index of current step
  SELECT index INTO current_index
  FROM unnest(step_order) WITH ORDINALITY AS t(step, index)
  WHERE t.step = step;

  -- Check all previous steps
  FOR i IN 1..current_index-1 LOOP
    previous_step := step_order[i];
    
    -- If a previous step is pending, we can't proceed
    IF workflow_status->>previous_step::text = 'pending' THEN
      -- Allow skipping quotation if not required
      IF previous_step = 'quotation' AND 
         (workflow_status->>'quotation_required')::boolean = false THEN
        CONTINUE;
      END IF;
      
      -- Allow skipping profiling if not required
      IF previous_step = 'profiling' AND 
         (workflow_status->>'profiling_required')::boolean = false THEN
        CONTINUE;
      END IF;
      
      RETURN false;
    END IF;
  END LOOP;

  RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Create function to handle workflow transitions
CREATE OR REPLACE FUNCTION handle_workflow_transition(
  p_video_call_id uuid,
  p_step workflow_step,
  p_new_status workflow_step_status
) RETURNS jsonb AS $$
DECLARE
  v_workflow_status jsonb;
  v_next_step workflow_step;
  step_order workflow_step[] := ARRAY[
    'video_call',
    'quotation',
    'profiling',
    'payment',
    'qc',
    'packaging',
    'dispatch'
  ]::workflow_step[];
  current_index integer;
BEGIN
  -- Get current workflow status
  SELECT workflow_status INTO v_workflow_status
  FROM video_calls
  WHERE id = p_video_call_id;

  -- Validate dependencies
  IF NOT check_workflow_dependencies(v_workflow_status, p_step) THEN
    RAISE EXCEPTION 'Cannot update step % - previous steps not completed', p_step;
  END IF;

  -- Update the specified step
  v_workflow_status := jsonb_set(
    v_workflow_status,
    array[p_step::text],
    to_jsonb(p_new_status::text)
  );

  -- If step is completed, set next step to pending
  IF p_new_status = 'completed' THEN
    -- Get index of current step
    SELECT index INTO current_index
    FROM unnest(step_order) WITH ORDINALITY AS t(step, index)
    WHERE t.step = p_step;

    -- If there is a next step, set it to pending
    IF current_index < array_length(step_order, 1) THEN
      v_next_step := step_order[current_index + 1];
      
      -- Handle special cases
      CASE v_next_step
        WHEN 'quotation' THEN
          -- Skip quotation if not required
          IF (v_workflow_status->>'quotation_required')::boolean = false THEN
            v_workflow_status := jsonb_set(
              v_workflow_status,
              array['quotation'],
              '"skipped"'
            );
            -- Set next step after quotation to pending
            IF current_index + 2 <= array_length(step_order, 1) THEN
              v_workflow_status := jsonb_set(
                v_workflow_status,
                array[step_order[current_index + 2]::text],
                '"pending"'
              );
            END IF;
          ELSE
            v_workflow_status := jsonb_set(
              v_workflow_status,
              array[v_next_step::text],
              '"pending"'
            );
          END IF;
        
        WHEN 'profiling' THEN
          -- Skip profiling if not required
          IF (v_workflow_status->>'profiling_required')::boolean = false THEN
            v_workflow_status := jsonb_set(
              v_workflow_status,
              array['profiling'],
              '"skipped"'
            );
            -- Set next step after profiling to pending
            IF current_index + 2 <= array_length(step_order, 1) THEN
              v_workflow_status := jsonb_set(
                v_workflow_status,
                array[step_order[current_index + 2]::text],
                '"pending"'
              );
            END IF;
          ELSE
            v_workflow_status := jsonb_set(
              v_workflow_status,
              array[v_next_step::text],
              '"pending"'
            );
          END IF;
        
        ELSE
          v_workflow_status := jsonb_set(
            v_workflow_status,
            array[v_next_step::text],
            '"pending"'
          );
      END CASE;
    END IF;
  END IF;

  -- Update the video call
  UPDATE video_calls
  SET 
    workflow_status = v_workflow_status,
    updated_at = now()
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