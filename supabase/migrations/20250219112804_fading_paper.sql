/*
  # Fix Video Call Deletion Cascade

  1. Changes
    - Add ON DELETE CASCADE to workflow_assignments foreign key
    - Add ON DELETE CASCADE to quotations foreign key
    - Add indexes for better performance
    - Update existing constraints to ensure proper cleanup

  2. Security
    - Maintain existing RLS policies
*/

-- First, drop existing foreign key constraints
ALTER TABLE workflow_assignments 
  DROP CONSTRAINT IF EXISTS workflow_assignments_video_call_id_fkey;

ALTER TABLE quotations 
  DROP CONSTRAINT IF EXISTS quotations_video_call_id_fkey;

-- Recreate foreign key constraints with ON DELETE CASCADE
ALTER TABLE workflow_assignments
  ADD CONSTRAINT workflow_assignments_video_call_id_fkey 
  FOREIGN KEY (video_call_id) 
  REFERENCES video_calls(id) 
  ON DELETE CASCADE;

ALTER TABLE quotations
  ADD CONSTRAINT quotations_video_call_id_fkey 
  FOREIGN KEY (video_call_id) 
  REFERENCES video_calls(id) 
  ON DELETE CASCADE;

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_workflow_assignments_video_call_id 
  ON workflow_assignments(video_call_id);

CREATE INDEX IF NOT EXISTS idx_quotations_video_call_id 
  ON quotations(video_call_id);