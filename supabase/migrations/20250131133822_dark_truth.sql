/*
  # Create video calls table

  1. New Tables
    - `video_calls`
      - `id` (uuid, primary key)
      - `customer_id` (uuid, references customers)
      - `staff_id` (text)
      - `scheduled_at` (timestamptz)
      - `status` (text)
      - `notes` (text)
      - `created_at` (timestamptz)
      - `updated_at` (timestamptz)

  2. Security
    - Enable RLS on `video_calls` table
    - Add policies for public access (temporary for development)
*/

CREATE TABLE IF NOT EXISTS video_calls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES customers(id),
  staff_id text NOT NULL,
  scheduled_at timestamptz NOT NULL,
  status text NOT NULL CHECK (status IN ('scheduled', 'completed', 'cancelled')),
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE video_calls ENABLE ROW LEVEL SECURITY;

-- Create policies for public access (temporary for development)
CREATE POLICY "Allow public read access"
  ON video_calls
  FOR SELECT
  TO public
  USING (true);

CREATE POLICY "Allow public insert access"
  ON video_calls
  FOR INSERT
  TO public
  WITH CHECK (true);

CREATE POLICY "Allow public update access"
  ON video_calls
  FOR UPDATE
  TO public
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Allow public delete access"
  ON video_calls
  FOR DELETE
  TO public
  USING (true);
