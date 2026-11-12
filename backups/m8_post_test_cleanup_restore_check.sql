-- Post-test M81/M82 fixture cleanup for SolarDB_restore_check only.
\set ON_ERROR_STOP on

SELECT current_database() AS db, current_user AS usr;

DO $$
BEGIN
    IF current_database() IS DISTINCT FROM 'SolarDB_restore_check' THEN
        RAISE EXCEPTION 'Refuse cleanup on database %', current_database();
    END IF;
END $$;

BEGIN;

-- M81 cleanup (same predicates as 14_test_m8_1_invoice_register_restore.sql)
DELETE FROM solar_app.log_notification_delivery
 WHERE notification_id IN (
        SELECT notification_id FROM solar_app.notification_details
         WHERE created_by = 'M81_IT'
            OR recipient_user_id IN (
                SELECT user_id FROM solar_app.user_details
                 WHERE mobile_e164 LIKE '+91990081%' OR created_by = 'M81_IT'
            )
      );
DELETE FROM solar_app.notification_details
 WHERE created_by = 'M81_IT'
    OR recipient_user_id IN (
        SELECT user_id FROM solar_app.user_details
         WHERE mobile_e164 LIKE '+91990081%' OR created_by = 'M81_IT'
    );
DELETE FROM solar_app.invoice_tax_details
 WHERE invoice_id IN (SELECT invoice_id FROM solar_app.invoice_details WHERE created_by = 'M81_IT' OR invoice_no LIKE 'M81-%');
DELETE FROM solar_app.invoice_line_details
 WHERE invoice_id IN (SELECT invoice_id FROM solar_app.invoice_details WHERE created_by = 'M81_IT' OR invoice_no LIKE 'M81-%');
DELETE FROM solar_app.payment_details
 WHERE created_by = 'M81_IT'
    OR invoice_id IN (SELECT invoice_id FROM solar_app.invoice_details WHERE created_by = 'M81_IT' OR invoice_no LIKE 'M81-%');
DELETE FROM solar_app.invoice_details WHERE created_by = 'M81_IT' OR invoice_no LIKE 'M81-%';
DELETE FROM solar_app.ref_currencies WHERE currency_code = 'XTS' AND created_by = 'M81_IT';
DELETE FROM solar_app.spare_part_request_details WHERE created_by = 'M81_IT';
DELETE FROM solar_app.job_assignment_details WHERE created_by = 'M81_IT';
DELETE FROM solar_app.service_request_details WHERE created_by = 'M81_IT' OR service_request_no LIKE 'M81-SR-%';
DELETE FROM solar_app.amc_contract_details WHERE created_by = 'M81_IT';
DELETE FROM solar_app.order_details WHERE created_by = 'M81_IT' OR order_no LIKE 'M81-ORD-%';
DELETE FROM solar_app.technician_details
 WHERE created_by = 'M81_IT'
    OR user_id IN (SELECT user_id FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990081%' OR created_by = 'M81_IT');
DELETE FROM solar_app.site_details
 WHERE created_by = 'M81_IT'
    OR customer_id IN (SELECT customer_id FROM solar_app.customer_details WHERE customer_code LIKE 'M81-CUST-%');
DELETE FROM solar_app.customer_details WHERE customer_code LIKE 'M81-CUST-%' OR created_by = 'M81_IT';
DELETE FROM solar_app.log_user_sessions WHERE jwt_token_hash LIKE 'aa81bb00%' OR created_by = 'M81_IT';
DELETE FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990081%' OR created_by = 'M81_IT';
DELETE FROM solar_app.ref_amc_plans WHERE plan_code = 'M81-PLAN' OR created_by = 'M81_IT';

-- M82 cleanup (same predicates as 15_test_m8_2_payment_register_restore.sql)
DELETE FROM solar_app.log_notification_delivery
 WHERE notification_id IN (
        SELECT notification_id FROM solar_app.notification_details
         WHERE created_by = 'M82_IT'
            OR recipient_user_id IN (
                SELECT user_id FROM solar_app.user_details
                 WHERE mobile_e164 LIKE '+91990082%' OR created_by = 'M82_IT'
            )
      );
DELETE FROM solar_app.notification_details
 WHERE created_by = 'M82_IT'
    OR recipient_user_id IN (
        SELECT user_id FROM solar_app.user_details
         WHERE mobile_e164 LIKE '+91990082%' OR created_by = 'M82_IT'
    );
DELETE FROM solar_app.payment_details
 WHERE created_by = 'M82_IT'
    OR invoice_id IN (SELECT invoice_id FROM solar_app.invoice_details WHERE created_by = 'M82_IT' OR invoice_no LIKE 'M82-%');
DELETE FROM solar_app.invoice_tax_details
 WHERE invoice_id IN (SELECT invoice_id FROM solar_app.invoice_details WHERE created_by = 'M82_IT' OR invoice_no LIKE 'M82-%');
DELETE FROM solar_app.invoice_line_details
 WHERE invoice_id IN (SELECT invoice_id FROM solar_app.invoice_details WHERE created_by = 'M82_IT' OR invoice_no LIKE 'M82-%');
DELETE FROM solar_app.invoice_details WHERE created_by = 'M82_IT' OR invoice_no LIKE 'M82-%';
DELETE FROM solar_app.ref_currencies WHERE currency_code = 'XTS' AND created_by = 'M82_IT';
DELETE FROM solar_app.site_details
 WHERE created_by = 'M82_IT'
    OR customer_id IN (SELECT customer_id FROM solar_app.customer_details WHERE customer_code LIKE 'M82-CUST-%');
DELETE FROM solar_app.customer_details WHERE customer_code LIKE 'M82-CUST-%' OR created_by = 'M82_IT';
DELETE FROM solar_app.log_user_sessions WHERE jwt_token_hash LIKE 'bb82cc00%' OR created_by = 'M82_IT';
DELETE FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990082%' OR created_by = 'M82_IT';

COMMIT;

SELECT COUNT(*) AS leftover_inv FROM solar_app.invoice_details WHERE invoice_no LIKE 'M81-%' OR invoice_no LIKE 'M82-%' OR created_by IN ('M81_IT','M82_IT');
SELECT COUNT(*) AS leftover_pay FROM solar_app.payment_details WHERE created_by IN ('M81_IT','M82_IT');
SELECT COUNT(*) AS leftover_users FROM solar_app.user_details WHERE created_by IN ('M81_IT','M82_IT') OR mobile_e164 LIKE '+91990081%' OR mobile_e164 LIKE '+91990082%';
SELECT COUNT(*) AS leftover_cust FROM solar_app.customer_details WHERE created_by IN ('M81_IT','M82_IT') OR customer_code LIKE 'M81-%' OR customer_code LIKE 'M82-%';
SELECT COUNT(*) AS leftover_sess FROM solar_app.log_user_sessions WHERE created_by IN ('M81_IT','M82_IT') OR jwt_token_hash LIKE 'aa81bb00%' OR jwt_token_hash LIKE 'bb82cc00%';
SELECT COUNT(*) AS leftover_ntf FROM solar_app.notification_details WHERE created_by IN ('M81_IT','M82_IT');
