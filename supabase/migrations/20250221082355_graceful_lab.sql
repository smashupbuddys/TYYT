-- Drop existing objects if they exist
DO $$ 
BEGIN
  -- Drop existing triggers
  DROP TRIGGER IF EXISTS update_manufacturer_analytics_products ON products;
  DROP TRIGGER IF EXISTS update_manufacturer_analytics_quotations ON quotations;
  
  -- Drop existing functions
  DROP FUNCTION IF EXISTS update_manufacturer_analytics();
  DROP FUNCTION IF EXISTS get_manufacturer_analytics(date, date);
  
  -- Drop existing table
  DROP TABLE IF EXISTS manufacturer_analytics;
END $$;

-- Create manufacturer analytics table
CREATE TABLE manufacturer_analytics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  manufacturer text NOT NULL,
  month date NOT NULL,
  purchases jsonb DEFAULT '{
    "total_amount": 0,
    "total_items": 0,
    "categories": {}
  }',
  sales jsonb DEFAULT '{
    "total_amount": 0,
    "total_items": 0,
    "categories": {}
  }',
  dead_stock jsonb DEFAULT '{
    "total_items": 0,
    "total_value": 0,
    "items": []
  }',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Add unique constraint for manufacturer and month
CREATE UNIQUE INDEX idx_manufacturer_month 
  ON manufacturer_analytics(manufacturer, month);

-- Enable RLS
ALTER TABLE manufacturer_analytics ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on manufacturer_analytics"
  ON manufacturer_analytics FOR SELECT TO public USING (true);

-- Create function to update manufacturer analytics
CREATE OR REPLACE FUNCTION update_manufacturer_analytics()
RETURNS TRIGGER AS $$
DECLARE
  current_month date;
  dead_stock_period interval;
  category_data jsonb;
  manufacturer_record record;
BEGIN
  -- Get current month (first day)
  current_month := date_trunc('month', CURRENT_DATE)::date;
  
  -- Get dead stock period from settings (default 90 days)
  SELECT COALESCE(
    (SELECT (value->>'days')::integer * interval '1 day'
     FROM company_settings,
     jsonb_each(video_call_settings) AS s(key, value)
     WHERE key = 'dead_stock_period'
    ),
    interval '90 days'
  ) INTO dead_stock_period;

  -- For purchases (triggered by product updates)
  IF TG_TABLE_NAME = 'products' THEN
    -- Get category data
    SELECT jsonb_build_object(
      NEW.category,
      jsonb_build_object(
        'quantity', NEW.stock_level,
        'value', NEW.buy_price * NEW.stock_level
      )
    ) INTO category_data;

    -- Insert or update monthly record
    INSERT INTO manufacturer_analytics (manufacturer, month, purchases)
    VALUES (
      NEW.manufacturer,
      current_month,
      jsonb_build_object(
        'total_amount', NEW.buy_price * NEW.stock_level,
        'total_items', NEW.stock_level,
        'categories', category_data
      )
    )
    ON CONFLICT (manufacturer, month) DO UPDATE
    SET 
      purchases = jsonb_set(
        jsonb_set(
          jsonb_set(
            manufacturer_analytics.purchases,
            '{total_amount}',
            to_jsonb(COALESCE((manufacturer_analytics.purchases->>'total_amount')::numeric, 0) + 
                    (NEW.buy_price * NEW.stock_level))
          ),
          '{total_items}',
          to_jsonb(COALESCE((manufacturer_analytics.purchases->>'total_items')::integer, 0) + 
                  NEW.stock_level)
        ),
        '{categories}',
        COALESCE(manufacturer_analytics.purchases->'categories', '{}'::jsonb) || category_data
      ),
      updated_at = now();
  END IF;

  -- Update dead stock for the manufacturer
  FOR manufacturer_record IN 
    SELECT DISTINCT manufacturer 
    FROM products 
    WHERE manufacturer = COALESCE(NEW.manufacturer, OLD.manufacturer)
  LOOP
    UPDATE manufacturer_analytics ma
    SET dead_stock = (
      SELECT jsonb_build_object(
        'total_items', COALESCE(SUM(p.stock_level), 0),
        'total_value', COALESCE(SUM(p.stock_level * p.buy_price), 0),
        'items', COALESCE(
          jsonb_agg(
            jsonb_build_object(
              'id', p.id,
              'sku', p.sku,
              'name', p.name,
              'category', p.category,
              'stock_level', p.stock_level,
              'buy_price', p.buy_price,
              'last_sold', p.last_sold_at
            )
          ) FILTER (WHERE p.id IS NOT NULL),
          '[]'::jsonb
        )
      )
      FROM products p
      WHERE p.manufacturer = manufacturer_record.manufacturer
      AND (p.last_sold_at IS NULL OR p.last_sold_at < CURRENT_DATE - dead_stock_period)
      AND p.stock_level > 0
    )
    WHERE ma.manufacturer = manufacturer_record.manufacturer
    AND ma.month = current_month;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
CREATE TRIGGER update_manufacturer_analytics_products
  AFTER INSERT OR UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION update_manufacturer_analytics();

-- Create function to get manufacturer analytics
CREATE OR REPLACE FUNCTION get_manufacturer_analytics(
  start_date date,
  end_date date
) RETURNS TABLE (
  manufacturer text,
  month date,
  purchases jsonb,
  sales jsonb,
  dead_stock jsonb
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    ma.manufacturer,
    ma.month,
    ma.purchases,
    ma.sales,
    ma.dead_stock
  FROM manufacturer_analytics ma
  WHERE ma.month BETWEEN start_date AND end_date
  ORDER BY ma.manufacturer, ma.month;
END;
$$ LANGUAGE plpgsql;