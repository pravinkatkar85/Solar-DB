-- Isolated M8.1 offline invoice register tests for SolarDB_restore_check only.
-- Do not run against SolarDB.

\set ON_ERROR_STOP on

SELECT current_database() AS db, current_user AS usr;

DO $$
BEGIN
    IF current_database() IS DISTINCT FROM 'SolarDB_restore_check' THEN
        RAISE EXCEPTION 'Refuse to run M8.1 IT on database %', current_database();
    END IF;
END $$;

BEGIN;

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

COMMIT;

DO $$
DECLARE
    v_role_admin BIGINT;
    v_role_customer BIGINT;
    v_role_tech BIGINT;
    v_acct_active BIGINT;
    v_reg_self BIGINT;
    v_inst_status BIGINT;
    v_ord_status BIGINT;
    v_sr_open BIGINT;
    v_job_queued BIGINT;
    v_service_type BIGINT;
    v_pay_method BIGINT;
    v_pay_status BIGINT;
    v_country_id BIGINT := 1;
    v_currency CHAR(3);
    v_admin_id BIGINT;
    v_cust1_user_id BIGINT;
    v_cust2_user_id BIGINT;
    v_cust3_user_id BIGINT;
    v_cust1_id BIGINT;
    v_cust2_id BIGINT;
    v_cust3_id BIGINT;
    v_site1_id BIGINT;
    v_site2_id BIGINT;
    v_order_id BIGINT;
    v_amc_plan_id BIGINT;
    v_amc_id BIGINT;
    v_sr_id BIGINT;
    v_tech_user_id BIGINT;
    v_tech_id BIGINT;
    v_job_id BIGINT;
    v_spr_id BIGINT;
    v_admin_hash TEXT := 'aa81bb00cc11dd22ee33ff44556677889900aabbccddeeff0011223344556677';
    v_cust1_hash TEXT := 'aa81bb00cc11dd22ee33ff44556677889900aabbccddeeff0011223344556688';
    v_cust2_hash TEXT := 'aa81bb00cc11dd22ee33ff44556677889900aabbccddeeff0011223344556699';
    v_cust3_hash TEXT := 'aa81bb00cc11dd22ee33ff44556677889900aabbccddeeff00112233445566aa';
    v_resp JSONB;
    v_inv1_id BIGINT;
    v_inv2_id BIGINT;
    v_inv3_id BIGINT;
    v_preserve_id BIGINT;
    v_draft_id BIGINT;
    v_paid_before NUMERIC(14,2);
    v_bal_before NUMERIC(14,2);
    v_status_before BIGINT;
    v_ntf_count INTEGER;
    v_ntf_active BOOLEAN;
    v_before_count INTEGER;
    v_after_count INTEGER;
    v_line_count INTEGER;
    v_tax_count INTEGER;
    v_list_len INTEGER;
