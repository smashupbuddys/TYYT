/*
  # Product images configuration

  1. New Features
    - Create product images table
    - Set up RLS policies
    - Add image metadata tracking

  2. Changes
    - Add product_images table
    - Add RLS policies for image access
    - Add image metadata tracking
*/

-- Create table for tracking image metadata
CREATE TABLE IF NOT EXISTS product_images (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  storage_path text NOT NULL,
  file_name text NOT NULL,
  file_size integer NOT NULL,
  mime_type text NOT NULL,
  width integer,
  height integer,
  is_primary boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE product_images ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Public Read Access"
  ON product_images FOR SELECT
  TO public
  USING (true);

CREATE POLICY "Staff Write Access"
  ON product_images FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Staff Update Access"
  ON product_images FOR UPDATE
  TO authenticated
  USING (true);

CREATE POLICY "Staff Delete Access"
  ON product_images FOR DELETE
  TO authenticated
  USING (true);

-- Add indexes
CREATE INDEX idx_product_images_product_id ON product_images(product_id);
CREATE INDEX idx_product_images_is_primary ON product_images(is_primary);

-- Create function to handle image updates
CREATE OR REPLACE FUNCTION handle_product_image()
RETURNS TRIGGER AS $$
BEGIN
  -- If this is marked as primary, unmark other images
  IF NEW.is_primary THEN
    UPDATE product_images
    SET is_primary = false
    WHERE product_id = NEW.product_id
    AND id != NEW.id;
  END IF;

  -- Update product's main image URL
  IF NEW.is_primary THEN
    UPDATE products
    SET image_url = NEW.storage_path
    WHERE id = NEW.product_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for image updates
CREATE TRIGGER product_image_trigger
  AFTER INSERT OR UPDATE OF is_primary ON product_images
  FOR EACH ROW
  EXECUTE FUNCTION handle_product_image();