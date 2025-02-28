-- Drop sale-related tables and functions safely
DO $$ 
BEGIN
  -- Drop triggers first
  DROP TRIGGER IF EXISTS update_stock_levels_trigger ON quotations;
  DROP TRIGGER IF EXISTS update_customer_purchases_trigger ON quotations;
  DROP TRIGGER IF EXISTS handle_sale_completion_trigger ON quotations;
  
  -- Drop functions
  DROP FUNCTION IF EXISTS complete_sale(text, uuid, uuid, jsonb, jsonb) CASCADE;
  DROP FUNCTION IF EXISTS complete_sale_v2(text, uuid, uuid, jsonb, jsonb) CASCADE;
  DROP FUNCTION IF EXISTS validate_payment_details(jsonb) CASCADE;
  DROP FUNCTION IF EXISTS handle_sale_completion() CASCADE;

  -- Drop sequences
  DROP SEQUENCE IF EXISTS sale_number_seq CASCADE;

  -- Drop types
  DROP TYPE IF EXISTS sale_type CASCADE;
  DROP TYPE IF EXISTS payment_status CASCADE;

  -- Drop indexes
  DROP INDEX IF EXISTS idx_sales_customer_id;
  DROP INDEX IF EXISTS idx_sales_video_call_id;
  DROP INDEX IF EXISTS idx_sales_quotation_id;
  DROP INDEX IF EXISTS idx_sales_sale_number;
  DROP INDEX IF EXISTS idx_sales_payment_status;

  -- Drop policies
  DROP POLICY IF EXISTS "Allow public read access on sales" ON sales;
  DROP POLICY IF EXISTS "Allow public insert access on sales" ON sales;
  DROP POLICY IF EXISTS "Allow public update access on sales" ON sales;

  -- Finally drop the sales table
  DROP TABLE IF EXISTS sales CASCADE;

END $$;