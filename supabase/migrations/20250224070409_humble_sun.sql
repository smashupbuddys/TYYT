-- Drop existing trigger first
DROP TRIGGER IF EXISTS track_staff_performance_trigger ON video_calls;

-- Create improved staff performance tracking function without duration check
CREATE OR REPLACE FUNCTION track_staff_performance()
RETURNS TRIGGER AS $$
DECLARE
  v_duration integer;
  v_total_items integer;
  v_total_value numeric;
  v_quotation record;
BEGIN
  -- Calculate actual call duration for metrics only
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

-- Recreate trigger without duration check
CREATE TRIGGER track_staff_performance_trigger
  AFTER UPDATE OF status ON video_calls
  FOR EACH ROW
  WHEN (NEW.status = 'completed')
  EXECUTE FUNCTION track_staff_performance();