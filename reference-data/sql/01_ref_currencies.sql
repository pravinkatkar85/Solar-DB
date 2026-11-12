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

-- Forward-only identity sync: advance only when sequence is behind MAX(id).
-- Leave sequence unchanged when already ahead (gaps from CACHE/concurrency are OK).
SELECT CASE
  WHEN seq_meta.next_expected > seq_meta.max_id THEN seq_meta.next_expected
  ELSE setval(seq_meta.seq_reg, seq_meta.max_id, TRUE)
END
FROM (
  SELECT
    pg_get_serial_sequence('solar_app.ref_currencies', 'currency_id')::regclass AS seq_reg,
    (SELECT MAX(currency_id) FROM solar_app.ref_currencies) AS max_id,
    CASE
      WHEN s.is_called THEN s.last_value + 1
      ELSE s.last_value
    END AS next_expected
  FROM pg_sequences AS s
  WHERE pg_get_serial_sequence('solar_app.ref_currencies', 'currency_id') IS NOT NULL
    AND (
      (s.schemaname || '.' || s.sequencename) = pg_get_serial_sequence('solar_app.ref_currencies', 'currency_id')
      OR s.sequencename = split_part(
           pg_get_serial_sequence('solar_app.ref_currencies', 'currency_id'),
           '.',
           2
         )
    )
) AS seq_meta
WHERE seq_meta.max_id IS NOT NULL;
