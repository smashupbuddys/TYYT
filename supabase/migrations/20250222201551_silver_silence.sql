-- Create workflow history table
CREATE TABLE IF NOT EXISTS workflow_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  video_call_id uuid REFERENCES video_calls(id) ON DELETE CASCADE,
  step text NOT NULL,
  old_status text,
  new_status text NOT NULL,
  changed_by uuid REFERENCES staff(id),
  notes text,
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE workflow_history ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on workflow_history"
  ON workflow_history FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on workflow_history"
  ON workflow_history FOR INSERT TO public WITH CHECK (true);

-- Create function to track workflow history
CREATE OR REPLACE FUNCTION track_workflow_history()
RETURNS TRIGGER AS $$
DECLARE
  step text;
  old_status text;
  new_status text;
BEGIN
  -- Compare old and new workflow status
  FOR step IN 
    SELECT * FROM jsonb_object_keys(NEW.workflow_status)
    WHERE step NOT IN ('quotation_required', 'profiling_required')
  LOOP
    old_status := OLD.workflow_status->>step;
    new_status := NEW.workflow_status->>step;
    
    -- If status changed, record it
    IF old_status IS DISTINCT FROM new_status THEN
      INSERT INTO workflow_history (
        video_call_id,
        step,
        old_status,
        new_status,
        changed_by,
        notes
      ) VALUES (
        NEW.id,
        step,
        old_status,
        new_status,
        current_setting('app.current_user_id', true)::uuid,
        NEW.notes
      );
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for workflow history
CREATE TRIGGER track_workflow_history_trigger
  AFTER UPDATE OF workflow_status ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION track_workflow_history();