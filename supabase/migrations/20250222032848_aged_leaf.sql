-- Drop existing complete_sale functions to avoid conflicts
DROP FUNCTION IF EXISTS complete_sale(sale_type, uuid, uuid, jsonb, jsonb);
DROP FUNCTION IF EXISTS complete_sale(text, uuid, uuid, jsonb, jsonb);

-- Create sequence for sale numbers if it doesn't exist
CREATE SEQUENCE IF NOT EXISTS sale_number_seq;

-- Create improved complete_sale function
CREATE OR REPLACE FUNCTION complete_sale_v2(
  p_sale_type text,
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
  -- Validate sale type
  IF p_sale_type NOT IN ('counter', 'video_call') THEN
    RAISE EXCEPTION 'Invalid sale type: %', p_sale_type;
  END IF;

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
    p_sale_type::sale_type,
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

-- Add helpful comment
COMMENT ON FUNCTION complete_sale_v2 IS 'Handles the complete sale process with improved type handling and validation';