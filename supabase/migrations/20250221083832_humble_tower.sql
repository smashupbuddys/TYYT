-- Add dead stock settings to products table
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS dead_stock_status text 
    CHECK (dead_stock_status IN ('normal', 'warning', 'critical')),
  ADD COLUMN IF NOT EXISTS dead_stock_days integer;

-- Create dead stock settings table
CREATE TABLE IF NOT EXISTS dead_stock_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category text NOT NULL,
  warning_days integer NOT NULL DEFAULT 60,
  critical_days integer NOT NULL DEFAULT 90,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE dead_stock_settings ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on dead_stock_settings"
  ON dead_stock_settings FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on dead_stock_settings"
  ON dead_stock_settings FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on dead_stock_settings"
  ON dead_stock_settings FOR UPDATE TO public USING (true) WITH CHECK (true);

-- Create function to check dead stock status
CREATE OR REPLACE FUNCTION check_dead_stock_status()
RETURNS TRIGGER AS $$
DECLARE
  warning_threshold integer;
  critical_threshold integer;
  days_since_sold integer;
BEGIN
  -- Get thresholds for the product's category
  SELECT 
    warning_days, 
    critical_days 
  INTO warning_threshold, critical_threshold
  FROM dead_stock_settings 
  WHERE category = NEW.category;

  -- Use default values if no category-specific settings
  IF warning_threshold IS NULL THEN
    warning_threshold := 60;  -- Default warning threshold
    critical_threshold := 90; -- Default critical threshold
  END IF;

  -- Calculate days since last sold
  IF NEW.last_sold_at IS NULL THEN
    days_since_sold := 999999; -- Very large number for never sold items
  ELSE
    days_since_sold := EXTRACT(DAY FROM (NOW() - NEW.last_sold_at));
  END IF;

  -- Update dead stock status
  NEW.dead_stock_days := days_since_sold;
  NEW.dead_stock_status := CASE
    WHEN days_since_sold >= critical_threshold THEN 'critical'
    WHEN days_since_sold >= warning_threshold THEN 'warning'
    ELSE 'normal'
  END;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for dead stock status updates
DROP TRIGGER IF EXISTS check_dead_stock_trigger ON products;
CREATE TRIGGER check_dead_stock_trigger
  BEFORE INSERT OR UPDATE OF last_sold_at ON products
  FOR EACH ROW
  EXECUTE FUNCTION check_dead_stock_status();

-- Insert default dead stock settings
INSERT INTO dead_stock_settings (category, warning_days, critical_days) VALUES
  ('Rings', 45, 75),
  ('Necklaces', 45, 75),
  ('Earrings', 30, 60),
  ('Bracelets', 45, 75),
  ('Watches', 60, 90)
ON CONFLICT DO NOTHING;

-- Create function to get dead stock report
CREATE OR REPLACE FUNCTION get_dead_stock_report(
  manufacturer_filter text DEFAULT NULL,
  category_filter text DEFAULT NULL
) RETURNS TABLE (
  manufacturer text,
  category text,
  total_items integer,
  total_value numeric,
  items jsonb
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.manufacturer,
    p.category,
    COUNT(*)::integer as total_items,
    SUM(p.stock_level * p.buy_price) as total_value,
    jsonb_agg(jsonb_build_object(
      'id', p.id,
      'sku', p.sku,
      'name', p.name,
      'stock_level', p.stock_level,
      'buy_price', p.buy_price,
      'dead_stock_days', p.dead_stock_days,
      'dead_stock_status', p.dead_stock_status
    )) as items
  FROM products p
  WHERE p.dead_stock_status IN ('warning', 'critical')
    AND p.stock_level > 0
    AND (manufacturer_filter IS NULL OR p.manufacturer = manufacturer_filter)
    AND (category_filter IS NULL OR p.category = category_filter)
  GROUP BY p.manufacturer, p.category
  ORDER BY total_value DESC;
END;
$$ LANGUAGE plpgsql;