/*
  # Staff Performance Tracking

  1. New Tables
    - staff_performance_metrics
      - Tracks individual staff member performance metrics
    - staff_ratings
      - Stores customer satisfaction ratings
    - staff_sales_targets
      - Manages sales targets and goals
    - staff_performance_history
      - Maintains historical performance data

  2. Functions
    - Automatic performance calculation
    - Rating aggregation
    - Target tracking
    
  3. Triggers
    - Update performance metrics on sales
    - Calculate satisfaction scores
    - Track payment completion impact
*/

-- Create staff performance metrics table
CREATE TABLE staff_performance_metrics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid REFERENCES staff(id) ON DELETE CASCADE,
  period_start date NOT NULL,
  period_end date NOT NULL,
  video_calls_total integer DEFAULT 0,
  video_calls_completed integer DEFAULT 0,
  sales_conversion_rate numeric DEFAULT 0,
  total_sales_value numeric DEFAULT 0,
  completed_sales_value numeric DEFAULT 0,
  average_satisfaction_score numeric DEFAULT 0,
  performance_score numeric DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create staff ratings table
CREATE TABLE staff_ratings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid REFERENCES staff(id) ON DELETE CASCADE,
  video_call_id uuid REFERENCES video_calls(id) ON DELETE CASCADE,
  customer_id uuid REFERENCES customers(id) ON DELETE CASCADE,
  rating integer CHECK (rating >= 1 AND rating <= 5),
  feedback text,
  created_at timestamptz DEFAULT now()
);

-- Create staff sales targets table
CREATE TABLE staff_sales_targets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid REFERENCES staff(id) ON DELETE CASCADE,
  period_start date NOT NULL,
  period_end date NOT NULL,
  target_calls integer NOT NULL,
  target_sales_value numeric NOT NULL,
  target_conversion_rate numeric NOT NULL,
  target_satisfaction_score numeric NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create staff performance history table
CREATE TABLE staff_performance_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid REFERENCES staff(id) ON DELETE CASCADE,
  metric_type text NOT NULL,
  metric_value numeric NOT NULL,
  recorded_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE staff_performance_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_sales_targets ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_performance_history ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on staff_performance_metrics"
  ON staff_performance_metrics FOR SELECT TO public USING (true);

CREATE POLICY "Allow public read access on staff_ratings"
  ON staff_ratings FOR SELECT TO public USING (true);

CREATE POLICY "Allow public read access on staff_sales_targets"
  ON staff_sales_targets FOR SELECT TO public USING (true);

CREATE POLICY "Allow public read access on staff_performance_history"
  ON staff_performance_history FOR SELECT TO public USING (true);

-- Create function to calculate performance score
CREATE OR REPLACE FUNCTION calculate_performance_score(
  p_calls_completed integer,
  p_calls_total integer,
  p_sales_completed numeric,
  p_sales_total numeric,
  p_satisfaction_score numeric
) RETURNS numeric AS $$
DECLARE
  v_conversion_weight numeric := 0.3;
  v_payment_weight numeric := 0.4;
  v_satisfaction_weight numeric := 0.3;
  v_conversion_rate numeric;
  v_payment_rate numeric;
BEGIN
  -- Calculate conversion rate (completed calls / total calls)
  v_conversion_rate := CASE 
    WHEN p_calls_total > 0 THEN (p_calls_completed::numeric / p_calls_total::numeric) * 100
    ELSE 0
  END;

  -- Calculate payment completion rate (completed sales / total sales)
  v_payment_rate := CASE 
    WHEN p_sales_total > 0 THEN (p_sales_completed / p_sales_total) * 100
    ELSE 0
  END;

  -- Calculate weighted score
  RETURN (
    (v_conversion_rate * v_conversion_weight) +
    (v_payment_rate * v_payment_weight) +
    (p_satisfaction_score * v_satisfaction_weight)
  );
END;
$$ LANGUAGE plpgsql;

