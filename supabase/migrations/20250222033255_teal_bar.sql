-- Drop existing function
DROP FUNCTION IF EXISTS complete_sale_v2(text, uuid, uuid, jsonb, jsonb);

-- Create improved complete_sale function with proper aggregation and validation
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
  v_total_items integer;
  v_total_amount numeric;
  v_delivery_method text;
BEGIN
  -- Validate inputs
  IF p_quotation_data IS NULL OR p_payment_details IS NULL THEN
    RAISE EXCEPTION 'Quotation data and payment details are required';
  END IF;

  -- Extract and validate values
  v_total_amount := (p_quotation_data->>'total_amount')::numeric;
  IF v_total_amount IS NULL OR v_total_amount <= 0 THEN
    RAISE EXCEPTION 'Invalid total amount';
  END IF;

  v_delivery_method := COALESCE(p_quotation_data->>'delivery_method', 'dispatch');
  
  -- Calculate total items without nested aggregates
  SELECT COALESCE(SUM((value->>'quantity')::integer), 0)
  INTO v_total_items 
  FROM jsonb_array_elements(p_quotation_data->'items') as value;

  IF v_total_items = 0 THEN
    RAISE EXCEPTION 'No items in quotation';
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
    quotation_number,
    valid_until
  )
  VALUES (
    p_customer_id,
    p_video_call_id,
    p_quotation_data->'items',
    v_total_amount,
    'accepted',
    p_payment_details,
    jsonb_build_object(
      'qc', CASE WHEN v_delivery_method = 'hand_carry' THEN 'completed' ELSE 'pending' END,
      'packaging', CASE WHEN v_delivery_method = 'hand_carry' THEN 'completed' ELSE 'pending' END,
      'dispatch', CASE WHEN v_delivery_method = 'hand_carry' THEN 'completed' ELSE 'pending' END
    ),
    p_quotation_data->>'quotation_number',
    now() + interval '7 days'
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
    v_total_amount,
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

    IF v_workflow_status IS NULL THEN
      v_workflow_status := jsonb_build_object(
        'video_call', 'completed',
        'quotation', 'completed',
        'profiling', 'pending',
        'payment', CASE 
          WHEN (p_payment_details->>'payment_status')::text = 'completed' THEN 'completed'
          ELSE 'pending'
        END,
        'qc', CASE WHEN v_delivery_method = 'hand_carry' THEN 'completed' ELSE 'pending' END,
        'packaging', CASE WHEN v_delivery_method = 'hand_carry' THEN 'completed' ELSE 'pending' END,
        'dispatch', CASE WHEN v_delivery_method = 'hand_carry' THEN 'completed' ELSE 'pending' END
      );
    ELSE
      v_workflow_status := jsonb_set(
        v_workflow_status,
        '{quotation}',
        '"completed"'
      );
    END IF;

    UPDATE video_calls
    SET
      workflow_status = v_workflow_status,
      quotation_id = v_quotation_id,
      quotation_required = true,
      bill_status = CASE
        WHEN (p_payment_details->>'payment_status')::text = 'completed' THEN 'paid'
        ELSE 'pending'
      END,
      bill_amount = v_total_amount,
      bill_generated_at = now(),
      bill_paid_at = CASE
        WHEN (p_payment_details->>'payment_status')::text = 'completed' THEN now()
        ELSE NULL
      END
    WHERE id = p_video_call_id;
  END IF;

  -- Update stock levels using a CTE to avoid nested aggregates
  WITH item_updates AS (
    SELECT 
      (value->>'product_id')::uuid as product_id,
      (value->>'quantity')::integer as quantity
    FROM jsonb_array_elements(p_quotation_data->'items') as value
  )
  UPDATE products p
  SET 
    stock_level = p.stock_level - i.quantity,
    last_sold_at = now()
  FROM item_updates i
  WHERE p.id = i.product_id;

  RETURN v_sale_id;
EXCEPTION
  WHEN OTHERS THEN
    -- Log error details
    RAISE NOTICE 'Error in complete_sale_v2: %', SQLERRM;
    RAISE;
END;
$$ LANGUAGE plpgsql;

-- Add helpful comment
COMMENT ON FUNCTION complete_sale_v2 IS 'Handles the complete sale process with proper validation, error handling, and no nested aggregates';