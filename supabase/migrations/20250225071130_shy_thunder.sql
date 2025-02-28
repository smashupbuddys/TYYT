-- Drop template-related tables if they exist
DO $$ 
BEGIN
  -- Drop scenario_template_tags first due to foreign key constraints
  DROP TABLE IF EXISTS scenario_template_tags CASCADE;
  
  -- Drop template_tags
  DROP TABLE IF EXISTS template_tags CASCADE;
  
  -- Drop scenario_templates
  DROP TABLE IF EXISTS scenario_templates CASCADE;
  
  -- Drop voice_templates
  DROP TABLE IF EXISTS voice_templates CASCADE;

  -- Drop related functions and triggers
  DROP FUNCTION IF EXISTS ensure_single_default_template() CASCADE;
END $$;