-- Create function to update performance metrics
CREATE OR REPLACE FUNCTION update_staff_performance()
RETURNS TRIGGER AS $$
DECLARE
  v_period_start date;
  v_period_end date;
  v_metrics record;
BEGIN
  -- Get current month period
  v_period_start := date_trunc('month', CURRENT_DATE)::date;
  v_period_end := (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date;

  -- Get or create performance metrics record
  INSERT INTO staff_performance_metrics (
    staff_id,
    period_start,
    period_end
  ) VALUES (
    NEW.staff_id,
    v_period_start,
    v_period_end
  ) ON CONFLICT (staff_id, period_start) DO NOTHING;

  -- Update metrics
  WITH metrics AS (
    SELECT
      COUNT(*) as total_calls,
      COUNT(*) FILTER (WHERE status = 'completed') as completed_calls,
      SUM(CASE WHEN quotation_id IS NOT NULL THEN 1 ELSE 0 END) as sales_converted,
      COALESCE(SUM(bill_amount) FILTER (WHERE bill_status = 'paid'), 0) as completed_sales,
      COALESCE(SUM(bill_amount), 0) as total_sales
    FROM video_calls
    WHERE staff_id = NEW.staff_id
    AND scheduled_at >= v_period_start
    AND scheduled_at <= v_period_end
  ),
  satisfaction AS (
    SELECT COALESCE(AVG(rating), 0) as avg_rating
    FROM staff_ratings
    WHERE staff_id = NEW.staff_id
    AND created_at >= v_period_start
    AND created_at <= v_period_end
  )
  UPDATE staff_performance_metrics
  SET
    video_calls_total = metrics.total_calls,
    video_calls_completed = metrics.completed_calls,
    sales_conversion_rate = CASE 
      WHEN metrics.total_calls > 0 
      THEN (metrics.sales_converted::numeric / metrics.total_calls::numeric) * 100
      ELSE 0
    END,
    total_sales_value = metrics.total_sales,
    completed_sales_value = metrics.completed_sales,
    average_satisfaction_score = satisfaction.avg_rating,
    performance_score = calculate_performance_score(
      metrics.completed_calls,
      metrics.total_calls,
      metrics.completed_sales,
      metrics.total_sales,
      satisfaction.avg_rating
    ),
    updated_at = now()
  FROM metrics, satisfaction
  WHERE staff_id = NEW.staff_id
  AND period_start = v_period_start;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
CREATE TRIGGER update_staff_performance_trigger
  AFTER INSERT OR UPDATE OF status, bill_status, bill_amount
  ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION update_staff_performance();

-- Create function to get staff performance report
CREATE OR REPLACE FUNCTION get_staff_performance_report(
  p_start_date date,
  p_end_date date,
  p_staff_id uuid DEFAULT NULL
)
RETURNS TABLE (
  staff_id uuid,
  staff_name text,
  video_calls_total integer,
  video_calls_completed integer,
  sales_conversion_rate numeric,
  total_sales_value numeric,
  completed_sales_value numeric,
  average_satisfaction_score numeric,
  performance_score numeric,
  target_achievement numeric
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.id as staff_id,
    s.name as staff_name,
    pm.video_calls_total,
    pm.video_calls_completed,
    pm.sales_conversion_rate,
    pm.total_sales_value,
    pm.completed_sales_value,
    pm.average_satisfaction_score,
    pm.performance_score,
    CASE
      WHEN st.target_sales_value > 0 THEN
        (pm.completed_sales_value / st.target_sales_value) * 100
      ELSE 0
    END as target_achievement
  FROM staff s
  LEFT JOIN staff_performance_metrics pm ON s.id = pm.staff_id
  LEFT JOIN staff_sales_targets st ON s.id = st.staff_id
  WHERE (p_staff_id IS NULL OR s.id = p_staff_id)
  AND pm.period_start >= p_start_date
  AND pm.period_end <= p_end_date
  ORDER BY pm.performance_score DESC;
END;
$$ LANGUAGE plpgsql;