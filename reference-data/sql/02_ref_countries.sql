-- Auto-generated. Do not edit by hand; re-run generate-reference-data.mjs
SET search_path TO solar_app, public;

INSERT INTO solar_app.ref_countries (country_id, country_code, country_name, phone_code, national_phone_min_length, national_phone_max_length, national_phone_regex, postal_code_regex, tax_registration_label, tax_registration_regex, active_ind, created_by, updated_by)
OVERRIDING SYSTEM VALUE
VALUES
  (1, 'IN', 'India', '+91', 10, 10, '^[6-9][0-9]{9}$', '^[1-9][0-9]{5}$', 'GSTIN', NULL, TRUE, 'SYSTEM', 'SYSTEM')
ON CONFLICT (country_id) DO UPDATE SET
  country_code = EXCLUDED.country_code,
  country_name = EXCLUDED.country_name,
  phone_code = EXCLUDED.phone_code,
  national_phone_min_length = EXCLUDED.national_phone_min_length,
  national_phone_max_length = EXCLUDED.national_phone_max_length,
  national_phone_regex = EXCLUDED.national_phone_regex,
  postal_code_regex = EXCLUDED.postal_code_regex,
  tax_registration_label = EXCLUDED.tax_registration_label,
  tax_registration_regex = EXCLUDED.tax_registration_regex,
  active_ind = EXCLUDED.active_ind,
  updated_by = EXCLUDED.updated_by,
  updated_on = CURRENT_TIMESTAMP;

SELECT setval(
  pg_get_serial_sequence('solar_app.ref_countries', 'country_id'),
  COALESCE((SELECT MAX(country_id) FROM solar_app.ref_countries), 1),
  EXISTS (SELECT 1 FROM solar_app.ref_countries)
);
