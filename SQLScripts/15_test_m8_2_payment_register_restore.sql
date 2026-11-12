-- Isolated M8.2 offline payment register tests for SolarDB_restore_check only.
-- Do not run against SolarDB.

\set ON_ERROR_STOP on

SELECT current_database() AS db, current_user AS usr;

DO $$
BEGIN
    IF current_database() IS DISTINCT FROM 'SolarDB_restore_check' THEN
        RAISE EXCEPTION 'Refuse to run M8.2 IT on database %', current_database();
    END IF;
END $$;

BEGIN;

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

DO $$
DECLARE
    v_role_admin BIGINT;
    v_role_customer BIGINT;
    v_acct_active BIGINT;
    v_reg_self BIGINT;
    v_inst_status BIGINT;
    v_country_id BIGINT := 1;
    v_currency CHAR(3);
    v_admin_id BIGINT;
    v_cust1_user_id BIGINT;
    v_cust2_user_id BIGINT;
    v_cust1_id BIGINT;
    v_cust2_id BIGINT;
    v_site1_id BIGINT;
    v_admin_hash TEXT := 'bb82cc00dd11ee22ff33445566778899aabbccddeeff00112233445566778899';
    v_cust1_hash TEXT := 'bb82cc00dd11ee22ff33445566778899aabbccddeeff001122334455667788aa';
    v_cust2_hash TEXT := 'bb82cc00dd11ee22ff33445566778899aabbccddeeff001122334455667788bb';
    v_resp JSONB;
    v_inv1_id BIGINT;
    v_inv2_id BIGINT;
    v_inv3_id BIGINT;
    v_draft_id BIGINT;
    v_over_id BIGINT;
    v_pay1_id BIGINT;
    v_pay2_id BIGINT;
    v_pay3_id BIGINT;
    v_pay_full_id BIGINT;
    v_pay_draft_id BIGINT;
    v_pay_remaining_id BIGINT;
    v_inv_status TEXT;
    v_paid NUMERIC(14,2);
    v_bal NUMERIC(14,2);
    v_ntf_count INTEGER;
    v_ntf_active BOOLEAN;
    v_before_pay INTEGER;
    v_after_pay INTEGER;
    v_before_paid NUMERIC(14,2);
    v_before_bal NUMERIC(14,2);
    v_before_status BIGINT;
    v_list_len INTEGER;