BEGIN
    SELECT ref_data_id INTO v_role_admin FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='USER_ROLES' AND r.data_code='ROLE_ADMIN' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_role_customer FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='USER_ROLES' AND r.data_code='ROLE_CUSTOMER' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_role_tech FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='USER_ROLES' AND r.data_code='ROLE_TECHNICIAN' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_acct_active FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='USER_ACCOUNT_STATUSES' AND r.data_code='ACCT_ACTIVE' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_reg_self FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='REGISTRATION_SOURCES' AND r.data_code='REG_SELF_APP' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_inst_status FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='INSTALLATION_STATUSES' AND r.data_code='INST_COMMISSIONED' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_ord_status FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='ORDER_STATUSES' AND r.data_code='ORD_CONFIRMED' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_sr_open FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='SERVICE_REQUEST_STATUSES' AND r.data_code='SR_OPEN' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_job_queued FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='JOB_STATUSES' AND r.data_code='JOB_QUEUED' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_service_type FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='SERVICE_TYPES' AND r.active_ind AND c.active_ind ORDER BY r.ref_data_id LIMIT 1;
    SELECT ref_data_id INTO v_pay_method FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='PAYMENT_METHODS' AND r.active_ind AND c.active_ind ORDER BY r.ref_data_id LIMIT 1;
    SELECT ref_data_id INTO v_pay_status FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='PAYMENT_STATUSES' AND r.data_code='PAY_RECORDED' AND r.active_ind AND c.active_ind;
    SELECT currency_code INTO v_currency FROM solar_app.ref_currencies WHERE active_ind IS TRUE ORDER BY currency_code LIMIT 1;

    IF v_role_admin IS NULL OR v_role_customer IS NULL OR v_acct_active IS NULL OR v_currency IS NULL
       OR v_inst_status IS NULL OR v_ord_status IS NULL OR v_sr_open IS NULL OR v_pay_method IS NULL OR v_pay_status IS NULL THEN
        RAISE EXCEPTION 'Missing M8.1 reference fixtures';
    END IF;

    IF to_regprocedure('solar_app.fn_create_notification_details(jsonb)') IS NULL
       OR to_regprocedure('solar_app.fn_create_invoice_details(jsonb)') IS NULL
       OR to_regprocedure('solar_app.fn_update_invoice_details(jsonb)') IS NULL
       OR to_regprocedure('solar_app.fn_get_invoice_details(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'Required M8.1 functions are not installed on SolarDB_restore_check';
    END IF;

    INSERT INTO solar_app.user_details (country_id, mobile_e164, full_name, role_ref_data_id, pin_hash, admin_registered, account_status_ref_data_id, registration_source_ref_data_id, created_by, updated_by)
    VALUES (v_country_id, '+919900810001', 'M81 Admin', v_role_admin, NULL, TRUE, v_acct_active, v_reg_self, 'M81_IT', 'M81_IT')
    RETURNING user_id INTO v_admin_id;

    INSERT INTO solar_app.user_details (country_id, mobile_e164, full_name, role_ref_data_id, pin_hash, admin_registered, account_status_ref_data_id, registration_source_ref_data_id, created_by, updated_by)
    VALUES (v_country_id, '+919900810002', 'M81 Customer 1', v_role_customer, NULL, TRUE, v_acct_active, v_reg_self, 'M81_IT', 'M81_IT')
    RETURNING user_id INTO v_cust1_user_id;
    INSERT INTO solar_app.user_details (country_id, mobile_e164, full_name, role_ref_data_id, pin_hash, admin_registered, account_status_ref_data_id, registration_source_ref_data_id, created_by, updated_by)
    VALUES (v_country_id, '+919900810003', 'M81 Customer 2', v_role_customer, NULL, TRUE, v_acct_active, v_reg_self, 'M81_IT', 'M81_IT')
    RETURNING user_id INTO v_cust2_user_id;
    INSERT INTO solar_app.user_details (country_id, mobile_e164, full_name, role_ref_data_id, pin_hash, admin_registered, account_status_ref_data_id, registration_source_ref_data_id, created_by, updated_by)
    VALUES (v_country_id, '+919900810004', 'M81 Customer 3', v_role_customer, NULL, TRUE, v_acct_active, v_reg_self, 'M81_IT', 'M81_IT')
    RETURNING user_id INTO v_cust3_user_id;
    INSERT INTO solar_app.user_details (country_id, mobile_e164, full_name, role_ref_data_id, pin_hash, admin_registered, account_status_ref_data_id, registration_source_ref_data_id, created_by, updated_by)
    VALUES (v_country_id, '+919900810005', 'M81 Tech', v_role_tech, NULL, TRUE, v_acct_active, v_reg_self, 'M81_IT', 'M81_IT')
    RETURNING user_id INTO v_tech_user_id;

    INSERT INTO solar_app.customer_details (user_id, customer_code, billing_name, created_by, updated_by)
    VALUES (v_cust1_user_id, 'M81-CUST-0001', 'M81 Cust1', 'M81_IT', 'M81_IT') RETURNING customer_id INTO v_cust1_id;
    INSERT INTO solar_app.customer_details (user_id, customer_code, billing_name, created_by, updated_by)
    VALUES (v_cust2_user_id, 'M81-CUST-0002', 'M81 Cust2', 'M81_IT', 'M81_IT') RETURNING customer_id INTO v_cust2_id;
    INSERT INTO solar_app.customer_details (user_id, customer_code, billing_name, created_by, updated_by)
    VALUES (v_cust3_user_id, 'M81-CUST-0003', 'M81 Cust3', 'M81_IT', 'M81_IT') RETURNING customer_id INTO v_cust3_id;

    INSERT INTO solar_app.site_details (customer_id, site_name, address_line1, installation_status_ref_data_id, commissioning_on, created_by, updated_by)
    VALUES (v_cust1_id, 'M81 Site 1', '1 M81 Lane', v_inst_status, CURRENT_DATE, 'M81_IT', 'M81_IT')
    RETURNING site_id INTO v_site1_id;
    INSERT INTO solar_app.site_details (customer_id, site_name, address_line1, installation_status_ref_data_id, commissioning_on, created_by, updated_by)
    VALUES (v_cust2_id, 'M81 Site 2', '2 M81 Lane', v_inst_status, CURRENT_DATE, 'M81_IT', 'M81_IT')
    RETURNING site_id INTO v_site2_id;

    INSERT INTO solar_app.order_details (order_no, order_source, customer_id, site_id, order_status_ref_data_id, currency_code, created_by, updated_by)
    VALUES ('M81-ORD-0001', 'MANUAL', v_cust1_id, v_site1_id, v_ord_status, v_currency, 'M81_IT', 'M81_IT')
    RETURNING order_id INTO v_order_id;

    INSERT INTO solar_app.ref_amc_plans (
        plan_code, plan_name, duration_months, includes_breakdown, includes_cleaning,
        free_visit_count, free_visit_radius_km, plan_price, currency_code,
        effective_from, active_ind, created_by, updated_by
    ) VALUES (
        'M81-PLAN', 'M81 Test Plan', 12, TRUE, TRUE,
        2, 25, 1000, v_currency,
        CURRENT_DATE, TRUE, 'M81_IT', 'M81_IT'
    )
    RETURNING amc_plan_id INTO v_amc_plan_id;

    INSERT INTO solar_app.amc_contract_details (site_id, amc_plan_id, start_on, expiry_on, currency_code, created_by, updated_by)
    VALUES (v_site1_id, v_amc_plan_id, CURRENT_DATE, CURRENT_DATE + 365, v_currency, 'M81_IT', 'M81_IT')
    RETURNING amc_contract_id INTO v_amc_id;

    INSERT INTO solar_app.service_request_details (service_request_no, site_id, customer_id, service_type_ref_data_id, status_ref_data_id, created_by, updated_by)
    VALUES ('M81-SR-0001', v_site1_id, v_cust1_id, v_service_type, v_sr_open, 'M81_IT', 'M81_IT')
    RETURNING service_request_id INTO v_sr_id;

    INSERT INTO solar_app.technician_details (user_id, employee_code, is_available, created_by, updated_by)
    VALUES (v_tech_user_id, 'M81-EMP-1', TRUE, 'M81_IT', 'M81_IT')
    RETURNING technician_id INTO v_tech_id;

    INSERT INTO solar_app.job_assignment_details (job_type, site_id, technician_id, service_request_id, job_status_ref_data_id, scheduled_on, created_by, updated_by)
    VALUES ('SERVICE_REQUEST', v_site1_id, v_tech_id, v_sr_id, v_job_queued, CURRENT_DATE, 'M81_IT', 'M81_IT')
    RETURNING job_id INTO v_job_id;

    INSERT INTO solar_app.spare_part_request_details (job_id, part_name, quantity, created_by, updated_by)
    VALUES (v_job_id, 'M81 Fuse', 1, 'M81_IT', 'M81_IT')
    RETURNING spare_part_request_id INTO v_spr_id;

    INSERT INTO solar_app.log_user_sessions (user_id, mobile_e164, jwt_token_hash, session_status, active_ind, created_by, updated_by)
    VALUES
        (v_admin_id, '+919900810001', v_admin_hash, 'ACTIVE', TRUE, 'M81_IT', 'M81_IT'),
        (v_cust1_user_id, '+919900810002', v_cust1_hash, 'ACTIVE', TRUE, 'M81_IT', 'M81_IT'),
        (v_cust2_user_id, '+919900810003', v_cust2_hash, 'ACTIVE', TRUE, 'M81_IT', 'M81_IT'),
        (v_cust3_user_id, '+919900810004', v_cust3_hash, 'ACTIVE', TRUE, 'M81_IT', 'M81_IT');

    ------------------------------------------------------------------
    -- 1) Admin header-only invoice
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M81-INV-HEADER',
        'customer_id', v_cust1_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_INSTALL',
        'taxable_amount', '1000.00',
        'tax_amount', '180.00',
        'total_amount', '1180.00',
        'paid_amount', '999.00',
        'balance_amount', '1.00',
        'site_id', v_site1_id::TEXT,
        'related_order_id', v_order_id::TEXT,
        'related_amc_contract_id', v_amc_id::TEXT,
        'related_service_request_id', v_sr_id::TEXT,
        'related_spare_part_request_id', v_spr_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' OR (v_resp->>'code')::INT <> 200 THEN
        RAISE EXCEPTION 'Header-only create failed: %', v_resp;
    END IF;
    IF (v_resp->'data'->>'paid_amount')::NUMERIC <> 0
       OR (v_resp->'data'->>'balance_amount')::NUMERIC <> 1180
       OR v_resp->'data'->>'invoice_status_code' <> 'INV_UNPAID' THEN
        RAISE EXCEPTION 'Client paid/balance override not ignored: %', v_resp;
    END IF;
    v_inv1_id := (v_resp->'data'->>'invoice_id')::BIGINT;

    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M81-INV-BAD-STATUS',
        'customer_id', v_cust1_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_INSTALL',
        'total_amount', '10',
        'invoice_status_code', 'INV_PAID'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 400 THEN
        RAISE EXCEPTION 'Client INV_PAID on create should be 400: %', v_resp;
    END IF;

    SELECT COUNT(*) INTO v_ntf_count
      FROM solar_app.notification_details n
      JOIN solar_app.ref_data t ON t.ref_data_id = n.notification_type_ref_data_id
     WHERE n.related_entity_type = 'INVOICE'
       AND n.related_entity_id = v_inv1_id
       AND n.recipient_user_id = v_cust1_user_id
       AND t.data_code = 'NTF_BILLING_UPDATE'
       AND n.active_ind;
    IF v_ntf_count < 1 THEN
        RAISE EXCEPTION 'NTF_BILLING_UPDATE not enqueued on create';
    END IF;

    ------------------------------------------------------------------
    -- 2) Admin invoice with multiple lines
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M81-INV-LINES',
        'customer_id', v_cust1_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_SPARE',
        'taxable_amount', '500.00',
        'tax_amount', '0',
        'total_amount', '500.00',
        'lines', jsonb_build_array(
            jsonb_build_object('line_no', 1, 'line_desc', 'Fuse kit', 'quantity', '2', 'unit_rate', '100', 'line_amount', '200'),
            jsonb_build_object('line_no', 2, 'line_desc', 'Labour', 'quantity', '1', 'unit_rate', '300', 'line_amount', '300')
        )
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Multi-line create failed: %', v_resp;
    END IF;
    v_inv2_id := (v_resp->'data'->>'invoice_id')::BIGINT;
    SELECT COUNT(*) INTO v_line_count FROM solar_app.invoice_line_details WHERE invoice_id = v_inv2_id AND active_ind;
    IF v_line_count <> 2 THEN
        RAISE EXCEPTION 'Expected 2 active lines, got %', v_line_count;
    END IF;

    ------------------------------------------------------------------
    -- 3) Admin transcribed tax snapshots
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M81-INV-TAX',
        'customer_id', v_cust2_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_AMC',
        'site_id', v_site2_id::TEXT,
        'taxable_amount', '1000.00',
        'tax_amount', '180.00',
        'total_amount', '1180.00',
        'lines', jsonb_build_array(
            jsonb_build_object('line_no', 1, 'line_desc', 'AMC year', 'line_amount', '1000')
        ),
        'tax_snapshots', jsonb_build_array(
            jsonb_build_object(
                'tax_group_code', 'GST',
                'tax_component_code', 'CGST',
                'tax_display_name', 'CGST 9%',
                'calculation_method', 'PERCENTAGE',
                'rate_percent', '9',
                'taxable_amount', '1000',
                'tax_amount', '90',
                'line_no', 1
            ),
            jsonb_build_object(
                'tax_group_code', 'GST',
                'tax_component_code', 'SGST',
                'tax_display_name', 'SGST 9%',
                'calculation_method', 'PERCENTAGE',
                'rate_percent', '9',
                'taxable_amount', '1000',
                'tax_amount', '90'
            )
        )
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Tax snapshot create failed: %', v_resp;
    END IF;
    v_inv3_id := (v_resp->'data'->>'invoice_id')::BIGINT;
    SELECT COUNT(*) INTO v_tax_count
      FROM solar_app.invoice_tax_details
     WHERE invoice_id = v_inv3_id AND active_ind AND source_tax_rule_id IS NULL;
    IF v_tax_count <> 2 THEN
        RAISE EXCEPTION 'Expected 2 transcribed tax rows, got %', v_tax_count;
    END IF;

    ------------------------------------------------------------------
    -- 4) Duplicate invoice number rejected
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M81-INV-HEADER',
        'customer_id', v_cust1_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_INSTALL',
        'total_amount', '10'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 409 THEN
        RAISE EXCEPTION 'Duplicate invoice_no should be 409: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 5) Invalid customer / currency / category
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M81-INV-BAD-CUST',
        'customer_id', '999999999',
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_INSTALL',
        'total_amount', '10'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 404 THEN
        RAISE EXCEPTION 'Invalid customer should be 404: %', v_resp;
    END IF;

    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M81-INV-BAD-CUR',
        'customer_id', v_cust1_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', 'ZZZ',
        'invoice_category_code', 'INV_INSTALL',
        'total_amount', '10'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 400 THEN
        RAISE EXCEPTION 'Invalid currency should be 400: %', v_resp;
    END IF;

    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M81-INV-BAD-CAT',
        'customer_id', v_cust1_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_NOT_REAL',
        'total_amount', '10'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 400 THEN
        RAISE EXCEPTION 'Invalid category should be 400: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 6) Invalid linked site / order / AMC / SR / spare
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M81-INV-BAD-SITE',
        'customer_id', v_cust1_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_INSTALL',
        'total_amount', '10',
        'site_id', v_site2_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 404 THEN
        RAISE EXCEPTION 'Cross-customer site should be 404: %', v_resp;
    END IF;

    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M81-INV-BAD-ORD',
        'customer_id', v_cust2_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_INSTALL',
        'total_amount', '10',
        'related_order_id', v_order_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 404 THEN
        RAISE EXCEPTION 'Cross-customer order should be 404: %', v_resp;
    END IF;

    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M81-INV-BAD-AMC',
        'customer_id', v_cust2_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_AMC',
        'total_amount', '10',
        'related_amc_contract_id', v_amc_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 404 THEN
        RAISE EXCEPTION 'Cross-customer AMC should be 404: %', v_resp;
    END IF;

    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M81-INV-BAD-SR',
        'customer_id', v_cust2_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_CLEANING',
        'total_amount', '10',
        'related_service_request_id', v_sr_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 404 THEN
        RAISE EXCEPTION 'Cross-customer SR should be 404: %', v_resp;
    END IF;

    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M81-INV-BAD-SPR',
        'customer_id', v_cust2_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_SPARE',
        'total_amount', '10',
        'related_spare_part_request_id', v_spr_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 404 THEN
        RAISE EXCEPTION 'Cross-customer spare should be 404: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 7) Customer cannot create or update
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_cust1_hash,
        'invoice_no', 'M81-INV-CUST',
        'customer_id', v_cust1_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_INSTALL',
        'total_amount', '10'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 403 THEN
        RAISE EXCEPTION 'Customer create should be 403: %', v_resp;
    END IF;

    v_resp := solar_app.fn_update_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices/update',
        'jwt_token_hash', v_cust1_hash,
        'invoice_id', v_inv1_id::TEXT,
        'remarks', 'hack'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 403 THEN
        RAISE EXCEPTION 'Customer update should be 403: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 8) Customer sees only own; admin across customers; empty history
    ------------------------------------------------------------------
    v_resp := solar_app.fn_get_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/invoices',
        'jwt_token_hash', v_cust1_hash
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Customer1 list failed: %', v_resp;
    END IF;
    v_list_len := jsonb_array_length(v_resp->'data'->'invoices');
    IF v_list_len <> 2 THEN
        RAISE EXCEPTION 'Customer1 should see 2 invoices, got %: %', v_list_len, v_resp;
    END IF;

    v_resp := solar_app.fn_get_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/invoices',
        'jwt_token_hash', v_cust1_hash,
        'customer_id', v_cust2_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 403 THEN
        RAISE EXCEPTION 'Customer1 viewing cust2 should be 403: %', v_resp;
    END IF;

    v_resp := solar_app.fn_get_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Admin list failed: %', v_resp;
    END IF;
    IF jsonb_array_length(v_resp->'data'->'invoices') < 3 THEN
        RAISE EXCEPTION 'Admin should see invoices across customers: %', v_resp;
    END IF;

    v_resp := solar_app.fn_get_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/invoices',
        'jwt_token_hash', v_cust3_hash
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR jsonb_array_length(v_resp->'data'->'invoices') <> 0 THEN
        RAISE EXCEPTION 'Empty customer history expected: %', v_resp;
    END IF;

    v_resp := solar_app.fn_get_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/invoices',
        'jwt_token_hash', v_cust2_hash,
        'invoice_id', v_inv3_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR jsonb_array_length(v_resp->'data'->'invoice'->'tax_snapshots') <> 2 THEN
        RAISE EXCEPTION 'Detail with tax snapshots failed: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 9) Invalid child row rolls back whole create
    ------------------------------------------------------------------
    SELECT COUNT(*) INTO v_before_count FROM solar_app.invoice_details WHERE invoice_no = 'M81-INV-BAD-CHILD';
    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M81-INV-BAD-CHILD',
        'customer_id', v_cust1_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_INSTALL',
        'taxable_amount', '100',
        'tax_amount', '18',
        'total_amount', '118',
        'lines', jsonb_build_array(
            jsonb_build_object('line_no', 1, 'line_desc', 'Ok', 'line_amount', '100')
        ),
        'tax_snapshots', jsonb_build_array(
            jsonb_build_object(
                'tax_group_code', 'GST',
                'tax_component_code', 'CGST',
                'tax_display_name', 'CGST',
                'calculation_method', 'PERCENTAGE',
                'rate_percent', '9',
                'taxable_amount', '100',
                'tax_amount', '10'
            )
        )
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' THEN
        RAISE EXCEPTION 'Mismatched tax sum should fail: %', v_resp;
    END IF;
    SELECT COUNT(*) INTO v_after_count FROM solar_app.invoice_details WHERE invoice_no = 'M81-INV-BAD-CHILD';
    IF v_after_count IS DISTINCT FROM v_before_count THEN
        RAISE EXCEPTION 'Invalid child did not roll back invoice header';
    END IF;

    ------------------------------------------------------------------
    -- 10) Notification failure rolls back
    ------------------------------------------------------------------
    SELECT COUNT(*) INTO v_before_count FROM solar_app.invoice_details WHERE invoice_no = 'M81-INV-NTF-FAIL';
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

    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M81-INV-NTF-FAIL',
        'customer_id', v_cust1_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_INSTALL',
        'total_amount', '25'
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
    SELECT COUNT(*) INTO v_after_count FROM solar_app.invoice_details WHERE invoice_no = 'M81-INV-NTF-FAIL';
    IF v_after_count IS DISTINCT FROM v_before_count THEN
        RAISE EXCEPTION 'Notification failure did not roll back invoice';
    END IF;

    ------------------------------------------------------------------
    -- 11) Preserve existing invoice/payment data on update guards
    ------------------------------------------------------------------
    INSERT INTO solar_app.invoice_details (
        invoice_no, customer_id, invoice_category_ref_data_id, invoice_status_ref_data_id,
        invoice_date, currency_code, taxable_amount, tax_amount, total_amount,
        paid_amount, balance_amount, created_by, updated_by
    )
    SELECT 'M81-INV-PRESERVE', v_cust1_id, cat.ref_data_id, st.ref_data_id,
           CURRENT_DATE, v_currency, 200, 0, 200, 50, 150, 'M81_IT', 'M81_IT'
      FROM solar_app.ref_data cat
      JOIN solar_app.ref_data_categories cc ON cc.category_id = cat.category_id AND cc.category_code = 'INVOICE_CATEGORIES'
      JOIN solar_app.ref_data st ON TRUE
      JOIN solar_app.ref_data_categories sc ON sc.category_id = st.category_id AND sc.category_code = 'INVOICE_STATUSES'
     WHERE cat.data_code = 'INV_INSTALL' AND st.data_code = 'INV_PARTIAL'
     LIMIT 1
    RETURNING invoice_id INTO v_preserve_id;

    INSERT INTO solar_app.payment_details (
        invoice_id, customer_id, amount, currency_code,
        payment_method_ref_data_id, payment_status_ref_data_id,
        is_offline_ind, paid_on, created_by, updated_by
    ) VALUES (
        v_preserve_id, v_cust1_id, 50, v_currency,
        v_pay_method, v_pay_status, TRUE, CURRENT_DATE, 'M81_IT', 'M81_IT'
    );

    SELECT paid_amount, balance_amount, invoice_status_ref_data_id
      INTO v_paid_before, v_bal_before, v_status_before
      FROM solar_app.invoice_details WHERE invoice_id = v_preserve_id;

    v_resp := solar_app.fn_update_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices/update',
        'jwt_token_hash', v_admin_hash,
        'invoice_id', v_preserve_id::TEXT,
        'remarks', 'updated note',
        'paid_amount', '0',
        'balance_amount', '0',
        'invoice_status_code', 'INV_PAID',
        'total_amount', '10',
        'customer_id', v_cust2_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' THEN
        RAISE EXCEPTION 'Payment relationship conflicts should reject: %', v_resp;
    END IF;

    IF EXISTS (
        SELECT 1 FROM solar_app.invoice_details
         WHERE invoice_id = v_preserve_id
           AND (paid_amount IS DISTINCT FROM v_paid_before
                OR balance_amount IS DISTINCT FROM v_bal_before
                OR invoice_status_ref_data_id IS DISTINCT FROM v_status_before
                OR customer_id IS DISTINCT FROM v_cust1_id
                OR remarks IS DISTINCT FROM NULL)
    ) THEN
        RAISE EXCEPTION 'Existing invoice/payment data was mutated on rejected update';
    END IF;

    v_resp := solar_app.fn_update_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices/update',
        'jwt_token_hash', v_admin_hash,
        'invoice_id', v_preserve_id::TEXT,
        'remarks', 'safe update',
        'paid_amount', '999',
        'balance_amount', '0',
        'invoice_status_code', 'INV_UNPAID',
        'total_amount', '250'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Safe update with payments present failed: %', v_resp;
    END IF;
    IF (v_resp->'data'->>'paid_amount')::NUMERIC <> 50
       OR (v_resp->'data'->>'balance_amount')::NUMERIC <> 200
       OR v_resp->'data'->>'invoice_status_code' <> 'INV_PARTIAL' THEN
        RAISE EXCEPTION 'Update should keep paid=50, balance=200, status INV_PARTIAL: %', v_resp;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM solar_app.payment_details
         WHERE invoice_id = v_preserve_id AND amount = 50 AND active_ind
    ) THEN
        RAISE EXCEPTION 'Payment row was not preserved';
    END IF;

    SELECT COUNT(*) INTO v_ntf_count
      FROM solar_app.notification_details n
      JOIN solar_app.ref_data t ON t.ref_data_id = n.notification_type_ref_data_id
     WHERE n.related_entity_id = v_preserve_id
       AND t.data_code = 'NTF_BILLING_UPDATE'
       AND n.active_ind;
    IF v_ntf_count < 1 THEN
        RAISE EXCEPTION 'NTF_BILLING_UPDATE not enqueued on update';
    END IF;

    ------------------------------------------------------------------
    -- 12) Draft invoice, customer visibility, currency lock
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices',
        'jwt_token_hash', v_admin_hash,
        'invoice_no', 'M81-INV-DRAFT',
        'customer_id', v_cust1_id::TEXT,
        'invoice_date', CURRENT_DATE::TEXT,
        'currency_code', v_currency,
        'invoice_category_code', 'INV_INSTALL',
        'total_amount', '75.00',
        'invoice_status_code', 'INV_DRAFT'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR v_resp->'data'->>'invoice_status_code' <> 'INV_DRAFT' THEN
        RAISE EXCEPTION 'Draft create failed: %', v_resp;
    END IF;
    v_draft_id := (v_resp->'data'->>'invoice_id')::BIGINT;

    v_resp := solar_app.fn_get_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/invoices',
        'jwt_token_hash', v_cust1_hash
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Customer list after draft failed: %', v_resp;
    END IF;
    IF EXISTS (
        SELECT 1
          FROM jsonb_array_elements(v_resp->'data'->'invoices') AS inv
         WHERE inv->>'invoice_id' = v_draft_id::TEXT
            OR inv->>'invoice_status_code' IN ('INV_DRAFT', 'INV_CANCELLED')
    ) THEN
        RAISE EXCEPTION 'Customer list must exclude draft/cancelled invoices: %', v_resp;
    END IF;

    v_resp := solar_app.fn_get_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/invoices',
        'jwt_token_hash', v_cust1_hash,
        'invoice_id', v_draft_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 404 THEN
        RAISE EXCEPTION 'Customer draft detail should be 404: %', v_resp;
    END IF;

    INSERT INTO solar_app.ref_currencies (currency_code, currency_name, decimal_places, created_by, updated_by)
    VALUES ('XTS', 'M81 Test Currency', 2, 'M81_IT', 'M81_IT')
    ON CONFLICT (currency_code) DO UPDATE
       SET active_ind = TRUE,
           updated_by = 'M81_IT',
           updated_on = CURRENT_TIMESTAMP;

    v_resp := solar_app.fn_update_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices/update',
        'jwt_token_hash', v_admin_hash,
        'invoice_id', v_preserve_id::TEXT,
        'currency_code', 'XTS'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 409 THEN
        RAISE EXCEPTION 'Currency change with payment history should be 409: %', v_resp;
    END IF;

    -- Total raised to equal paid must sync to INV_PAID
    v_resp := solar_app.fn_update_invoice_details(jsonb_build_object(
        'api_endpoint', '/api/admin/invoices/update',
        'jwt_token_hash', v_admin_hash,
        'invoice_id', v_preserve_id::TEXT,
        'total_amount', '50.00'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS'
       OR v_resp->'data'->>'invoice_status_code' <> 'INV_PAID'
       OR (v_resp->'data'->>'balance_amount')::NUMERIC <> 0 THEN
        RAISE EXCEPTION 'Total equal to paid should sync INV_PAID: %', v_resp;
    END IF;

    RAISE NOTICE 'M8.1 invoice register restore_check IT passed';
END $$;
