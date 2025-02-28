-- Create time slots table if it doesn't exist
CREATE TABLE IF NOT EXISTS time_slots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid REFERENCES staff(id) ON DELETE CASCADE,
  start_time timestamptz NOT NULL,
  end_time timestamptz NOT NULL,
  buffer_before interval DEFAULT '5 minutes',
  buffer_after interval DEFAULT '5 minutes',
  is_available boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE time_slots ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on time_slots"
  ON time_slots FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on time_slots"
  ON time_slots FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on time_slots"
  ON time_slots FOR UPDATE TO public USING (true);

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_time_slots_staff_id ON time_slots(staff_id);
CREATE INDEX IF NOT EXISTS idx_time_slots_start_time ON time_slots(start_time);
CREATE INDEX IF NOT EXISTS idx_time_slots_end_time ON time_slots(end_time);
CREATE INDEX IF NOT EXISTS idx_time_slots_availability ON time_slots(is_available);

-- Add constraint to ensure end_time is after start_time
ALTER TABLE time_slots
  ADD CONSTRAINT time_slots_end_time_check 
  CHECK (end_time > start_time);

-- Add constraint to prevent overlapping slots for same staff
CREATE OR REPLACE FUNCTION check_slot_overlap()
RETURNS trigger AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM time_slots
    WHERE staff_id = NEW.staff_id
    AND id != NEW.id
    AND NOT is_available
    AND tstzrange(start_time - buffer_before, end_time + buffer_after) &&
        tstzrange(NEW.start_time - NEW.buffer_before, NEW.end_time + NEW.buffer_after)
  ) THEN
    RAISE EXCEPTION 'Time slot overlaps with existing slot';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_slot_overlap_trigger
  BEFORE INSERT OR UPDATE ON time_slots
  FOR EACH ROW
  EXECUTE FUNCTION check_slot_overlap();

-- Add helpful comment
COMMENT ON TABLE time_slots IS 'Stores staff availability time slots with buffer periods';