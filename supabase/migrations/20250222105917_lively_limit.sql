-- Drop existing foreign key if it exists
DO $$ 
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'video_calls_staff_id_fkey'
  ) THEN
    ALTER TABLE video_calls DROP CONSTRAINT video_calls_staff_id_fkey;
  END IF;
END $$;

-- Add foreign key constraint to staff table
ALTER TABLE video_calls
  ADD CONSTRAINT video_calls_staff_id_fkey 
  FOREIGN KEY (staff_id) 
  REFERENCES staff(id)
  ON DELETE SET NULL;

-- Add comment explaining the relationship
COMMENT ON CONSTRAINT video_calls_staff_id_fkey ON video_calls IS 'Links video calls to assigned staff members';

-- Add index for better join performance
CREATE INDEX IF NOT EXISTS idx_video_calls_staff_id ON video_calls(staff_id);