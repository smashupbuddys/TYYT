/*
  # Enhance Video Calls System - Part 1

  1. Changes
    - Add quotation and payment tracking columns to video_calls
    - Create quotations table
    - Create payments table
    - Create notifications table
    
  2. Security
    - Enable RLS on new tables
    - Add policies for public access
*/

-- Create quotations table first since it will be referenced by video_calls
CREATE TABLE IF NOT EXISTS quotations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid REFERENCES customers(id),
  items jsonb NOT NULL DEFAULT '[]',
  total_amount numeric NOT NULL DEFAULT 0,
  status text NOT NULL CHECK (status IN ('draft', 'sent', 'accepted', 'rejected', 'expired')) DEFAULT 'draft',
  valid_until timestamptz NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Add quotation status to video calls
ALTER TABLE video_calls 
  ADD COLUMN IF NOT EXISTS quotation_required boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS quotation_id uuid REFERENCES quotations(id),
  ADD COLUMN IF NOT EXISTS payment_status text CHECK (payment_status IN ('pending', 'completed', 'overdue')) DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS payment_due_date timestamptz;

-- Create payments table
CREATE TABLE IF NOT EXISTS payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quotation_id uuid REFERENCES quotations(id),
  amount numeric NOT NULL,
  status text NOT NULL CHECK (status IN ('pending', 'completed', 'failed')) DEFAULT 'pending',
  payment_method text,
  transaction_id text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create notifications table
CREATE TABLE IF NOT EXISTS notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  type text NOT NULL,
  title text NOT NULL,
  message text NOT NULL,
  read boolean DEFAULT false,
  data jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE quotations ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Create policies for quotations
CREATE POLICY "Allow public read access on quotations"
  ON quotations FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on quotations"
  ON quotations FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on quotations"
  ON quotations FOR UPDATE TO public USING (true) WITH CHECK (true);

-- Create policies for payments
CREATE POLICY "Allow public read access on payments"
  ON payments FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on payments"
  ON payments FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on payments"
  ON payments FOR UPDATE TO public USING (true) WITH CHECK (true);

-- Create policies for notifications
CREATE POLICY "Allow public read access on notifications"
  ON notifications FOR SELECT TO public USING (true);

CREATE POLICY "Allow public insert access on notifications"
  ON notifications FOR INSERT TO public WITH CHECK (true);

CREATE POLICY "Allow public update access on notifications"
  ON notifications FOR UPDATE TO public USING (true) WITH CHECK (true);
