/*
  # Add Purchase Tracking

  1. New Tables
    - `purchase_notifications` - Tracks notifications for new purchases
    - `purchase_history` - Tracks history of all product purchases

  2. Changes
    - Add purchase tracking columns to products table
    - Add trigger to create notifications and history entries

  3. Security
    - Enable RLS on new tables
    - Add policies for public access
*/

-- Create purchase_notifications table
CREATE TABLE IF NOT EXISTS purchase_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  manufacturer text NOT NULL,
  quantity integer NOT NULL,
  buy_price numeric NOT NULL,
  total_amount numeric NOT NULL,
  created_at timestamptz DEFAULT now(),
  read boolean DEFAULT false
);

-- Create purchase_history table
CREATE TABLE IF NOT EXISTS purchase_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  manufacturer text NOT NULL,
  quantity integer NOT NULL,
  buy_price numeric NOT NULL,
  total_amount numeric NOT NULL,
  purchase_date timestamptz DEFAULT now(),
  notes text
);

-- Enable RLS
ALTER TABLE purchase_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_history ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on purchase_notifications"
  ON purchase_notifications FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on purchase_notifications"
  ON purchase_notifications FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on purchase_notifications"
  ON purchase_notifications FOR UPDATE TO public USING (true);

CREATE POLICY "Allow public read access on purchase_history"
  ON purchase_history FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on purchase_history"
  ON purchase_history FOR INSERT TO public WITH CHECK (true);

-- Create function to track product purchases
CREATE OR REPLACE FUNCTION track_product_purchase()
RETURNS TRIGGER AS $$
DECLARE
  purchase_quantity integer;
  purchase_amount numeric;
BEGIN
  -- Calculate purchase quantity and amount
  IF TG_OP = 'INSERT' THEN
    purchase_quantity := NEW.stock_level;
    purchase_amount := NEW.stock_level * NEW.buy_price;
  ELSE
    -- Only track increases in stock level
    IF NEW.stock_level <= OLD.stock_level THEN
      RETURN NEW;
    END IF;
    purchase_quantity := NEW.stock_level - OLD.stock_level;
    purchase_amount := purchase_quantity * NEW.buy_price;
  END IF;

  -- Create purchase notification
  INSERT INTO purchase_notifications (
    product_id,
    manufacturer,
    quantity,
    buy_price,
    total_amount
  ) VALUES (
    NEW.id,
    NEW.manufacturer,
    purchase_quantity,
    NEW.buy_price,
    purchase_amount
  );

  -- Add to purchase history
  INSERT INTO purchase_history (
    product_id,
    manufacturer,
    quantity,
    buy_price,
    total_amount,
    notes
  ) VALUES (
    NEW.id,
    NEW.manufacturer,
    purchase_quantity,
    NEW.buy_price,
    purchase_amount,
    CASE
      WHEN TG_OP = 'INSERT' THEN 'Initial stock purchase'
      ELSE 'Stock level increase'
    END
  );

  -- Update manufacturer analytics
  INSERT INTO manufacturer_analytics (
    manufacturer,
    month,
    purchases
  ) VALUES (
    NEW.manufacturer,
    date_trunc('month', CURRENT_DATE)::date,
    jsonb_build_object(
      'total_amount', purchase_amount,
      'total_items', purchase_quantity,
      'categories', jsonb_build_object(
        NEW.category, jsonb_build_object(
          'quantity', purchase_quantity,
          'value', purchase_amount
        )
      )
    )
  )
  ON CONFLICT (manufacturer, month) DO UPDATE
  SET purchases = jsonb_set(
    jsonb_set(
      jsonb_set(
        manufacturer_analytics.purchases,
        '{total_amount}',
        to_jsonb(COALESCE((manufacturer_analytics.purchases->>'total_amount')::numeric, 0) + purchase_amount)
      ),
      '{total_items}',
      to_jsonb(COALESCE((manufacturer_analytics.purchases->>'total_items')::integer, 0) + purchase_quantity)
    ),
    '{categories}',
    CASE
      WHEN manufacturer_analytics.purchases->'categories' ? NEW.category
      THEN jsonb_set(
        manufacturer_analytics.purchases->'categories',
        array[NEW.category],
        jsonb_build_object(
          'quantity', (((manufacturer_analytics.purchases->'categories'->NEW.category->>'quantity')::integer) + purchase_quantity),
          'value', (((manufacturer_analytics.purchases->'categories'->NEW.category->>'value')::numeric) + purchase_amount)
        )
      )
      ELSE jsonb_set(
        COALESCE(manufacturer_analytics.purchases->'categories', '{}'::jsonb),
        array[NEW.category],
        jsonb_build_object(
          'quantity', purchase_quantity,
          'value', purchase_amount
        )
      )
    END
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for purchase tracking
CREATE TRIGGER track_product_purchase_trigger
  AFTER INSERT OR UPDATE OF stock_level ON products
  FOR EACH ROW
  EXECUTE FUNCTION track_product_purchase();

-- Add indexes for better performance
CREATE INDEX idx_purchase_notifications_product ON purchase_notifications(product_id);
CREATE INDEX idx_purchase_notifications_manufacturer ON purchase_notifications(manufacturer);
CREATE INDEX idx_purchase_history_product ON purchase_history(product_id);
CREATE INDEX idx_purchase_history_manufacturer ON purchase_history(manufacturer);
CREATE INDEX idx_purchase_history_date ON purchase_history(purchase_date);

-- Add comment explaining the purchase tracking system
COMMENT ON TABLE purchase_notifications IS 'Tracks notifications for new product purchases and stock increases';
COMMENT ON TABLE purchase_history IS 'Maintains a complete history of all product purchases and stock changes';