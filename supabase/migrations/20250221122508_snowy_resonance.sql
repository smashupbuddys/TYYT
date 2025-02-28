-- Create purchase_transactions table
CREATE TABLE IF NOT EXISTS purchase_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  manufacturer text NOT NULL,
  invoice_number text,
  purchase_date date NOT NULL,
  items jsonb NOT NULL DEFAULT '[]',
  total_amount numeric NOT NULL DEFAULT 0,
  payment_status text CHECK (payment_status IN ('pending', 'partial', 'completed')) DEFAULT 'pending',
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE purchase_transactions ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on purchase_transactions"
  ON purchase_transactions FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on purchase_transactions"
  ON purchase_transactions FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on purchase_transactions"
  ON purchase_transactions FOR UPDATE TO public USING (true);

-- Create function to update manufacturer analytics on purchase
CREATE OR REPLACE FUNCTION update_manufacturer_purchase_analytics()
RETURNS TRIGGER AS $$
BEGIN
  -- Update manufacturer analytics
  INSERT INTO manufacturer_analytics (
    manufacturer,
    month,
    purchases
  ) VALUES (
    NEW.manufacturer,
    date_trunc('month', NEW.purchase_date)::date,
    jsonb_build_object(
      'total_amount', NEW.total_amount,
      'total_items', (
        SELECT SUM((item->>'quantity')::integer)
        FROM jsonb_array_elements(NEW.items) item
      ),
      'categories', (
        SELECT jsonb_object_agg(
          category,
          jsonb_build_object(
            'quantity', SUM((items->>'quantity')::integer),
            'value', SUM((items->>'quantity')::integer * (items->>'price')::numeric)
          )
        )
        FROM (
          SELECT 
            items->>'category' as category,
            jsonb_array_elements(NEW.items) as items
          GROUP BY items->>'category'
        ) categories
      )
    )
  )
  ON CONFLICT (manufacturer, month) DO UPDATE
  SET purchases = jsonb_set(
    jsonb_set(
      jsonb_set(
        manufacturer_analytics.purchases,
        '{total_amount}',
        to_jsonb(COALESCE((manufacturer_analytics.purchases->>'total_amount')::numeric, 0) + NEW.total_amount)
      ),
      '{total_items}',
      to_jsonb(
        COALESCE((manufacturer_analytics.purchases->>'total_items')::integer, 0) + 
        (SELECT SUM((item->>'quantity')::integer) FROM jsonb_array_elements(NEW.items) item)
      )
    ),
    '{categories}',
    COALESCE(manufacturer_analytics.purchases->'categories', '{}'::jsonb) || 
    (
      SELECT jsonb_object_agg(
        category,
        jsonb_build_object(
          'quantity', SUM((items->>'quantity')::integer),
          'value', SUM((items->>'quantity')::integer * (items->>'price')::numeric)
        )
      )
      FROM (
        SELECT 
          items->>'category' as category,
          jsonb_array_elements(NEW.items) as items
        GROUP BY items->>'category'
      ) categories
    )
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for purchase analytics
CREATE TRIGGER update_purchase_analytics_trigger
  AFTER INSERT OR UPDATE ON purchase_transactions
  FOR EACH ROW
  EXECUTE FUNCTION update_manufacturer_purchase_analytics();

-- Add helpful indexes
CREATE INDEX idx_purchase_transactions_manufacturer 
  ON purchase_transactions(manufacturer);
CREATE INDEX idx_purchase_transactions_date 
  ON purchase_transactions(purchase_date);
CREATE INDEX idx_purchase_transactions_payment_status 
  ON purchase_transactions(payment_status);