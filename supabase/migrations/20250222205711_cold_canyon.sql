-- Drop sale-related objects safely
DO $$ 
DECLARE
  v_table_exists boolean;
BEGIN
  -- Check if sales table exists
  SELECT EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_name = 'sales'
  ) INTO v_table_exists;

  -- Only try to drop objects if sales table exists
  IF v_table_exists THEN
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

    -- Drop types if they exist
    IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sale_type') THEN
      DROP TYPE sale_type CASCADE;
    END IF;
    
    IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_status') THEN
      DROP TYPE payment_status CASCADE;
    END IF;

    -- Drop the sales table last
    DROP TABLE sales CASCADE;
  END IF;
END $$;