-- Auto-generated. Do not edit by hand; re-run generate-reference-data.mjs
SET search_path TO solar_app, public;

INSERT INTO solar_app.ref_currencies (currency_id, currency_code, currency_name, decimal_places, active_ind, created_by, updated_by)
OVERRIDING SYSTEM VALUE
VALUES
  (1, 'INR', 'Indian Rupee', 2, TRUE, 'SYSTEM', 'SYSTEM')
ON CONFLICT (currency_id) DO UPDATE SET
  currency_code = EXCLUDED.currency_code,
  currency_name = EXCLUDED.currency_name,
  decimal_places = EXCLUDED.decimal_places,
  active_ind = EXCLUDED.active_ind,
  updated_by = EXCLUDED.updated_by,
  updated_on = CURRENT_TIMESTAMP;

SELECT setval(
  pg_get_serial_sequence('solar_app.ref_currencies', 'currency_id'),
  COALESCE((SELECT MAX(currency_id) FROM solar_app.ref_currencies), 1),
  EXISTS (SELECT 1 FROM solar_app.ref_currencies)
);
