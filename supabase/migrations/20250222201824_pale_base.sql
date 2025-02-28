-- Create workflow notes table
CREATE TABLE IF NOT EXISTS workflow_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  video_call_id uuid REFERENCES video_calls(id) ON DELETE CASCADE,
  step text NOT NULL,
  note text NOT NULL,
  staff_id uuid REFERENCES staff(id),
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE workflow_notes ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on workflow_notes"
  ON workflow_notes FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on workflow_notes"
  ON workflow_notes FOR INSERT TO public WITH CHECK (true);

-- Add index for better performance
CREATE INDEX idx_workflow_notes_video_call_id ON workflow_notes(video_call_id);
CREATE INDEX idx_workflow_notes_staff_id ON workflow_notes(staff_id);

-- Add helpful comment
COMMENT ON TABLE workflow_notes IS 'Stores notes and comments for each workflow step';