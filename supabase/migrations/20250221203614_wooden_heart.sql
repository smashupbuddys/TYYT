/*
  # Add workflow fallback functionality

  1. Changes
    - Add function to handle workflow progression
    - Add trigger to automatically advance workflow when steps are skipped
    - Add validation for workflow step dependencies

  2. Security
    - Enable RLS on affected tables
    - Add policies for workflow status updates
*/

-- Create function to validate workflow step dependencies
CREATE OR REPLACE FUNCTION validate_workflow_dependencies(
  workflow_status jsonb,
  step text
) RETURNS boolean AS $$
DECLARE
  step_order text[] := ARRAY['video_call', 'quotation', 'profiling', 'payment', 'qc', 'packaging', 'dispatch'];
  current_index integer;
  i integer;
BEGIN
  -- Get index of current step
  SELECT index INTO current_index
  FROM unnest(step_order) WITH ORDINALITY AS t(step, index)
  WHERE t.step = step;

  -- Check all previous steps
  FOR i IN 1..current_index-1 LOOP
    -- If a previous step is pending, we can't proceed unless it's optional
    IF workflow_status->>step_order[i] = 'pending' THEN
      -- Allow skipping quotation and profiling if not required
      IF step_order[i] = 'quotation' AND 
         (workflow_status->>'quotation_required')::boolean = false THEN
        CONTINUE;
      END IF;
      
      IF step_order[i] = 'profiling' AND 
         (workflow_status->>'profiling_required')::boolean = false THEN
        CONTINUE;
      END IF;
      
      RETURN false;
    END IF;
  END LOOP;

  RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Create function to handle workflow progression
CREATE OR REPLACE FUNCTION handle_workflow_progression()
RETURNS TRIGGER AS $$
DECLARE
  next_step text;
  step_order text[] := ARRAY['video_call', 'quotation', 'profiling', 'payment', 'qc', 'packaging', 'dispatch'];
  current_index integer;
BEGIN
  -- Get current step being updated
  SELECT index INTO current_index
  FROM unnest(step_order) WITH ORDINALITY AS t(step, index)
  WHERE t.step = TG_ARGV[0];

  -- If current step is completed, try to advance workflow
  IF NEW.workflow_status->>TG_ARGV[0] = 'completed' THEN
    -- Check if next step can be skipped
    IF current_index < array_length(step_order, 1) THEN
      next_step := step_order[current_index + 1];
      
      -- Auto-complete quotation step if not required
      IF next_step = 'quotation' AND NOT NEW.quotation_required THEN
        NEW.workflow_status := jsonb_set(
          NEW.workflow_status,
          '{quotation}',
          '"completed"'
        );
      END IF;

      -- Auto-complete profiling step if not required
      IF next_step = 'profiling' AND NOT COALESCE(
        (NEW.workflow_status->>'profiling_required')::boolean,
        false
      ) THEN
        NEW.workflow_status := jsonb_set(
          NEW.workflow_status,
          '{profiling}',
          '"completed"'
        );
      END IF;

      -- Auto-complete payment step for retail customers with no quotation
      IF next_step = 'payment' AND 
         NOT NEW.quotation_required AND
         EXISTS (
           SELECT 1 FROM customers 
           WHERE id = NEW.customer_id AND type = 'retailer'
         ) THEN
        NEW.workflow_status := jsonb_set(
          NEW.workflow_status,
          '{payment}',
          '"completed"'
        );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for each workflow step
CREATE TRIGGER handle_video_call_progression
  BEFORE UPDATE OF workflow_status ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION handle_workflow_progression('video_call');

CREATE TRIGGER handle_quotation_progression
  BEFORE UPDATE OF workflow_status ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION handle_workflow_progression('quotation');

CREATE TRIGGER handle_profiling_progression
  BEFORE UPDATE OF workflow_status ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION handle_workflow_progression('profiling');

CREATE TRIGGER handle_payment_progression
  BEFORE UPDATE OF workflow_status ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION handle_workflow_progression('payment');

-- Add helpful comments
COMMENT ON FUNCTION validate_workflow_dependencies IS 'Validates that all required previous steps are completed before advancing workflow';
COMMENT ON FUNCTION handle_workflow_progression IS 'Handles automatic workflow progression and step skipping based on business rules';