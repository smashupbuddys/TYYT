-- Add workflow tracking columns to video_calls
ALTER TABLE video_calls
  ADD COLUMN IF NOT EXISTS workflow_status jsonb DEFAULT '{
    "video_call": "pending",
    "quotation": "pending",
    "profiling": "pending",
    "payment": "pending",
    "qc": "pending",
    "packaging": "pending",
    "dispatch": "pending"
  }',
  ADD COLUMN IF NOT EXISTS assigned_staff jsonb DEFAULT '{
    "video_call": null,
    "billing": null,
    "qc": null,
    "packaging": null,
    "dispatch": null
  }',
  ADD COLUMN IF NOT EXISTS qc_details jsonb DEFAULT '{
    "pieces_checked": false,
    "chains_checked": false,
    "dori_checked": false,
    "notes": null,
    "checked_at": null,
    "checked_by": null
  }',
  ADD COLUMN IF NOT EXISTS packaging_details jsonb DEFAULT '{
    "packed_at": null,
    "packed_by": null,
    "package_type": null,
    "weight": null,
    "dimensions": null,
    "notes": null
  }',
  ADD COLUMN IF NOT EXISTS dispatch_details jsonb DEFAULT '{
    "dispatched_at": null,
    "dispatched_by": null,
    "tracking_number": null,
    "courier_name": null,
    "estimated_delivery": null,
    "notes": null
  }';

-- Create workflow_assignments table to track staff assignments
CREATE TABLE IF NOT EXISTS workflow_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  video_call_id uuid REFERENCES video_calls(id),
  staff_id uuid NOT NULL,
  role text NOT NULL CHECK (role IN ('video_call', 'billing', 'qc', 'packaging', 'dispatch')),
  status text NOT NULL CHECK (status IN ('assigned', 'in_progress', 'completed', 'rejected')),
  assigned_at timestamptz DEFAULT now(),
  completed_at timestamptz,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create profiling_questions table
CREATE TABLE IF NOT EXISTS profiling_questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category text NOT NULL,
  question text NOT NULL,
  options jsonb NOT NULL,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create profiling_responses table
CREATE TABLE IF NOT EXISTS profiling_responses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid REFERENCES customers(id),
  video_call_id uuid REFERENCES video_calls(id),
  question_id uuid REFERENCES profiling_questions(id),
  response text NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE workflow_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiling_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiling_responses ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on workflow_assignments"
  ON workflow_assignments FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on workflow_assignments"
  ON workflow_assignments FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on workflow_assignments"
  ON workflow_assignments FOR UPDATE TO public USING (true) WITH CHECK (true);

CREATE POLICY "Allow public read access on profiling_questions"
  ON profiling_questions FOR SELECT TO public USING (true);

CREATE POLICY "Allow public read access on profiling_responses"
  ON profiling_responses FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on profiling_responses"
  ON profiling_responses FOR INSERT TO public WITH CHECK (true);

-- Insert default profiling questions
INSERT INTO profiling_questions (category, question, options) VALUES
  ('preferences', 'What type of jewelry do you prefer?', '["Gold", "Diamond", "Platinum", "Silver", "Gemstones"]'),
  ('preferences', 'What is your typical budget range for jewelry?', '["Under ₹50,000", "₹50,000-1,00,000", "₹1,00,000-5,00,000", "Above ₹5,00,000"]'),
  ('preferences', 'How often do you purchase jewelry?', '["Monthly", "Quarterly", "Yearly", "Special Occasions Only"]'),
  ('preferences', 'What is the primary purpose of your jewelry purchases?', '["Personal Use", "Investment", "Gifting", "Special Occasions", "Business"]'),
  ('style', 'Which jewelry style do you prefer?', '["Traditional", "Modern", "Contemporary", "Minimalist", "Statement"]'),
  ('style', 'What metal color do you prefer?', '["Yellow Gold", "White Gold", "Rose Gold", "Mixed Metals"]'),
  ('style', 'Do you prefer handcrafted or machine-made jewelry?', '["Handcrafted", "Machine-made", "Both", "No Preference"]'),
  ('business', 'What is your target customer segment?', '["Mass Market", "Premium", "Luxury", "All Segments"]'),
  ('business', 'What is your preferred payment method?', '["Cash", "Bank Transfer", "Credit Card", "Financing"]'),
  ('business', 'What is your typical order volume?', '["1-5 pieces", "6-20 pieces", "21-50 pieces", "50+ pieces"]');

-- Create function to update workflow status
CREATE OR REPLACE FUNCTION update_workflow_status()
RETURNS TRIGGER AS $$
BEGIN
  -- Update workflow status based on assignment completion
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    UPDATE video_calls
    SET workflow_status = jsonb_set(
      workflow_status,
      ARRAY[NEW.role],
      '"completed"'
    )
    WHERE id = NEW.video_call_id;
    
    -- Create notification for next step
    INSERT INTO notifications (
      user_id,
      type,
      title,
      message,
      data
    ) VALUES (
      NEW.staff_id,
      'workflow_update',
      'Workflow Step Completed',
      format('The %s step has been completed for video call #%s', NEW.role, NEW.video_call_id),
      jsonb_build_object(
        'video_call_id', NEW.video_call_id,
        'role', NEW.role,
        'completed_at', NEW.completed_at
      )
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for workflow status updates
DROP TRIGGER IF EXISTS workflow_status_trigger ON workflow_assignments;

CREATE TRIGGER workflow_status_trigger
  AFTER UPDATE OF status ON workflow_assignments
  FOR EACH ROW
  EXECUTE FUNCTION update_workflow_status();
