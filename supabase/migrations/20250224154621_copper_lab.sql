-- Drop existing products table
DROP TABLE IF EXISTS products CASCADE;

-- Create products table with correct schema
CREATE TABLE products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  manufacturer text NOT NULL,
  sku text UNIQUE NOT NULL,
  buy_price numeric NOT NULL,
  wholesale_price numeric NOT NULL,
  retail_price numeric NOT NULL,
  stock_level integer NOT NULL DEFAULT 0,
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
  ON products FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on products"
  ON products FOR UPDATE TO public USING (true);

CREATE POLICY "Allow public delete access on products"
  ON products FOR DELETE TO public USING (true);

-- Create indexes
CREATE INDEX idx_products_sku ON products(sku);
CREATE INDEX idx_products_manufacturer ON products(manufacturer);
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_products_stock_level ON products(stock_level);
CREATE INDEX idx_products_last_sold_at ON products(last_sold_at);

-- Add helpful comment
COMMENT ON TABLE products IS 'Stores product inventory with pricing, stock levels, and tracking information';