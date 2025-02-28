-- Drop existing function and triggers
DROP TRIGGER IF EXISTS handle_video_call_progression ON video_calls;
DROP TRIGGER IF EXISTS handle_quotation_progression ON video_calls;
DROP TRIGGER IF EXISTS handle_profiling_progression ON video_calls;
DROP TRIGGER IF EXISTS handle_payment_progression ON video_calls;
DROP FUNCTION IF EXISTS handle_workflow_progression_v2();

-- Create improved workflow progression function
CREATE OR REPLACE FUNCTION handle_workflow_progression_v3()
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

  -- If video call is completed, always set quotation to pending
  IF TG_ARGV[0] = 'video_call' AND NEW.workflow_status->>'video_call' = 'completed' THEN
    NEW.workflow_status := jsonb_set(
      NEW.workflow_status,
      '{quotation}',
      '"pending"'
    );
    RETURN NEW;
  END IF;

  -- Handle other workflow steps
  IF NEW.workflow_status->>TG_ARGV[0] = 'completed' THEN
    -- Check if next step exists
    IF current_index < array_length(step_order, 1) THEN
      next_step := step_order[current_index + 1];
      
      -- Set next step to pending
      NEW.workflow_status := jsonb_set(
        NEW.workflow_status,
        array[next_step],
        '"pending"'
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create new triggers with updated function
CREATE TRIGGER handle_video_call_progression
  BEFORE UPDATE OF workflow_status ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION handle_workflow_progression_v3('video_call');

CREATE TRIGGER handle_quotation_progression
  BEFORE UPDATE OF workflow_status ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION handle_workflow_progression_v3('quotation');

CREATE TRIGGER handle_profiling_progression
  BEFORE UPDATE OF workflow_status ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION handle_workflow_progression_v3('profiling');

CREATE TRIGGER handle_payment_progression
  BEFORE UPDATE OF workflow_status ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION handle_workflow_progression_v3('payment');

-- Add helpful comment
COMMENT ON FUNCTION handle_workflow_progression_v3 IS 'Handles video call workflow progression ensuring quotation step is always pending after video call completion';