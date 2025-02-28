-- Create sequence for sale numbers
CREATE SEQUENCE IF NOT EXISTS sale_number_seq;

-- Create type for sale types
DO $$ BEGIN
  CREATE TYPE sale_type AS ENUM ('counter', 'video_call');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Create type for payment status
DO $$ BEGIN
  CREATE TYPE payment_status AS ENUM ('pending', 'partially_paid', 'paid', 'overdue');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Create sales table
CREATE TABLE IF NOT EXISTS sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_type sale_type NOT NULL,
  customer_id uuid REFERENCES customers(id),
  video_call_id uuid REFERENCES video_calls(id),
  quotation_id uuid REFERENCES quotations(id),
  sale_number text NOT NULL,
  sale_date timestamptz DEFAULT now(),
  total_amount numeric NOT NULL,
  payment_status payment_status DEFAULT 'pending',
  payment_details jsonb DEFAULT '{
    "total_amount": 0,
    "paid_amount": 0,
    "pending_amount": 0,
    "payments": []
  }',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create function to handle sale completion
CREATE OR REPLACE FUNCTION complete_sale(
  p_sale_type sale_type,
  p_customer_id uuid,
  p_video_call_id uuid,
  p_quotation_data jsonb,
  p_payment_details jsonb
)
RETURNS uuid AS $$
DECLARE
  v_sale_id uuid;
  v_quotation_id uuid;
  v_sale_number text;
  v_workflow_status jsonb;
BEGIN
  -- Generate sale number
  v_sale_number := 'S' || to_char(now(), 'YYYYMMDD') || '-' || 
                   lpad(nextval('sale_number_seq')::text, 4, '0');

  -- Create quotation first
  INSERT INTO quotations (
    customer_id,
    video_call_id,
    items,
    total_amount,
    status,
    payment_details,
    workflow_status,
    quotation_number
  )
  VALUES (
    p_customer_id,
    p_video_call_id,
    p_quotation_data->'items',
    (p_quotation_data->>'total_amount')::numeric,
    'accepted',
    p_payment_details,
    jsonb_build_object(
      'qc', CASE WHEN p_quotation_data->>'delivery_method' = 'hand_carry' THEN 'completed' ELSE 'pending' END,
      'packaging', CASE WHEN p_quotation_data->>'delivery_method' = 'hand_carry' THEN 'completed' ELSE 'pending' END,
      'dispatch', CASE WHEN p_quotation_data->>'delivery_method' = 'hand_carry' THEN 'completed' ELSE 'pending' END
    ),
    p_quotation_data->>'quotation_number'
  )
  RETURNING id INTO v_quotation_id;

  -- Create sale record
  INSERT INTO sales (
    sale_type,
    customer_id,
    video_call_id,
    quotation_id,
    sale_number,
    total_amount,
    payment_status,
    payment_details
  )
  VALUES (
    p_sale_type,
    p_customer_id,
    p_video_call_id,
    v_quotation_id,
    v_sale_number,
    (p_quotation_data->>'total_amount')::numeric,
    CASE
      WHEN (p_payment_details->>'payment_status')::text = 'completed' THEN 'paid'::payment_status
      WHEN (p_payment_details->>'payment_status')::text = 'pending' THEN 'pending'::payment_status
      ELSE 'partially_paid'::payment_status
    END,
    p_payment_details
  )
  RETURNING id INTO v_sale_id;

  -- Update video call if applicable
  IF p_video_call_id IS NOT NULL THEN
    SELECT workflow_status INTO v_workflow_status
    FROM video_calls
    WHERE id = p_video_call_id;

    UPDATE video_calls
    SET
      workflow_status = jsonb_set(
        v_workflow_status,
        '{quotation}',
        '"completed"'
      ),
      quotation_id = v_quotation_id,
      quotation_required = true,
      bill_status = CASE
        WHEN (p_payment_details->>'payment_status')::text = 'completed' THEN 'paid'
        ELSE 'pending'
      END,
      bill_amount = (p_quotation_data->>'total_amount')::numeric,
      bill_generated_at = now(),
      bill_paid_at = CASE
        WHEN (p_payment_details->>'payment_status')::text = 'completed' THEN now()
        ELSE NULL
      END
    WHERE id = p_video_call_id;
  END IF;

  -- Update stock levels
  UPDATE products p
  SET stock_level = p.stock_level - (i->>'quantity')::integer
  FROM jsonb_array_elements(p_quotation_data->'items') AS i
  WHERE p.id = (i->>'product_id')::uuid;

  RETURN v_sale_id;
END;
$$ LANGUAGE plpgsql;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_sales_customer_id ON sales(customer_id);
CREATE INDEX IF NOT EXISTS idx_sales_video_call_id ON sales(video_call_id);
CREATE INDEX IF NOT EXISTS idx_sales_quotation_id ON sales(quotation_id);
CREATE INDEX IF NOT EXISTS idx_sales_sale_number ON sales(sale_number);
CREATE INDEX IF NOT EXISTS idx_sales_payment_status ON sales(payment_status);

-- Add helpful comments
COMMENT ON TABLE sales IS 'Stores all sales transactions including both counter sales and video call sales';
COMMENT ON FUNCTION complete_sale IS 'Handles the complete sale process including quotation creation, stock updates, and video call workflow updates';