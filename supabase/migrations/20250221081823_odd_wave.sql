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
  dead_stock_items jsonb;
  item_record record;
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
    -- Insert or update monthly record
    INSERT INTO manufacturer_analytics (manufacturer, month)
    VALUES (NEW.manufacturer, current_month)
    ON CONFLICT (manufacturer, month) DO UPDATE
    SET purchases = jsonb_set(
      manufacturer_analytics.purchases,
      '{total_amount}',
      (COALESCE((manufacturer_analytics.purchases->>'total_amount')::numeric, 0) + 
       (NEW.buy_price * NEW.stock_level))::text::jsonb
    ),
    purchases = jsonb_set(
      manufacturer_analytics.purchases,
      '{total_items}',
      (COALESCE((manufacturer_analytics.purchases->>'total_items')::integer, 0) + 
       NEW.stock_level)::text::jsonb
    ),
    updated_at = now();

  -- For sales (triggered by quotations)
  ELSIF TG_TABLE_NAME = 'quotations' AND NEW.status = 'accepted' THEN
    -- Process each item in the quotation
    FOR item_record IN 
      SELECT 
        p.manufacturer,
        p.category,
        (i->>'quantity')::integer as quantity,
        (i->>'price')::numeric as price
      FROM jsonb_array_elements(NEW.items) as i
      JOIN products p ON p.id = (i->>'product_id')::uuid
    LOOP
      -- Update manufacturer analytics
      INSERT INTO manufacturer_analytics (manufacturer, month)
      VALUES (item_record.manufacturer, current_month)
      ON CONFLICT (manufacturer, month) DO UPDATE
      SET sales = jsonb_set(
        manufacturer_analytics.sales,
        '{total_amount}',
        (COALESCE((manufacturer_analytics.sales->>'total_amount')::numeric, 0) + 
         (item_record.price * item_record.quantity))::text::jsonb
      ),
      sales = jsonb_set(
        manufacturer_analytics.sales,
        '{total_items}',
        (COALESCE((manufacturer_analytics.sales->>'total_items')::integer, 0) + 
         item_record.quantity)::text::jsonb
      ),
      updated_at = now();
    END LOOP;
  END IF;

  -- Update dead stock for all manufacturers
  UPDATE manufacturer_analytics
  SET dead_stock = (
    SELECT jsonb_build_object(
      'total_items', SUM(p.stock_level),
      'total_value', SUM(p.stock_level * p.buy_price),
      'items', jsonb_agg(jsonb_build_object(
        'id', p.id,
        'sku', p.sku,
        'name', p.name,
        'category', p.category,
        'stock_level', p.stock_level,
        'buy_price', p.buy_price,
        'last_sold', p.last_sold_at
      ))
    )
    FROM products p
    WHERE p.manufacturer = manufacturer_analytics.manufacturer
    AND (p.last_sold_at IS NULL OR p.last_sold_at < CURRENT_DATE - dead_stock_period)
    AND p.stock_level > 0
    GROUP BY p.manufacturer
  )
  WHERE month = current_month;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
CREATE TRIGGER update_manufacturer_analytics_products
  AFTER INSERT OR UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION update_manufacturer_analytics();

CREATE TRIGGER update_manufacturer_analytics_quotations
  AFTER INSERT OR UPDATE OF status ON quotations
  FOR EACH ROW
  WHEN (NEW.status = 'accepted')
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