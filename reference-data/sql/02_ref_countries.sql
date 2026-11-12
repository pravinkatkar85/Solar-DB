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

-- Forward-only identity sync: advance only when sequence is behind MAX(id).
-- Leave sequence unchanged when already ahead (gaps from CACHE/concurrency are OK).
SELECT CASE
  WHEN seq_meta.next_expected > seq_meta.max_id THEN seq_meta.next_expected
  ELSE setval(seq_meta.seq_reg, seq_meta.max_id, TRUE)
END
FROM (
  SELECT
    pg_get_serial_sequence('solar_app.ref_countries', 'country_id')::regclass AS seq_reg,
    (SELECT MAX(country_id) FROM solar_app.ref_countries) AS max_id,
    CASE
      WHEN s.is_called THEN s.last_value + 1
      ELSE s.last_value
    END AS next_expected
  FROM pg_sequences AS s
  WHERE pg_get_serial_sequence('solar_app.ref_countries', 'country_id') IS NOT NULL
    AND (
      (s.schemaname || '.' || s.sequencename) = pg_get_serial_sequence('solar_app.ref_countries', 'country_id')
      OR s.sequencename = split_part(
           pg_get_serial_sequence('solar_app.ref_countries', 'country_id'),
           '.',
           2
         )
    )
) AS seq_meta
WHERE seq_meta.max_id IS NOT NULL;
