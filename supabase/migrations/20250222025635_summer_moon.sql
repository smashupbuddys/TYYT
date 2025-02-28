-- Create function to handle workflow progression with proper quotation handling
CREATE OR REPLACE FUNCTION handle_workflow_progression_v2()
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

  -- If video call is completed, check quotation requirement
  IF TG_ARGV[0] = 'video_call' AND NEW.workflow_status->>'video_call' = 'completed' THEN
    -- If quotation is required, set quotation step to in_progress
    IF NEW.quotation_required THEN
      NEW.workflow_status := jsonb_set(
        NEW.workflow_status,
        '{quotation}',
        '"in_progress"'
      );
    -- If quotation is not required, mark it as completed and move to profiling
    ELSE
      NEW.workflow_status := jsonb_set(
        jsonb_set(
          NEW.workflow_status,
          '{quotation}',
          '"completed"'
        ),
        '{profiling}',
        '"in_progress"'
      );
    END IF;
  END IF;

  -- If current step is completed, try to advance workflow
  IF NEW.workflow_status->>TG_ARGV[0] = 'completed' THEN
    -- Check if next step exists
    IF current_index < array_length(step_order, 1) THEN
      next_step := step_order[current_index + 1];
      
      -- Skip quotation if not required
      IF next_step = 'quotation' AND NOT NEW.quotation_required THEN
        next_step := step_order[current_index + 2];
      END IF;

      -- Set next step to in_progress
      NEW.workflow_status := jsonb_set(
        NEW.workflow_status,
        array[next_step],
        '"in_progress"'
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing triggers
DROP TRIGGER IF EXISTS handle_video_call_progression ON video_calls;
DROP TRIGGER IF EXISTS handle_quotation_progression ON video_calls;
DROP TRIGGER IF EXISTS handle_profiling_progression ON video_calls;
DROP TRIGGER IF EXISTS handle_payment_progression ON video_calls;

-- Create new triggers with updated function
CREATE TRIGGER handle_video_call_progression
  BEFORE UPDATE OF workflow_status ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION handle_workflow_progression_v2('video_call');

CREATE TRIGGER handle_quotation_progression
  BEFORE UPDATE OF workflow_status ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION handle_workflow_progression_v2('quotation');

CREATE TRIGGER handle_profiling_progression
  BEFORE UPDATE OF workflow_status ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION handle_workflow_progression_v2('profiling');

CREATE TRIGGER handle_payment_progression
  BEFORE UPDATE OF workflow_status ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION handle_workflow_progression_v2('payment');

-- Add helpful comment
COMMENT ON FUNCTION handle_workflow_progression_v2 IS 'Handles video call workflow progression with proper quotation handling';