BEGIN
    SELECT ref_data_id INTO v_role_admin FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='USER_ROLES' AND r.data_code='ROLE_ADMIN' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_role_customer FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='USER_ROLES' AND r.data_code='ROLE_CUSTOMER' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_acct_active FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='USER_ACCOUNT_STATUSES' AND r.data_code='ACCT_ACTIVE' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_reg_self FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='REGISTRATION_SOURCES' AND r.data_code='REG_SELF_APP' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_inst_status FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='INSTALLATION_STATUSES' AND r.data_code='INST_COMMISSIONED' AND r.active_ind AND c.active_ind;
    SELECT currency_code INTO v_currency FROM solar_app.ref_currencies WHERE active_ind IS TRUE ORDER BY currency_code LIMIT 1;

    IF v_role_admin IS NULL OR v_role_customer IS NULL OR v_acct_active IS NULL OR v_currency IS NULL THEN
        RAISE EXCEPTION 'Missing M8.2 reference fixtures';
    END IF;

    IF to_regprocedure('solar_app.fn_create_notification_details(jsonb)') IS NULL
       OR to_regprocedure('solar_app.fn_create_invoice_details(jsonb)') IS NULL
       OR to_regprocedure('solar_app.fn_update_invoice_details(jsonb)') IS NULL
       OR to_regprocedure('solar_app.fn_create_payment_details(jsonb)') IS NULL
       OR to_regprocedure('solar_app.fn_update_payment_details(jsonb)') IS NULL
       OR to_regprocedure('solar_app.fn_get_payment_details(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'Required M8.2 functions are not installed on SolarDB_restore_check';
    END IF;

    INSERT INTO solar_app.user_details (country_id, mobile_e164, full_name, role_ref_data_id, pin_hash, admin_registered, account_status_ref_data_id, registration_source_ref_data_id, created_by, updated_by)
    VALUES (v_country_id, '+919900820001', 'M82 Admin', v_role_admin, NULL, TRUE, v_acct_active, v_reg_self, 'M82_IT', 'M82_IT')
    RETURNING user_id INTO v_admin_id;
    INSERT INTO solar_app.user_details (country_id, mobile_e164, full_name, role_ref_data_id, pin_hash, admin_registered, account_status_ref_data_id, registration_source_ref_data_id, created_by, updated_by)
    VALUES (v_country_id, '+919900820002', 'M82 Cust1', v_role_customer, NULL, TRUE, v_acct_active, v_reg_self, 'M82_IT', 'M82_IT')
    RETURNING user_id INTO v_cust1_user_id;
    INSERT INTO solar_app.user_details (country_id, mobile_e164, full_name, role_ref_data_id, pin_hash, admin_registered, account_status_ref_data_id, registration_source_ref_data_id, created_by, updated_by)
    VALUES (v_country_id, '+919900820003', 'M82 Cust2', v_role_customer, NULL, TRUE, v_acct_active, v_reg_self, 'M82_IT', 'M82_IT')
    RETURNING user_id INTO v_cust2_user_id;

    INSERT INTO solar_app.customer_details (user_id, customer_code, billing_name, created_by, updated_by)
    VALUES (v_cust1_user_id, 'M82-CUST-0001', 'M82 Cust1', 'M82_IT', 'M82_IT') RETURNING customer_id INTO v_cust1_id;
    INSERT INTO solar_app.customer_details (user_id, customer_code, billing_name, created_by, updated_by)
    VALUES (v_cust2_user_id, 'M82-CUST-0002', 'M82 Cust2', 'M82_IT', 'M82_IT') RETURNING customer_id INTO v_cust2_id;

    INSERT INTO solar_app.site_details (customer_id, site_name, address_line1, installation_status_ref_data_id, commissioning_on, created_by, updated_by)
    VALUES (v_cust1_id, 'M82 Site', '1 M82 Lane', v_inst_status, CURRENT_DATE, 'M82_IT', 'M82_IT')
    RETURNING site_id INTO v_site1_id;

    INSERT INTO solar_app.log_user_sessions (user_id, mobile_e164, jwt_token_hash, session_status, active_ind, created_by, updated_by)
    VALUES
        (v_admin_id, '+919900820001', v_admin_hash, 'ACTIVE', TRUE, 'M82_IT', 'M82_IT'),
        (v_cust1_user_id, '+919900820002', v_cust1_hash, 'ACTIVE', TRUE, 'M82_IT', 'M82_IT'),
        (v_cust2_user_id, '+919900820003', v_cust2_hash, 'ACTIVE', TRUE, 'M82_IT', 'M82_IT');

    -- Seed invoices via M8.1 create
    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices', 'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M82-INV-1000', 'customer_id', v_cust1_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT, 'currency_code', v_currency,
        'invoice_category_code', 'INV_INSTALL', 'site_id', v_site1_id::TEXT,
        'total_amount', '1000.00', 'taxable_amount', '1000', 'tax_amount', '0'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN RAISE EXCEPTION 'Seed inv1 failed: %', v_resp; END IF;
    v_inv1_id := (v_resp->'data'->>'invoice_id')::BIGINT;

    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices', 'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M82-INV-500', 'customer_id', v_cust1_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT, 'currency_code', v_currency,
        'invoice_category_code', 'INV_AMC', 'total_amount', '500.00'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN RAISE EXCEPTION 'Seed inv2 failed: %', v_resp; END IF;
    v_inv2_id := (v_resp->'data'->>'invoice_id')::BIGINT;

    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices', 'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M82-INV-C2', 'customer_id', v_cust2_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT, 'currency_code', v_currency,
        'invoice_category_code', 'INV_CLEANING', 'total_amount', '200.00'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN RAISE EXCEPTION 'Seed inv3 failed: %', v_resp; END IF;
    v_inv3_id := (v_resp->'data'->>'invoice_id')::BIGINT;

    ------------------------------------------------------------------
    -- 1) Full payment → INV_PAID
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments', 'jwt_token_hash', v_admin_hash,
        'invoice_id', v_inv2_id::TEXT, 'amount', '500.00',
        'payment_method_code', 'PAY_CASH', 'paid_on', CURRENT_DATE::TEXT,
        'instrument_ref', 'RCPT-FULL-1',
        'paid_amount', '0', 'balance_amount', '999', 'invoice_status_code', 'INV_UNPAID',
        'is_offline_ind', FALSE
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN RAISE EXCEPTION 'Full payment failed: %', v_resp; END IF;
    IF v_resp->'data'->>'invoice_status_code' <> 'INV_PAID'
       OR (v_resp->'data'->>'invoice_paid_amount')::NUMERIC <> 500
       OR (v_resp->'data'->>'invoice_balance_amount')::NUMERIC <> 0
       OR (v_resp->'data'->>'is_offline_ind')::BOOLEAN IS NOT TRUE THEN
        RAISE EXCEPTION 'Full payment status/offline incorrect: %', v_resp;
    END IF;
    v_pay_full_id := (v_resp->'data'->>'payment_id')::BIGINT;

    ------------------------------------------------------------------
    -- 2) Partial then multiple → UNPAID → PARTIAL → PAID
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments', 'jwt_token_hash', v_admin_hash,
        'invoice_id', v_inv1_id::TEXT, 'amount', '300.00',
        'payment_method_code', 'PAY_UPI_OFFLINE', 'paid_on', CURRENT_DATE::TEXT,
        'instrument_ref', 'UPI-001'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR v_resp->'data'->>'invoice_status_code' <> 'INV_PARTIAL' THEN
        RAISE EXCEPTION 'Partial payment failed: %', v_resp;
    END IF;
    v_pay1_id := (v_resp->'data'->>'payment_id')::BIGINT;

    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments', 'jwt_token_hash', v_admin_hash,
        'invoice_id', v_inv1_id::TEXT, 'amount', '400.00',
        'payment_method_code', 'PAY_NEFT', 'paid_on', CURRENT_DATE::TEXT,
        'instrument_ref', 'UTR-002'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR v_resp->'data'->>'invoice_status_code' <> 'INV_PARTIAL'
       OR (v_resp->'data'->>'invoice_paid_amount')::NUMERIC <> 700 THEN
        RAISE EXCEPTION 'Second partial failed: %', v_resp;
    END IF;
    v_pay2_id := (v_resp->'data'->>'payment_id')::BIGINT;

    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments', 'jwt_token_hash', v_admin_hash,
        'invoice_id', v_inv1_id::TEXT, 'amount', '300.00',
        'payment_method_code', 'PAY_CHEQUE', 'paid_on', CURRENT_DATE::TEXT,
        'instrument_ref', 'CHQ-003'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR v_resp->'data'->>'invoice_status_code' <> 'INV_PAID'
       OR (v_resp->'data'->>'invoice_balance_amount')::NUMERIC <> 0 THEN
        RAISE EXCEPTION 'Final payment to PAID failed: %', v_resp;
    END IF;
    v_pay3_id := (v_resp->'data'->>'payment_id')::BIGINT;

    SELECT COUNT(*) INTO v_ntf_count
      FROM solar_app.notification_details n
      JOIN solar_app.ref_data t ON t.ref_data_id = n.notification_type_ref_data_id
     WHERE n.related_entity_type = 'PAYMENT'
       AND n.related_entity_id = v_pay3_id
       AND t.data_code = 'NTF_BILLING_UPDATE'
       AND n.active_ind;
    IF v_ntf_count < 1 THEN RAISE EXCEPTION 'NTF_BILLING_UPDATE missing on create'; END IF;

    ------------------------------------------------------------------
    -- 3) Update amount/method/reference/date
    ------------------------------------------------------------------
    v_resp := solar_app.fn_update_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments/update', 'jwt_token_hash', v_admin_hash,
        'payment_id', v_pay1_id::TEXT,
        'amount', '250.00',
        'payment_method_code', 'PAY_OTHER',
        'instrument_ref', 'OTH-001',
        'paid_on', (CURRENT_DATE - 1)::TEXT,
        'remarks', 'adjusted'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR v_resp->'data'->>'payment_method_code' <> 'PAY_OTHER'
       OR (v_resp->'data'->>'amount')::NUMERIC <> 250
       OR v_resp->'data'->>'invoice_status_code' <> 'INV_PARTIAL'
       OR (v_resp->'data'->>'invoice_paid_amount')::NUMERIC <> 950 THEN
        RAISE EXCEPTION 'Payment update failed: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 4) Cancel payment → balance/status recalc
    ------------------------------------------------------------------
    v_resp := solar_app.fn_update_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments/update', 'jwt_token_hash', v_admin_hash,
        'payment_id', v_pay2_id::TEXT,
        'payment_status_code', 'PAY_CANCELLED'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR v_resp->'data'->>'payment_status_code' <> 'PAY_CANCELLED'
       OR (v_resp->'data'->>'invoice_paid_amount')::NUMERIC <> 550
       OR v_resp->'data'->>'invoice_status_code' <> 'INV_PARTIAL' THEN
        RAISE EXCEPTION 'Cancel payment recalc failed: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 5) Invalid method / currency mismatch / overpayment
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments', 'jwt_token_hash', v_admin_hash,
        'invoice_id', v_inv3_id::TEXT, 'amount', '10',
        'payment_method_code', 'PAY_GATEWAY', 'paid_on', CURRENT_DATE::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 400 THEN
        RAISE EXCEPTION 'Invalid method should be 400: %', v_resp;
    END IF;

    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments', 'jwt_token_hash', v_admin_hash,
        'invoice_id', v_inv3_id::TEXT, 'amount', '10',
        'payment_method_code', 'PAY_CASH', 'paid_on', CURRENT_DATE::TEXT,
        'currency_code', 'ZZZ'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 400 THEN
        RAISE EXCEPTION 'Currency mismatch should be 400: %', v_resp;
    END IF;

    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments', 'jwt_token_hash', v_admin_hash,
        'invoice_id', v_inv3_id::TEXT, 'amount', '250.00',
        'payment_method_code', 'PAY_CASH', 'paid_on', CURRENT_DATE::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 409 THEN
        RAISE EXCEPTION 'Overpayment should be 409: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 6) Customer cannot create/update; ownership on get
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments', 'jwt_token_hash', v_cust1_hash,
        'invoice_id', v_inv3_id::TEXT, 'amount', '10',
        'payment_method_code', 'PAY_CASH', 'paid_on', CURRENT_DATE::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 403 THEN
        RAISE EXCEPTION 'Customer create should be 403: %', v_resp;
    END IF;

    v_resp := solar_app.fn_update_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments/update', 'jwt_token_hash', v_cust1_hash,
        'payment_id', v_pay1_id::TEXT, 'remarks', 'hack'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 403 THEN
        RAISE EXCEPTION 'Customer update should be 403: %', v_resp;
    END IF;

    -- Seed a payment for cust2
    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments', 'jwt_token_hash', v_admin_hash,
        'invoice_id', v_inv3_id::TEXT, 'amount', '50.00',
        'payment_method_code', 'PAY_CASH', 'paid_on', CURRENT_DATE::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN RAISE EXCEPTION 'Cust2 payment seed failed: %', v_resp; END IF;

    v_resp := solar_app.fn_get_payment_details(jsonb_build_object(
        'api_endpoint', '/api/payments', 'jwt_token_hash', v_cust1_hash
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN RAISE EXCEPTION 'Cust1 list failed: %', v_resp; END IF;
    v_list_len := jsonb_array_length(v_resp->'data'->'payments');
    IF v_list_len < 3 THEN RAISE EXCEPTION 'Cust1 should see own payments, got %', v_list_len; END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_resp->'data'->'payments') p
         WHERE (p->>'customer_id')::BIGINT IS DISTINCT FROM v_cust1_id
    ) THEN
        RAISE EXCEPTION 'Cust1 saw another customer payment';
    END IF;

    v_resp := solar_app.fn_get_payment_details(jsonb_build_object(
        'api_endpoint', '/api/payments', 'jwt_token_hash', v_cust1_hash,
        'customer_id', v_cust2_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 403 THEN
        RAISE EXCEPTION 'Cust1 viewing cust2 payments should be 403: %', v_resp;
    END IF;

    v_resp := solar_app.fn_get_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments', 'jwt_token_hash', v_admin_hash
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR jsonb_array_length(v_resp->'data'->'payments') < 4 THEN
        RAISE EXCEPTION 'Admin cross-customer list failed: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 7) Invalid / duplicate-style requests
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments', 'jwt_token_hash', v_admin_hash,
        'amount', '10', 'payment_method_code', 'PAY_CASH', 'paid_on', CURRENT_DATE::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 400 THEN
        RAISE EXCEPTION 'Missing invoice_id should be 400: %', v_resp;
    END IF;

    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments', 'jwt_token_hash', v_admin_hash,
        'invoice_id', '999999999', 'amount', '10',
        'payment_method_code', 'PAY_CASH', 'paid_on', CURRENT_DATE::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 404 THEN
        RAISE EXCEPTION 'Unknown invoice should be 404: %', v_resp;
    END IF;

    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments', 'jwt_token_hash', v_admin_hash,
        'invoice_id', v_inv3_id::TEXT, 'amount', '0',
        'payment_method_code', 'PAY_CASH', 'paid_on', CURRENT_DATE::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 400 THEN
        RAISE EXCEPTION 'Zero amount should be 400: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 8) Concurrent-style balance integrity (sequential locked creates)
    ------------------------------------------------------------------
    -- Remaining balance on inv3 is 150 after 50 recorded.
    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments', 'jwt_token_hash', v_admin_hash,
        'invoice_id', v_inv3_id::TEXT, 'amount', '150.00',
        'payment_method_code', 'PAY_CASH', 'paid_on', CURRENT_DATE::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR v_resp->'data'->>'invoice_status_code' <> 'INV_PAID' THEN
        RAISE EXCEPTION 'Fill remaining balance failed: %', v_resp;
    END IF;
    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments', 'jwt_token_hash', v_admin_hash,
        'invoice_id', v_inv3_id::TEXT, 'amount', '1.00',
        'payment_method_code', 'PAY_CASH', 'paid_on', CURRENT_DATE::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 409 THEN
        RAISE EXCEPTION 'Post-paid overpayment should be 409: %', v_resp;
    END IF;
    SELECT paid_amount, balance_amount INTO v_paid, v_bal
      FROM solar_app.invoice_details WHERE invoice_id = v_inv3_id;
    IF v_paid <> 200 OR v_bal <> 0 THEN
        RAISE EXCEPTION 'Invoice balance integrity broken: paid=% bal=%', v_paid, v_bal;
    END IF;

    -- Amount update that would overpay must roll back
    SELECT paid_amount, balance_amount, invoice_status_ref_data_id
      INTO v_before_paid, v_before_bal, v_before_status
      FROM solar_app.invoice_details WHERE invoice_id = v_inv1_id;
    v_resp := solar_app.fn_update_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments/update', 'jwt_token_hash', v_admin_hash,
        'payment_id', v_pay1_id::TEXT, 'amount', '900.00'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 409 THEN
        RAISE EXCEPTION 'Update overpayment should be 409: %', v_resp;
    END IF;
    IF EXISTS (
        SELECT 1 FROM solar_app.invoice_details
         WHERE invoice_id = v_inv1_id
           AND (paid_amount IS DISTINCT FROM v_before_paid
                OR balance_amount IS DISTINCT FROM v_before_bal
                OR invoice_status_ref_data_id IS DISTINCT FROM v_before_status)
    ) OR EXISTS (
        SELECT 1 FROM solar_app.payment_details WHERE payment_id = v_pay1_id AND amount IS DISTINCT FROM 250
    ) THEN
        RAISE EXCEPTION 'Existing invoice/payment mutated on rejected overpay update';
    END IF;

    ------------------------------------------------------------------
    -- 9) Notification failure rolls back payment + invoice
    ------------------------------------------------------------------
    -- Restore some room on inv1 by ensuring balance > 0 (already PARTIAL ~550 paid of 1000)
    SELECT paid_amount, balance_amount INTO v_before_paid, v_before_bal
      FROM solar_app.invoice_details WHERE invoice_id = v_inv1_id;
    SELECT COUNT(*) INTO v_before_pay FROM solar_app.payment_details WHERE invoice_id = v_inv1_id;

    SELECT r.active_ind INTO v_ntf_active
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'NOTIFICATION_TYPES' AND r.data_code = 'NTF_BILLING_UPDATE';
    UPDATE solar_app.ref_data r
       SET active_ind = FALSE
      FROM solar_app.ref_data_categories c
     WHERE c.category_id = r.category_id
       AND c.category_code = 'NOTIFICATION_TYPES'
       AND r.data_code = 'NTF_BILLING_UPDATE';

    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments', 'jwt_token_hash', v_admin_hash,
        'invoice_id', v_inv1_id::TEXT, 'amount', '10.00',
        'payment_method_code', 'PAY_CASH', 'paid_on', CURRENT_DATE::TEXT
    ));

    UPDATE solar_app.ref_data r
       SET active_ind = COALESCE(v_ntf_active, TRUE)
      FROM solar_app.ref_data_categories c
     WHERE c.category_id = r.category_id
       AND c.category_code = 'NOTIFICATION_TYPES'
       AND r.data_code = 'NTF_BILLING_UPDATE';

    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 500 THEN
        RAISE EXCEPTION 'Notification failure should return 500: %', v_resp;
    END IF;
    SELECT COUNT(*) INTO v_after_pay FROM solar_app.payment_details WHERE invoice_id = v_inv1_id;
    SELECT paid_amount, balance_amount INTO v_paid, v_bal
      FROM solar_app.invoice_details WHERE invoice_id = v_inv1_id;
    IF v_after_pay IS DISTINCT FROM v_before_pay
       OR v_paid IS DISTINCT FROM v_before_paid
       OR v_bal IS DISTINCT FROM v_before_bal THEN
        RAISE EXCEPTION 'Notification failure did not roll back payment/invoice';
    END IF;

    ------------------------------------------------------------------
    -- 10) Existing invoice data preserved on successful cancel-all path check
    ------------------------------------------------------------------
    v_resp := solar_app.fn_update_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments/update', 'jwt_token_hash', v_admin_hash,
        'payment_id', v_pay_full_id::TEXT, 'payment_status_code', 'PAY_CANCELLED'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR v_resp->'data'->>'invoice_status_code' <> 'INV_UNPAID'
       OR (v_resp->'data'->>'invoice_paid_amount')::NUMERIC <> 0
       OR (v_resp->'data'->>'invoice_balance_amount')::NUMERIC <> 500 THEN
        RAISE EXCEPTION 'Cancel full payment should return UNPAID: %', v_resp;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM solar_app.invoice_details
         WHERE invoice_id = v_inv2_id AND total_amount = 500 AND invoice_no = 'M82-INV-500'
    ) THEN
        RAISE EXCEPTION 'Invoice header totals were not preserved';
    END IF;

    ------------------------------------------------------------------
    -- 11) Draft payment rejected; unpaid accepted; cancel → UNPAID
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M82-INV-DRAFT',
        'customer_id', v_cust1_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_INSTALL',
        'total_amount', '100.00',
        'invoice_status_code', 'INV_DRAFT'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Draft invoice create for payment IT failed: %', v_resp;
    END IF;
    v_draft_id := (v_resp->'data'->>'invoice_id')::BIGINT;

    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments',
        'jwt_token_hash', v_admin_hash,
        'invoice_id', v_draft_id::TEXT,
        'amount', '10.00',
        'payment_method_code', 'PAY_CASH',
        'paid_on', CURRENT_DATE::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 409 THEN
        RAISE EXCEPTION 'Payment against draft should be 409: %', v_resp;
    END IF;

    v_resp := solar_app.fn_update_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices/update',
        'jwt_token_hash', v_admin_hash,
        'invoice_id', v_draft_id::TEXT,
        'invoice_status_code', 'INV_UNPAID'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR v_resp->'data'->>'invoice_status_code' <> 'INV_UNPAID' THEN
        RAISE EXCEPTION 'Draft to unpaid update failed: %', v_resp;
    END IF;

    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments',
        'jwt_token_hash', v_admin_hash,
        'invoice_id', v_draft_id::TEXT,
        'amount', '40.00',
        'payment_method_code', 'PAY_CASH',
        'paid_on', CURRENT_DATE::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR v_resp->'data'->>'invoice_status_code' <> 'INV_PARTIAL' THEN
        RAISE EXCEPTION 'Unpaid invoice partial payment failed: %', v_resp;
    END IF;
    v_pay_draft_id := (v_resp->'data'->>'payment_id')::BIGINT;

    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments',
        'jwt_token_hash', v_admin_hash,
        'invoice_id', v_draft_id::TEXT,
        'amount', '60.00',
        'payment_method_code', 'PAY_UPI_OFFLINE',
        'paid_on', CURRENT_DATE::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR v_resp->'data'->>'invoice_status_code' <> 'INV_PAID' THEN
        RAISE EXCEPTION 'Full payment should set INV_PAID: %', v_resp;
    END IF;

    v_resp := solar_app.fn_update_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments/update',
        'jwt_token_hash', v_admin_hash,
        'payment_id', v_pay_draft_id::TEXT,
        'payment_status_code', 'PAY_CANCELLED'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR v_resp->'data'->>'invoice_status_code' <> 'INV_PARTIAL' THEN
        RAISE EXCEPTION 'Cancel one of two payments should leave PARTIAL: %', v_resp;
    END IF;

    -- Cancel remaining active payment → UNPAID
    SELECT payment_id INTO v_pay_remaining_id
      FROM solar_app.payment_details pay
      JOIN solar_app.ref_data st ON st.ref_data_id = pay.payment_status_ref_data_id
     WHERE pay.invoice_id = v_draft_id
       AND pay.active_ind IS TRUE
       AND st.data_code = 'PAY_RECORDED'
     ORDER BY pay.payment_id DESC
     LIMIT 1;
    v_resp := solar_app.fn_update_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments/update',
        'jwt_token_hash', v_admin_hash,
        'payment_id', v_pay_remaining_id::TEXT,
        'payment_status_code', 'PAY_CANCELLED'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR v_resp->'data'->>'invoice_status_code' <> 'INV_UNPAID'
       OR (v_resp->'data'->>'invoice_paid_amount')::NUMERIC <> 0 THEN
        RAISE EXCEPTION 'Cancel all recorded payments should set INV_UNPAID: %', v_resp;
    END IF;

    -- Currency cannot change after cancelled payment history remains
    INSERT INTO solar_app.ref_currencies (currency_code, currency_name, decimal_places, created_by, updated_by)
    VALUES ('XTS', 'M82 Test Currency', 2, 'M82_IT', 'M82_IT')
    ON CONFLICT (currency_code) DO UPDATE
       SET active_ind = TRUE,
           updated_by = 'M82_IT',
           updated_on = CURRENT_TIMESTAMP;

    v_resp := solar_app.fn_update_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices/update',
        'jwt_token_hash', v_admin_hash,
        'invoice_id', v_draft_id::TEXT,
        'currency_code', 'XTS'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 409 THEN
        RAISE EXCEPTION 'Currency change with cancelled payment history should be 409: %', v_resp;
    END IF;

    -- Concurrent-style overpay protection: lock serializes; second excess payment 409
    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M82-INV-OVER',
        'customer_id', v_cust1_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_INSTALL',
        'total_amount', '100.00'
    ));
    v_over_id := (v_resp->'data'->>'invoice_id')::BIGINT;
    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments',
        'jwt_token_hash', v_admin_hash,
        'invoice_id', v_over_id::TEXT,
        'amount', '70.00',
        'payment_method_code', 'PAY_CASH',
        'paid_on', CURRENT_DATE::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Seed payment for overpay lock test failed: %', v_resp;
    END IF;
    v_resp := solar_app.fn_create_payment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/payments',
        'jwt_token_hash', v_admin_hash,
        'invoice_id', v_over_id::TEXT,
        'amount', '40.00',
        'payment_method_code', 'PAY_CASH',
        'paid_on', CURRENT_DATE::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 409 THEN
        RAISE EXCEPTION 'Second concurrent-style overpay should be 409: %', v_resp;
    END IF;

    RAISE NOTICE 'M8.2 payment register restore_check IT passed';
END $$;
