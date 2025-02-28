-- Create daily_analytics table if it doesn't exist
CREATE TABLE IF NOT EXISTS daily_analytics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  date date UNIQUE NOT NULL DEFAULT CURRENT_DATE,
  video_calls_count integer DEFAULT 0,
  bills_generated_count integer DEFAULT 0,
  total_sales_amount numeric DEFAULT 0,
  total_items_sold integer DEFAULT 0,
  new_customers_count integer DEFAULT 0,
  payment_collection numeric DEFAULT 0,
  stats jsonb DEFAULT '{
    "categories": {},
    "payment_methods": {},
    "customer_types": {
      "retail": 0,
      "wholesale": 0
    }
  }',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE daily_analytics ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on daily_analytics"
  ON daily_analytics FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on daily_analytics"
  ON daily_analytics FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on daily_analytics"
  ON daily_analytics FOR UPDATE TO public USING (true);

-- Create function to update daily analytics
CREATE OR REPLACE FUNCTION update_daily_analytics()
RETURNS TRIGGER AS $$
DECLARE
  today date := CURRENT_DATE;
  customer_type text;
  category_stats jsonb;
BEGIN
  -- Initialize or get today's record
  INSERT INTO daily_analytics (date)
  VALUES (today)
  ON CONFLICT (date) DO NOTHING;

  -- Update based on trigger source
  CASE TG_TABLE_NAME
    WHEN 'video_calls' THEN
      -- Update video calls count
      UPDATE daily_analytics
      SET video_calls_count = video_calls_count + 1,
          updated_at = now()
      WHERE date = today;

    WHEN 'quotations' THEN
      -- Only process accepted quotations
      IF NEW.status = 'accepted' THEN
        -- Get customer type
        SELECT type INTO customer_type
        FROM customers
        WHERE id = NEW.customer_id;

        -- Get category stats
        SELECT jsonb_object_agg(
          category,
          jsonb_build_object(
            'quantity', SUM((item->>'quantity')::integer),
            'revenue', SUM((item->>'quantity')::integer * (item->>'price')::numeric)
          )
        )
        INTO category_stats
        FROM (
          SELECT 
            item->>'category' as category,
            item
          FROM jsonb_array_elements(NEW.items) item
        ) t
        GROUP BY category;

        -- Update daily analytics
        UPDATE daily_analytics
        SET 
          bills_generated_count = bills_generated_count + 1,
          total_sales_amount = total_sales_amount + NEW.total_amount,
          total_items_sold = total_items_sold + (
            SELECT SUM((item->>'quantity')::integer)
            FROM jsonb_array_elements(NEW.items) item
          ),
          stats = jsonb_set(
            jsonb_set(
              stats,
              '{categories}',
              COALESCE(stats->'categories', '{}'::jsonb) || category_stats
            ),
            '{customer_types}',
            jsonb_set(
              COALESCE(stats->'customer_types', '{}'::jsonb),
              ARRAY[customer_type],
              to_jsonb(COALESCE((stats->'customer_types'->customer_type)::integer, 0) + 1)
            )
          ),
          updated_at = now()
        WHERE date = today;
      END IF;

    WHEN 'customers' THEN
      -- Update new customers count
      IF TG_OP = 'INSERT' THEN
        UPDATE daily_analytics
        SET 
          new_customers_count = new_customers_count + 1,
          updated_at = now()
        WHERE date = today;
      END IF;
  END CASE;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
DROP TRIGGER IF EXISTS update_analytics_video_calls ON video_calls;
CREATE TRIGGER update_analytics_video_calls
  AFTER INSERT ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION update_daily_analytics();

DROP TRIGGER IF EXISTS update_analytics_quotations ON quotations;
CREATE TRIGGER update_analytics_quotations
  AFTER INSERT OR UPDATE OF status ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION update_daily_analytics();

DROP TRIGGER IF EXISTS update_analytics_customers ON customers;
CREATE TRIGGER update_analytics_customers
  AFTER INSERT ON customers
  FOR EACH ROW
  EXECUTE FUNCTION update_daily_analytics();

-- Add indexes for better performance
CREATE INDEX idx_daily_analytics_date ON daily_analytics(date);

-- Add helpful comments
COMMENT ON TABLE daily_analytics IS 'Stores daily business metrics and analytics';
COMMENT ON COLUMN daily_analytics.stats IS 'JSON object containing detailed statistics by category and customer type';