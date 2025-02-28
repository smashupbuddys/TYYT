-- Update Cartier's manufacturer code
UPDATE markup_settings 
SET code = 'CA02'
WHERE type = 'manufacturer' 
AND name = 'Cartier';

-- Add helpful comment
COMMENT ON TABLE markup_settings IS 'Stores markup percentages and manufacturer codes (e.g., CA02 for Cartier)';