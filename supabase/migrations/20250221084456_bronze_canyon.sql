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

CREATE POLICY "Allow public insert access on manufacturer_analytics"
  ON manufacturer_analytics FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on manufacturer_analytics"
  ON manufacturer_analytics FOR UPDATE TO public USING (true) WITH CHECK (true);

CREATE POLICY "Allow public delete access on manufacturer_analytics"
  ON manufacturer_analytics FOR DELETE TO public USING (true);

-- Create function to update manufacturer analytics
CREATE OR REPLACE FUNCTION update_manufacturer_analytics()
RETURNS TRIGGER AS $$
DECLARE
  current_month date;
  category_data jsonb;
  manufacturer_record record;
BEGIN
  -- Get current month (first day)
  current_month := date_trunc('month', CURRENT_DATE)::date;

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

  -- For sales (triggered by quotations)
  IF TG_TABLE_NAME = 'quotations' AND NEW.status = 'accepted' THEN
    -- Process each item in the quotation
    FOR manufacturer_record IN 
      SELECT DISTINCT p.manufacturer
      FROM jsonb_array_elements(NEW.items) as i
      JOIN products p ON p.id = (i->>'product_id')::uuid
    LOOP
      -- Update manufacturer analytics
      WITH item_totals AS (
        SELECT 
          SUM((i->>'quantity')::integer) as total_quantity,
          SUM((i->>'quantity')::integer * (i->>'price')::numeric) as total_amount,
          jsonb_object_agg(
            p.category,
            jsonb_build_object(
              'quantity', SUM((i->>'quantity')::integer),
              'value', SUM((i->>'quantity')::integer * (i->>'price')::numeric)
            )
          ) as categories
        FROM jsonb_array_elements(NEW.items) as i
        JOIN products p ON p.id = (i->>'product_id')::uuid
        WHERE p.manufacturer = manufacturer_record.manufacturer
        GROUP BY p.manufacturer
      )
      INSERT INTO manufacturer_analytics (
        manufacturer,
        month,
        sales
      )
      SELECT
        manufacturer_record.manufacturer,
        current_month,
        jsonb_build_object(
          'total_amount', total_amount,
          'total_items', total_quantity,
          'categories', categories
        )
      FROM item_totals
      ON CONFLICT (manufacturer, month) DO UPDATE
      SET sales = jsonb_set(
        jsonb_set(
          jsonb_set(
            manufacturer_analytics.sales,
            '{total_amount}',
            to_jsonb(COALESCE((manufacturer_analytics.sales->>'total_amount')::numeric, 0) + 
                    EXCLUDED.sales->>'total_amount')
          ),
          '{total_items}',
          to_jsonb(COALESCE((manufacturer_analytics.sales->>'total_items')::integer, 0) + 
                  (EXCLUDED.sales->>'total_items')::integer)
        ),
        '{categories}',
        COALESCE(manufacturer_analytics.sales->'categories', '{}'::jsonb) || 
        (EXCLUDED.sales->'categories')
      );
    END LOOP;
  END IF;

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