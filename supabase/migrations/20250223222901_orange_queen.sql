-- Create type for workflow step order
CREATE TYPE workflow_step AS ENUM (
  'video_call',
  'quotation', 
  'profiling',
  'payment',
  'qc',
  'packaging',
  'dispatch'
);

-- Create function to get workflow step order
CREATE OR REPLACE FUNCTION get_workflow_step_order(step text)
RETURNS integer AS $$
BEGIN
  RETURN CASE step
    WHEN 'video_call' THEN 1
    WHEN 'quotation' THEN 2
    WHEN 'profiling' THEN 3
    WHEN 'payment' THEN 4
    WHEN 'qc' THEN 5
    WHEN 'packaging' THEN 6
    WHEN 'dispatch' THEN 7
    ELSE 999
  END;
END;
$$ LANGUAGE plpgsql;

-- Create function to sort workflow steps
CREATE OR REPLACE FUNCTION sort_workflow_steps(workflow jsonb)
RETURNS jsonb AS $$
DECLARE
  sorted_workflow jsonb;
BEGIN
  SELECT jsonb_object_agg(
    key,
    value ORDER BY get_workflow_step_order(key)
  )
  INTO sorted_workflow
  FROM jsonb_each(workflow);
  
  RETURN sorted_workflow;
END;
$$ LANGUAGE plpgsql;

-- Update existing video calls with sorted workflow status
UPDATE video_calls
SET workflow_status = sort_workflow_steps(workflow_status)
WHERE workflow_status IS NOT NULL;