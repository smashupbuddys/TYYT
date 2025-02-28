-- Create manufacturer_sales_analytics table
CREATE TABLE IF NOT EXISTS manufacturer_sales_analytics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  manufacturer text NOT NULL,
  month date NOT NULL,
  sales_data jsonb NOT NULL DEFAULT '{
    "revenue": {
      "total": 0,
      "by_category": {},
      "by_customer_type": {
        "retail": 0,
        "wholesale": 0
      }
    },
    "units": {
      "total": 0,
      "by_category": {},
      "by_product": {}
    },
    "performance": {
      "top_products": [],
      "slow_moving": [],
      "conversion_rate": 0,
      "average_order_value": 0
    },
    "customer_insights": {
      "new_customers": 0,
      "repeat_customers": 0,
      "customer_segments": {}
    },
    "profitability": {
      "gross_profit": 0,
      "margin_percentage": 0,
      "by_category": {}
    }
  }',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Add unique constraint for manufacturer and month
CREATE UNIQUE INDEX idx_manufacturer_sales_month 
  ON manufacturer_sales_analytics(manufacturer, month);

-- Enable RLS
ALTER TABLE manufacturer_sales_analytics ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on manufacturer_sales_analytics"
  ON manufacturer_sales_analytics FOR SELECT TO public USING (true);

-- Create function to update sales analytics
CREATE OR REPLACE FUNCTION update_manufacturer_sales_analytics()
RETURNS TRIGGER AS $$
DECLARE
  v_month date;
  v_manufacturer text;
  v_customer_type text;
  v_product record;
  v_buy_price numeric;
  v_revenue numeric;
  v_cost numeric;
BEGIN
  -- Get the month and manufacturer
  v_month := date_trunc('month', NEW.created_at)::date;
  
  -- Process each item in the quotation
  FOR v_product IN 
    SELECT 
      p.manufacturer,
      p.category,
      p.buy_price,
      i.quantity,
      i.price,
      i.product->>'name' as name,
      i.product->>'sku' as sku
    FROM jsonb_array_elements(NEW.items) as i
    JOIN products p ON p.id = (i->>'product_id')::uuid
  LOOP
    -- Calculate revenue and cost
    v_revenue := v_product.quantity * v_product.price;
    v_cost := v_product.quantity * v_product.buy_price;
    
    -- Get customer type
    SELECT type INTO v_customer_type
    FROM customers
    WHERE id = NEW.customer_id;

    -- Update sales analytics
    INSERT INTO manufacturer_sales_analytics (
      manufacturer,
      month,
      sales_data
    ) VALUES (
      v_product.manufacturer,
      v_month,
      jsonb_build_object(
        'revenue', jsonb_build_object(
          'total', v_revenue,
          'by_category', jsonb_build_object(
            v_product.category, v_revenue
          ),
          'by_customer_type', jsonb_build_object(
            v_customer_type, v_revenue
          )
        ),
        'units', jsonb_build_object(
          'total', v_product.quantity,
          'by_category', jsonb_build_object(
            v_product.category, v_product.quantity
          ),
          'by_product', jsonb_build_object(
            v_product.sku, jsonb_build_object(
              'quantity', v_product.quantity,
              'revenue', v_revenue
            )
          )
        ),
        'profitability', jsonb_build_object(
          'gross_profit', v_revenue - v_cost,
          'margin_percentage', ((v_revenue - v_cost) / NULLIF(v_revenue, 0) * 100),
          'by_category', jsonb_build_object(
            v_product.category, jsonb_build_object(
              'revenue', v_revenue,
              'cost', v_cost,
              'margin', v_revenue - v_cost
            )
          )
        )
      )
    )
    ON CONFLICT (manufacturer, month) DO UPDATE
    SET sales_data = jsonb_deep_merge(
      manufacturer_sales_analytics.sales_data,
      EXCLUDED.sales_data
    );
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create function to merge JSON objects deeply
CREATE OR REPLACE FUNCTION jsonb_deep_merge(a jsonb, b jsonb)
RETURNS jsonb AS $$
BEGIN
  RETURN (
    SELECT jsonb_object_agg(
      COALESCE(ka, kb),
      CASE
        WHEN va IS NULL THEN vb
        WHEN vb IS NULL THEN va
        WHEN jsonb_typeof(va) = 'object' AND jsonb_typeof(vb) = 'object'
        THEN jsonb_deep_merge(va, vb)
        WHEN jsonb_typeof(va) = 'number' AND jsonb_typeof(vb) = 'number'
        THEN to_jsonb(COALESCE((va#>>'{}'),(vb#>>'{}'))::numeric + COALESCE((vb#>>'{}'),(va#>>'{}'))::numeric)
        ELSE vb
      END
    )
    FROM jsonb_each(a) AS t1(ka, va)
    FULL JOIN jsonb_each(b) AS t2(kb, vb)
    ON ka = kb
  );
END;
$$ LANGUAGE plpgsql;

-- Create trigger for sales analytics
CREATE TRIGGER update_sales_analytics_trigger
  AFTER INSERT OR UPDATE OF status ON quotations
  FOR EACH ROW
  WHEN (NEW.status = 'accepted')
  EXECUTE FUNCTION update_manufacturer_sales_analytics();

-- Create function to get manufacturer sales report
CREATE OR REPLACE FUNCTION get_manufacturer_sales_report(
  p_manufacturer text,
  p_start_date date,
  p_end_date date
) RETURNS TABLE (
  month date,
  total_revenue numeric,
  total_units integer,
  gross_profit numeric,
  margin_percentage numeric,
  top_categories jsonb,
  customer_mix jsonb,
  product_performance jsonb
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    msa.month,
    (msa.sales_data->'revenue'->>'total')::numeric as total_revenue,
    (msa.sales_data->'units'->>'total')::integer as total_units,
    (msa.sales_data->'profitability'->>'gross_profit')::numeric as gross_profit,
    (msa.sales_data->'profitability'->>'margin_percentage')::numeric as margin_percentage,
    msa.sales_data->'revenue'->'by_category' as top_categories,
    msa.sales_data->'revenue'->'by_customer_type' as customer_mix,
    msa.sales_data->'units'->'by_product' as product_performance
  FROM manufacturer_sales_analytics msa
  WHERE msa.manufacturer = p_manufacturer
    AND msa.month BETWEEN p_start_date AND p_end_date
  ORDER BY msa.month;
END;
$$ LANGUAGE plpgsql;