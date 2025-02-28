-- Create function to handle product purchase tracking
CREATE OR REPLACE FUNCTION track_product_purchase()
RETURNS TRIGGER AS $$
DECLARE
  purchase_amount numeric;
BEGIN
  -- Only track purchases for new products or stock increases
  IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.stock_level > OLD.stock_level) THEN
    -- Calculate purchase amount for new/additional stock
    purchase_amount := CASE
      WHEN TG_OP = 'INSERT' THEN NEW.stock_level * NEW.buy_price
      ELSE (NEW.stock_level - OLD.stock_level) * NEW.buy_price
    END;

    -- Create purchase transaction
    INSERT INTO purchase_transactions (
      manufacturer,
      purchase_date,
      items,
      total_amount,
      payment_status,
      notes
    ) VALUES (
      NEW.manufacturer,
      CURRENT_DATE,
      jsonb_build_array(
        jsonb_build_object(
          'product_id', NEW.id,
          'sku', NEW.sku,
          'name', NEW.name,
          'category', NEW.category,
          'quantity', CASE
            WHEN TG_OP = 'INSERT' THEN NEW.stock_level
            ELSE NEW.stock_level - OLD.stock_level
          END,
          'price', NEW.buy_price
        )
      ),
      purchase_amount,
      'completed',
      CASE
        WHEN TG_OP = 'INSERT' THEN 'Initial stock purchase'
        ELSE 'Stock level increase'
      END
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for purchase tracking
DROP TRIGGER IF EXISTS product_purchase_trigger ON products;
CREATE TRIGGER product_purchase_trigger
  AFTER INSERT OR UPDATE OF stock_level ON products
  FOR EACH ROW
  EXECUTE FUNCTION track_product_purchase();

-- Add last_purchase_date to products
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS last_purchase_date timestamptz,
  ADD COLUMN IF NOT EXISTS last_purchase_price numeric;

-- Create function to update product purchase info
CREATE OR REPLACE FUNCTION update_product_purchase_info()
RETURNS TRIGGER AS $$
BEGIN
  -- Update product's last purchase info
  UPDATE products
  SET 
    last_purchase_date = NEW.purchase_date,
    last_purchase_price = (NEW.items->0->>'price')::numeric
  WHERE id = (NEW.items->0->>'product_id')::uuid;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for updating product purchase info
CREATE TRIGGER update_product_purchase_info_trigger
  AFTER INSERT ON purchase_transactions
  FOR EACH ROW
  EXECUTE FUNCTION update_product_purchase_info();