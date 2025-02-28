-- Update manufacturer codes to use proper initials
UPDATE markup_settings 
SET code = CASE name
  WHEN 'Cartier' THEN 'CA02'
  WHEN 'Mohini' THEN 'MO01'
  WHEN 'DS BHAI' THEN 'DS01'
  WHEN 'SUHAG' THEN 'SU01'
  WHEN 'SGJ' THEN 'SG01'
  ELSE code -- Keep existing code if not in the list
END
WHERE type = 'manufacturer'
AND name IN ('Cartier', 'Mohini', 'DS BHAI', 'SUHAG', 'SGJ');

-- Insert new manufacturers with proper codes
INSERT INTO markup_settings (type, name, code, markup) VALUES
  ('manufacturer', 'DS BHAI', 'DS01', 0.25),
  ('manufacturer', 'SUHAG', 'SU01', 0.25),
  ('manufacturer', 'SGJ', 'SG01', 0.25)
ON CONFLICT (type, name) DO UPDATE
SET code = EXCLUDED.code,
    markup = EXCLUDED.markup;

-- Add helpful comment
COMMENT ON TABLE markup_settings IS 'Stores markup percentages and manufacturer codes using manufacturer initials (e.g., CA02 for Cartier, DS01 for DS BHAI)';