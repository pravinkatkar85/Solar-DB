-- Rolls back SQLScripts/08_amc_credit_reservation_and_quote.sql.
-- Drops the reservation table, the one-visit index, and the booking quote columns.
-- Confirmed quote values stored in those columns are removed with the columns.
-- Visit rows, bookings, contracts, and charge snapshots on site_visit_details stay.
--
-- Do not run this until a separate approval says the schema step should be undone.
--
--   psql -U solar_app_user -d SolarDB -v ON_ERROR_STOP=1 -f SQLScripts/08_amc_credit_reservation_and_quote_rollback.sql

BEGIN;

DROP INDEX IF EXISTS solar_app.uq_sv_one_service_request;

DROP TABLE IF EXISTS solar_app.amc_credit_reservation_details;

ALTER TABLE solar_app.service_request_details
    DROP CONSTRAINT IF EXISTS chk_sr_quote_confirmed,
    DROP CONSTRAINT IF EXISTS chk_sr_quote_pair,
    DROP CONSTRAINT IF EXISTS chk_sr_quote_amount,
    DROP CONSTRAINT IF EXISTS fk_sr_quote_slab,
    DROP CONSTRAINT IF EXISTS fk_sr_quote_currency;

ALTER TABLE solar_app.service_request_details
    DROP COLUMN IF EXISTS quote_confirmed_on,
    DROP COLUMN IF EXISTS fee_quote_snapshot_json,
    DROP COLUMN IF EXISTS visit_charge_slab_id,
    DROP COLUMN IF EXISTS quoted_currency_code,
    DROP COLUMN IF EXISTS quoted_charge_amount;

COMMENT ON COLUMN solar_app.site_visit_details.service_request_id IS 'Optional preventive service booking. FK added after service_request_details exists.';

COMMIT;
