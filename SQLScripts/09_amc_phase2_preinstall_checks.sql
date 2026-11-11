-- AMC Phase 2 pre-install checks. Read-only.
-- SELECT statements only. This file does not change the database.
--
-- Do not assume the live catalog matches SQLScripts/01_schema.sql.
-- A database built from the current 01_schema.sql already has the quote
-- columns, amc_credit_reservation_details, and uq_sv_one_service_request.
-- An older database does not. Either result is valid. Read what is there.
--
-- Run one statement at a time and read it before continuing:
--   psql -U solar_app_user -d SolarDB -f SQLScripts/09_amc_phase2_preinstall_checks.sql
--
-- If solar_app, site_visit_details, service_request_details,
-- ref_office_locations, or ref_visit_charge_slabs is missing, that
-- statement errors. Stop and record the missing object. An error is
-- not a passed check.

-- 1. Duplicate visits.
-- Stop if this returns any row. Migration 08 must not add
-- uq_sv_one_service_request while any service_request_id, active or
-- inactive, already has more than one site_visit_details row.
-- No rows means this check found no duplicate. Continue.
SELECT service_request_id, COUNT(*) AS visit_count
  FROM solar_app.site_visit_details
 WHERE service_request_id IS NOT NULL
 GROUP BY service_request_id
HAVING COUNT(*) > 1;

-- 2. Quote columns on service_request_details.
-- The five required names are quoted_charge_amount, quoted_currency_code,
-- visit_charge_slab_id, fee_quote_snapshot_json, and quote_confirmed_on.
-- Five rows, one for each name: the objects already exist. Do not run
-- migration 08. It is not idempotent and will fail on the first existing
-- column.
-- Zero rows: the quote columns are absent. Migration 08 is still a
-- candidate only when check 1 returned no rows and check 3 is also absent.
-- One to four rows: the table is only partly changed. Stop. Do not run
-- migration 08 and do not install the Phase 2 functions.
SELECT column_name
  FROM information_schema.columns
 WHERE table_schema = 'solar_app'
   AND table_name = 'service_request_details'
   AND column_name IN (
     'quoted_charge_amount',
     'quoted_currency_code',
     'visit_charge_slab_id',
     'fee_quote_snapshot_json',
     'quote_confirmed_on'
   )
 ORDER BY column_name;

-- 3. Reservation table and the three indexes.
-- to_regclass returns the registered name when the object exists and
-- NULL when it does not. The names are amc_credit_reservation_details,
-- uq_sv_one_service_request, uq_acr_contract_credit, and
-- uq_acr_request_open.
-- All four populated: do not run migration 08.
-- All four NULL, and checks 1 and 2 are clear: migration 08 is the
-- candidate for those objects.
-- A mix of names and NULL: stop. Do not run migration 08.
SELECT to_regclass('solar_app.amc_credit_reservation_details') AS reservation_table,
       to_regclass('solar_app.uq_sv_one_service_request') AS one_visit_index,
       to_regclass('solar_app.uq_acr_contract_credit') AS credit_index,
       to_regclass('solar_app.uq_acr_request_open') AS request_index;

-- 4. Approved active default offices.
-- DEV_ office codes are excluded. This count is not a pass or fail.
-- 0 is expected while only development fixtures exist. Booking can
-- continue without a stored fee.
-- 1, together with at least one row in check 5, is the approved pricing
-- configuration used by fn_create_service_request_details. An unavailable
-- quote then refuses the booking.
-- More than 1 means approved pricing is not configured, because that
-- function requires exactly one such office. Do not treat the extra
-- offices as a fee.
SELECT COUNT(*) AS approved_default_offices
  FROM solar_app.ref_office_locations
 WHERE is_default IS TRUE
   AND active_ind IS TRUE
   AND left(office_code, 4) IS DISTINCT FROM 'DEV_';

-- 5. Approved active visit-charge slabs.
-- Rows created by DEV_SEED are excluded. This count is not a pass or fail.
-- 0 is expected while only development sample bands exist. Do not describe
-- those bands as production prices. New bookings stay unpriced until both
-- this count is at least 1 and check 4 is exactly 1.
-- A count of 1 or more does not by itself prove a fee can be quoted.
-- Missing site coordinates, an unmatched distance, or more than one
-- matching slab can still make the quote unavailable.
SELECT COUNT(*) AS approved_slabs
  FROM solar_app.ref_visit_charge_slabs
 WHERE active_ind IS TRUE
   AND created_by IS DISTINCT FROM 'DEV_SEED';
