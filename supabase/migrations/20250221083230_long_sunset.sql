-- Add last_sold_at column to products table
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'products' AND column_name = 'last_sold_at'
  ) THEN
    ALTER TABLE products ADD COLUMN last_sold_at timestamptz;
  END IF;
END $$;

-- Create index for better performance
CREATE INDEX IF NOT EXISTS idx_products_last_sold 
  ON products(last_sold_at);

-- Create function to update last_sold_at
CREATE OR REPLACE FUNCTION update_product_last_sold()
RETURNS TRIGGER AS $$
BEGIN
  -- Update last_sold_at for all products in the quotation
  IF NEW.status = 'accepted' THEN
    UPDATE products p
    SET last_sold_at = NOW()
    FROM (
      SELECT (item->>'product_id')::uuid as product_id
      FROM jsonb_array_elements(NEW.items) as item
    ) sold_items
    WHERE p.id = sold_items.product_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for updating last_sold_at
DROP TRIGGER IF EXISTS update_product_last_sold_trigger ON quotations;
CREATE TRIGGER update_product_last_sold_trigger
  AFTER UPDATE OF status ON quotations
  FOR EACH ROW
  WHEN (NEW.status = 'accepted')
  EXECUTE FUNCTION update_product_last_sold();

-- Add helpful comment
COMMENT ON COLUMN products.last_sold_at IS 'Timestamp of when the product was last sold through an accepted quotation';