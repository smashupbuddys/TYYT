-- Add quotation tracking fields to customers
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS quotation_history jsonb DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS total_quotations integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS accepted_quotations integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS rejected_quotations integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_quotation_date timestamptz;

-- Create function to update customer quotation history
CREATE OR REPLACE FUNCTION update_customer_quotation_history()
RETURNS TRIGGER AS $$
DECLARE
  quotation_data jsonb;
BEGIN
  -- Build quotation data
  quotation_data := jsonb_build_object(
    'quotation_number', NEW.quotation_number,
    'date', NEW.created_at,
    'total_amount', NEW.total_amount,
    'status', NEW.status,
    'items', NEW.items,
    'payment_status', NEW.bill_status,
    'payment_details', NEW.payment_details
  );

  -- Update customer quotation history
  IF TG_OP = 'INSERT' THEN
    UPDATE customers
    SET 
      quotation_history = COALESCE(quotation_history, '[]'::jsonb) || quotation_data,
      total_quotations = total_quotations + 1,
      accepted_quotations = CASE 
        WHEN NEW.status = 'accepted' THEN accepted_quotations + 1 
        ELSE accepted_quotations 
      END,
      rejected_quotations = CASE 
        WHEN NEW.status = 'rejected' THEN rejected_quotations + 1 
        ELSE rejected_quotations 
      END,
      last_quotation_date = NEW.created_at
    WHERE id = NEW.customer_id;
  ELSIF TG_OP = 'UPDATE' THEN
    -- Handle status changes
    IF NEW.status != OLD.status THEN
      UPDATE customers
      SET 
        accepted_quotations = CASE 
          WHEN NEW.status = 'accepted' THEN accepted_quotations + 1
          WHEN OLD.status = 'accepted' THEN accepted_quotations - 1
          ELSE accepted_quotations 
        END,
        rejected_quotations = CASE 
          WHEN NEW.status = 'rejected' THEN rejected_quotations + 1
          WHEN OLD.status = 'rejected' THEN rejected_quotations - 1
          ELSE rejected_quotations 
        END,
        quotation_history = (
          SELECT jsonb_agg(
            CASE 
              WHEN (value->>'quotation_number')::text = NEW.quotation_number 
              THEN jsonb_set(
                value,
                '{status}',
                to_jsonb(NEW.status::text)
              )
              ELSE value 
            END
          )
          FROM jsonb_array_elements(quotation_history)
        )
      WHERE id = NEW.customer_id;
    END IF;

    -- Handle payment status changes
    IF NEW.bill_status != OLD.bill_status OR NEW.payment_details != OLD.payment_details THEN
      UPDATE customers
      SET quotation_history = (
        SELECT jsonb_agg(
          CASE 
            WHEN (value->>'quotation_number')::text = NEW.quotation_number 
            THEN jsonb_set(
              jsonb_set(
                value,
                '{payment_status}',
                to_jsonb(NEW.bill_status::text)
              ),
              '{payment_details}',
              NEW.payment_details
            )
            ELSE value 
          END
        )
        FROM jsonb_array_elements(quotation_history)
      )
      WHERE id = NEW.customer_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for quotation history updates
DROP TRIGGER IF EXISTS update_customer_quotation_history_trigger ON quotations;
CREATE TRIGGER update_customer_quotation_history_trigger
  AFTER INSERT OR UPDATE OF status, bill_status, payment_details ON quotations
  FOR EACH ROW
  EXECUTE FUNCTION update_customer_quotation_history();

-- Add index for better performance
CREATE INDEX IF NOT EXISTS idx_customers_quotation_history 
  ON customers USING gin (quotation_history);

-- Add helpful comment
COMMENT ON COLUMN customers.quotation_history IS 'History of all quotations for this customer including status and payment details';