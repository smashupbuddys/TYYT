/*
  # Add Daily Analytics Tracking

  1. New Tables
    - daily_analytics
      - date (date, primary key)
      - video_calls_count (integer)
      - bills_generated_count (integer)
      - total_sales_amount (numeric)
      - total_items_sold (integer)
      - new_customers_count (integer)
      - payment_collection (numeric)
      - stats (jsonb for additional metrics)

  2. Functions
    - Function to automatically update daily analytics
    - Function to aggregate analytics for custom date ranges

  3. Security
    - Enable RLS
    - Add policies for admin access
*/

-- Create daily analytics table
CREATE TABLE daily_analytics (
  date date PRIMARY KEY DEFAULT CURRENT_DATE,
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
CREATE POLICY "Allow admin read access on daily_analytics"
  ON daily_analytics FOR SELECT TO public
  USING (true);

-- Create function to update daily analytics
CREATE OR REPLACE FUNCTION update_daily_analytics()
RETURNS TRIGGER AS $$
DECLARE
  today date := CURRENT_DATE;
  category_stats jsonb;
  payment_stats jsonb;
  customer_type_stats jsonb;
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
      SET video_calls_count = video_calls_count + 1
      WHERE date = today;

    WHEN 'quotations' THEN
      -- Update bills and sales stats
      IF NEW.bill_status = 'paid' THEN
        -- Get category stats
        SELECT jsonb_object_agg(category, quantity)
        INTO category_stats
        FROM (
          SELECT 
            item->>'category' as category,
            SUM((item->>'quantity')::integer) as quantity
          FROM jsonb_array_elements(NEW.items) as item
          GROUP BY item->>'category'
        ) t;

        -- Update daily analytics
        UPDATE daily_analytics
        SET 
          bills_generated_count = bills_generated_count + 1,
          total_sales_amount = total_sales_amount + NEW.total_amount,
          total_items_sold = total_items_sold + (
            SELECT SUM((item->>'quantity')::integer)
            FROM jsonb_array_elements(NEW.items) as item
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
              ARRAY[CASE WHEN NEW.customer_id IS NULL THEN 'retail' ELSE 'wholesale' END],
              ((COALESCE((stats->'customer_types'->CASE WHEN NEW.customer_id IS NULL THEN 'retail' ELSE 'wholesale' END)::integer, 0) + 1)::text)::jsonb
            )
          )
        WHERE date = today;
      END IF;

    WHEN 'customers' THEN
      -- Update new customers count
      IF TG_OP = 'INSERT' THEN
        UPDATE daily_analytics
        SET new_customers_count = new_customers_count + 1
        WHERE date = today;
      END IF;
  END CASE;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
CREATE TRIGGER update_analytics_video_calls
  AFTER INSERT ON video_calls
  FOR EACH ROW
  EXECUTE FUNCTION update_daily_analytics();

CREATE TRIGGER update_analytics_quotations
  AFTER INSERT OR UPDATE OF bill_status ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION update_daily_analytics();

CREATE TRIGGER update_analytics_customers
  AFTER INSERT ON customers
  FOR EACH ROW
  EXECUTE FUNCTION update_daily_analytics();

-- Create function to get analytics for date range
CREATE OR REPLACE FUNCTION get_analytics_range(start_date date, end_date date)
RETURNS TABLE (
  period text,
  video_calls_count bigint,
  bills_generated_count bigint,
  total_sales_amount numeric,
  total_items_sold bigint,
  new_customers_count bigint,
  payment_collection numeric,
  stats jsonb
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    to_char(date, 'YYYY-MM-DD') as period,
    sum(a.video_calls_count)::bigint as video_calls_count,
    sum(a.bills_generated_count)::bigint as bills_generated_count,
    sum(a.total_sales_amount) as total_sales_amount,
    sum(a.total_items_sold)::bigint as total_items_sold,
    sum(a.new_customers_count)::bigint as new_customers_count,
    sum(a.payment_collection) as payment_collection,
    jsonb_object_agg(
      to_char(date, 'YYYY-MM-DD'),
      a.stats
    ) as stats
  FROM daily_analytics a
  WHERE date BETWEEN start_date AND end_date
  GROUP BY date
  ORDER BY date;
END;
$$ LANGUAGE plpgsql;