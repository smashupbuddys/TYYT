-- Create staff_performance_metrics table
CREATE TABLE IF NOT EXISTS staff_performance_metrics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid REFERENCES staff(id) ON DELETE CASCADE,
  video_call_id uuid REFERENCES video_calls(id) ON DELETE CASCADE,
  call_duration integer NOT NULL, -- Duration in minutes
  total_items_sold integer DEFAULT 0,
  total_sales_value numeric DEFAULT 0,
  conversion_successful boolean DEFAULT false,
  customer_satisfaction_score integer CHECK (customer_satisfaction_score BETWEEN 1 AND 5),
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE staff_performance_metrics ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on staff_performance_metrics"
  ON staff_performance_metrics FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on staff_performance_metrics"
  ON staff_performance_metrics FOR INSERT TO public WITH CHECK (true);

-- Create function to track staff performance
CREATE OR REPLACE FUNCTION track_staff_performance()
RETURNS TRIGGER AS $$
DECLARE
  v_duration integer;
  v_total_items integer;
  v_total_value numeric;
  v_quotation record;
BEGIN
  -- Calculate call duration
  v_duration := EXTRACT(EPOCH FROM (now() - OLD.scheduled_at)) / 60;

  -- Get quotation details if exists
  SELECT 
    SUM((item->>'quantity')::integer) as total_items,
    SUM((item->>'quantity')::integer * (item->>'price')::numeric) as total_value
  INTO v_total_items, v_total_value
  FROM quotations q,
  jsonb_array_elements(q.items) item
  WHERE q.video_call_id = NEW.id
  AND q.status = 'accepted';

  -- Create performance record
  INSERT INTO staff_performance_metrics (
    staff_id,
    video_call_id,
    call_duration,
    total_items_sold,
    total_sales_value,
    conversion_successful
  ) VALUES (
    NEW.staff_id,
    NEW.id,
    v_duration,
    COALESCE(v_total_items, 0),
    COALESCE(v_total_value, 0),
    NEW.quotation_id IS NOT NULL
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for staff performance tracking
CREATE TRIGGER track_staff_performance_trigger
  AFTER UPDATE OF status ON video_calls
  FOR EACH ROW
  WHEN (NEW.status = 'completed')
  EXECUTE FUNCTION track_staff_performance();

-- Add indexes for better performance
CREATE INDEX idx_staff_performance_metrics_staff_id 
  ON staff_performance_metrics(staff_id);
CREATE INDEX idx_staff_performance_metrics_video_call_id 
  ON staff_performance_metrics(video_call_id);

-- Add helpful comment
COMMENT ON TABLE staff_performance_metrics IS 'Tracks staff performance metrics including call duration and sales data';