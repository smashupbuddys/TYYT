-- Drop existing products table
DROP TABLE IF EXISTS products CASCADE;

-- Create products table with correct schema and validation
CREATE TABLE products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL, -- Keep name required at database level
  description text,
  manufacturer text NOT NULL,
  sku text UNIQUE NOT NULL,
  buy_price numeric NOT NULL CHECK (buy_price > 0),
  wholesale_price numeric NOT NULL CHECK (wholesale_price > buy_price),
  retail_price numeric NOT NULL CHECK (retail_price > wholesale_price),
  stock_level integer NOT NULL DEFAULT 0 CHECK (stock_level >= 0),
  category text NOT NULL,
  image_url text,
  qr_code text,
  code128 text,
  cipher text,
  additional_info text,
  last_sold_at timestamptz,
  dead_stock_status text CHECK (dead_stock_status IN ('normal', 'warning', 'critical')),
  dead_stock_days integer,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Allow public read access on products"
  ON products FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on products"
  ON products FOR INSERT TO public WITH CHECK (
    buy_price > 0 AND
    wholesale_price > buy_price AND
    retail_price > wholesale_price AND
    stock_level >= 0
  );

CREATE POLICY "Allow public update access on products"
  ON products FOR UPDATE TO public USING (true) WITH CHECK (
    buy_price > 0 AND
    wholesale_price > buy_price AND
    retail_price > wholesale_price AND
    stock_level >= 0
  );

CREATE POLICY "Allow public delete access on products"
  ON products FOR DELETE TO public USING (true);

-- Create indexes
CREATE INDEX idx_products_sku ON products(sku);
CREATE INDEX idx_products_manufacturer ON products(manufacturer);
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_products_stock_level ON products(stock_level);
CREATE INDEX idx_products_last_sold_at ON products(last_sold_at);
CREATE INDEX idx_products_dead_stock_status ON products(dead_stock_status);

-- Add helpful comments
COMMENT ON TABLE products IS 'Stores product inventory with pricing, stock levels, and tracking information';
COMMENT ON COLUMN products.name IS 'Required product name';
COMMENT ON COLUMN products.buy_price IS 'Purchase price - must be greater than 0';
COMMENT ON COLUMN products.wholesale_price IS 'Wholesale price - must be greater than buy price';
COMMENT ON COLUMN products.retail_price IS 'Retail price - must be greater than wholesale price';
COMMENT ON COLUMN products.stock_level IS 'Current stock level - cannot be negative';