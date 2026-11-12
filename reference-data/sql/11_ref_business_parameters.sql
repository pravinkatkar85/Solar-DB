-- Auto-generated. Do not edit by hand; re-run generate-reference-data.mjs
-- Natural-key upsert: ON CONFLICT (parameter_code, effective_from).
-- parameter_id is identity-assigned; never forced. Safe alongside script 04 DEV_* rows.
SET search_path TO solar_app, public;

INSERT INTO solar_app.ref_business_parameters (parameter_code, parameter_name, value_type, numeric_value, text_value, boolean_value, json_value, parameter_unit, parameter_desc, admin_manageable_ind, effective_from, effective_to, active_ind, created_by, updated_by)
VALUES
  ('COMPLAINT_MEDIA_MAX_COUNT', 'Complaint media attachment maximum', 'NUMERIC', 4, NULL, NULL, NULL, 'COUNT', 'Maximum photos/videos per complaint ticket (M6.2 OPEN-T3).', TRUE, '2026-01-01', NULL, TRUE, 'SYSTEM', 'SYSTEM')
ON CONFLICT (parameter_code, effective_from) DO UPDATE SET
  parameter_name = EXCLUDED.parameter_name,
  value_type = EXCLUDED.value_type,
  numeric_value = EXCLUDED.numeric_value,
  text_value = EXCLUDED.text_value,
  boolean_value = EXCLUDED.boolean_value,
  json_value = EXCLUDED.json_value,
  parameter_unit = EXCLUDED.parameter_unit,
  parameter_desc = EXCLUDED.parameter_desc,
  admin_manageable_ind = EXCLUDED.admin_manageable_ind,
  effective_to = EXCLUDED.effective_to,
  active_ind = EXCLUDED.active_ind,
  updated_by = EXCLUDED.updated_by,
  updated_on = CURRENT_TIMESTAMP;
