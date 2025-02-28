-- Add dead stock settings to company_settings
ALTER TABLE company_settings
  ADD COLUMN IF NOT EXISTS dead_stock_settings jsonb DEFAULT '{
    "thresholds": {
      "warning": 60,
      "critical": 90
    },
    "categories": {}
  }';

-- Create function to update dead stock settings
CREATE OR REPLACE FUNCTION update_dead_stock_settings(
  category text,
  warning_days integer,
  critical_days integer
) RETURNS void AS $$
BEGIN
  UPDATE company_settings
  SET dead_stock_settings = jsonb_set(
    dead_stock_settings,
    '{categories}',
    COALESCE(dead_stock_settings->'categories', '{}'::jsonb) || 
    jsonb_build_object(
      category,
      jsonb_build_object(
        'warning', warning_days,
        'critical', critical_days
      )
    )
  )
  WHERE settings_key = 1;
END;
$$ LANGUAGE plpgsql;

-- Create function to check dead stock status
CREATE OR REPLACE FUNCTION get_dead_stock_status(
  category text,
  last_sold_at timestamptz
) RETURNS text AS $$
DECLARE
  settings jsonb;
  warning_days integer;
  critical_days integer;
  days_since_sold integer;
BEGIN
  -- Get category-specific or default thresholds
  SELECT dead_stock_settings INTO settings
  FROM company_settings
  WHERE settings_key = 1;

  warning_days := COALESCE(
    (settings->'categories'->category->>'warning')::integer,
    (settings->'thresholds'->>'warning')::integer,
    60
  );
  
  critical_days := COALESCE(
    (settings->'categories'->category->>'critical')::integer,
    (settings->'thresholds'->>'critical')::integer,
    90
  );

  -- Calculate days since last sold
  IF last_sold_at IS NULL THEN
    days_since_sold := 999999; -- Very large number for never sold items
  ELSE
    days_since_sold := EXTRACT(DAY FROM (NOW() - last_sold_at));
  END IF;

  -- Return status based on thresholds
  RETURN CASE
    WHEN days_since_sold >= critical_days THEN 'critical'
    WHEN days_since_sold >= warning_days THEN 'warning'
    ELSE 'normal'
  END;
END;
$$ LANGUAGE plpgsql;

-- Create function to get dead stock report
CREATE OR REPLACE FUNCTION get_dead_stock_report(
  manufacturer_filter text DEFAULT NULL
) RETURNS TABLE (
  manufacturer text,
  category text,
  total_items integer,
  total_value numeric,
  status text,
  items jsonb
) AS $$
BEGIN
  RETURN QUERY
  WITH product_status AS (
    SELECT
      p.manufacturer,
      p.category,
      p.id,
      p.sku,
      p.name,
      p.stock_level,
      p.buy_price,
      p.last_sold_at,
      get_dead_stock_status(p.category, p.last_sold_at) as item_status
    FROM products p
    WHERE 
      (manufacturer_filter IS NULL OR p.manufacturer = manufacturer_filter)
      AND p.stock_level > 0
  )
  SELECT
    ps.manufacturer,
    ps.category,
    SUM(ps.stock_level)::integer as total_items,
    SUM(ps.stock_level * ps.buy_price) as total_value,
    MAX(ps.item_status) as status,
    jsonb_agg(
      jsonb_build_object(
        'id', ps.id,
        'sku', ps.sku,
        'name', ps.name,
        'stock_level', ps.stock_level,
        'buy_price', ps.buy_price,
        'value', ps.stock_level * ps.buy_price,
        'last_sold', ps.last_sold_at,
        'status', ps.item_status
      )
    ) as items
  FROM product_status ps
  WHERE ps.item_status IN ('warning', 'critical')
  GROUP BY ps.manufacturer, ps.category
  ORDER BY ps.manufacturer, total_value DESC;
END;
$$ LANGUAGE plpgsql;

-- Update existing company settings with default dead stock settings
UPDATE company_settings
SET dead_stock_settings = '{
  "thresholds": {
    "warning": 60,
    "critical": 90
  },
  "categories": {
    "Rings": {
      "warning": 45,
      "critical": 75
    },
    "Necklaces": {
      "warning": 45,
      "critical": 75
    },
    "Earrings": {
      "warning": 30,
      "critical": 60
    },
    "Bracelets": {
      "warning": 45,
      "critical": 75
    },
    "Watches": {
      "warning": 60,
      "critical": 90
    }
  }
}'::jsonb
WHERE settings_key = 1
  AND (dead_stock_settings IS NULL OR dead_stock_settings = '{}'::jsonb);