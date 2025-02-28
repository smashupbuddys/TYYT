-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS validate_product_sku_trigger ON products;
DROP FUNCTION IF EXISTS validate_product_sku();

-- Create improved product validation function
CREATE OR REPLACE FUNCTION validate_product_sku()
RETURNS TRIGGER AS $$
DECLARE
  mfr_code text;
  cat_code text;
  price_code text;
  random_code text;
  product_data jsonb;
  qr_data text;
BEGIN
  -- Get manufacturer code
  SELECT code INTO mfr_code
  FROM markup_settings
  WHERE type = 'manufacturer' AND name = NEW.manufacturer;

  IF mfr_code IS NULL THEN
    RAISE EXCEPTION 'Manufacturer code not found for %', NEW.manufacturer;
  END IF;

  -- Get category code
  SELECT code INTO cat_code
  FROM markup_settings
  WHERE type = 'category' AND name = NEW.category;

  IF cat_code IS NULL THEN
    RAISE EXCEPTION 'Category code not found for %', NEW.category;
  END IF;

  -- Generate price code (4 digits)
  price_code := lpad(floor(NEW.retail_price)::text, 4, '0');

  -- Generate random code (5 uppercase letters)
  SELECT string_agg(substr('ABCDEFGHIJKLMNOPQRSTUVWXYZ', ceil(random() * 26)::integer, 1), '')
  INTO random_code
  FROM generate_series(1, 5);

  -- Generate SKU in format: PE/PJ02-2399-AGZKO
  NEW.sku := format('%s/%s-%s-%s',
    cat_code,
    mfr_code,
    price_code,
    random_code
  );

  -- Ensure SKU is unique
  WHILE EXISTS (
    SELECT 1 FROM products WHERE sku = NEW.sku AND id != NEW.id
  ) LOOP
    -- Generate new random code if collision occurs
    SELECT string_agg(substr('ABCDEFGHIJKLMNOPQRSTUVWXYZ', ceil(random() * 26)::integer, 1), '')
    INTO random_code
    FROM generate_series(1, 5);

    NEW.sku := format('%s/%s-%s-%s',
      cat_code,
      mfr_code,
      price_code,
      random_code
    );
  END LOOP;

  -- Build product data for QR code
  product_data := jsonb_build_object(
    'sku', NEW.sku,
    'category', NEW.category,
    'manufacturer', NEW.manufacturer,
    'mrp', NEW.retail_price,
    'additional_info', NEW.additional_info
  );

  -- Convert to JSON string for QR code
  qr_data := product_data::text;

  -- Set QR code and Code128
  NEW.qr_code := qr_data;
  NEW.code128 := NEW.sku;
  NEW.cipher := NEW.sku;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for SKU validation
CREATE TRIGGER validate_product_sku_trigger
  BEFORE INSERT OR UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION validate_product_sku();

-- Add helpful comment
COMMENT ON FUNCTION validate_product_sku IS 'Automatically generates SKU, QR code, and Code128 for products using manufacturer and category codes';

-- Update existing products with missing SKUs
UPDATE products
SET sku = NULL
WHERE sku IS NULL OR qr_code IS NULL OR code128 IS NULL;