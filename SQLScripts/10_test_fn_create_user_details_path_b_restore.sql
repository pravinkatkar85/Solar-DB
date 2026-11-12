-- Isolated Path B integration tests for SolarDB_restore_check only.
-- Do not run against SolarDB.
-- Creates PATHB_IT fixtures, asserts outcomes, then cleans them up.

\set ON_ERROR_STOP on

SELECT current_database() AS db, current_user AS usr;
SELECT CASE
         WHEN current_database() = 'SolarDB_restore_check' THEN 'OK'
         ELSE 'REFUSING: not SolarDB_restore_check'
       END AS target_guard;
\if :{?target_guard}
\endif

DO $$
DECLARE
    v_db TEXT := current_database();
BEGIN
    IF v_db IS DISTINCT FROM 'SolarDB_restore_check' THEN
        RAISE EXCEPTION 'Refuse to run Path B IT on database %', v_db;
    END IF;
END $$;

BEGIN;

-- Cleanup any prior PATHB_IT leftovers
DELETE FROM solar_app.notification_details
 WHERE recipient_user_id IN (
        SELECT user_id FROM solar_app.user_details
         WHERE mobile_e164 LIKE '+91990011%'
            OR created_by = 'PATHB_IT'
      );
DELETE FROM solar_app.order_line_details
 WHERE order_id IN (
        SELECT order_id FROM solar_app.order_details
         WHERE order_no LIKE 'PATHB-ORD-%' OR created_by = 'PATHB_IT'
      );
DELETE FROM solar_app.order_details
 WHERE order_no LIKE 'PATHB-ORD-%' OR created_by = 'PATHB_IT';
DELETE FROM solar_app.equipment_details
 WHERE created_by = 'PATHB_IT'
    OR site_id IN (SELECT site_id FROM solar_app.site_details WHERE created_by = 'PATHB_IT');
DELETE FROM solar_app.user_site_access_details
 WHERE created_by = 'PATHB_IT'
    OR user_id IN (SELECT user_id FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990011%' OR created_by = 'PATHB_IT');
DELETE FROM solar_app.site_details
 WHERE created_by = 'PATHB_IT'
    OR customer_id IN (SELECT customer_id FROM solar_app.customer_details WHERE customer_code LIKE 'PATHB-CUST-%');
DELETE FROM solar_app.customer_details
 WHERE customer_code LIKE 'PATHB-CUST-%' OR created_by = 'PATHB_IT';
DELETE FROM solar_app.log_user_sessions
 WHERE jwt_token_hash LIKE 'aa11bb22%' OR created_by = 'PATHB_IT';
DELETE FROM solar_app.user_details
 WHERE mobile_e164 LIKE '+91990011%' OR created_by = 'PATHB_IT';

COMMIT;

DO $$
DECLARE
    v_role_admin BIGINT;
    v_role_customer BIGINT;
    v_acct_active BIGINT;
    v_reg_self BIGINT;
    v_admin_id BIGINT;
    v_customer_actor_id BIGINT;
    v_admin_hash TEXT := 'aa11bb22cc33dd44ee55ff6677889900aaaabbbbccccddddeeeeffff00001111';
    v_customer_hash TEXT := 'aa11bb22cc33dd44ee55ff6677889900aaaabbbbccccddddeeeeffff00002222';
    v_country_id BIGINT := 1;
    v_pincode_id BIGINT;
    v_product_id BIGINT;
    v_payload JSONB;
    v_resp JSONB;
    v_user_id BIGINT;
    v_customer_id BIGINT;
    v_order_id BIGINT;
    v_site_count INTEGER;
    v_eq_count INTEGER;
    v_access_count INTEGER;
    v_default_count INTEGER;
    v_ntf_count INTEGER;
    v_pin_hash TEXT;
    v_admin_registered BOOLEAN;
    v_role_code TEXT;
    v_acct_code TEXT;
    v_source_code TEXT;
    v_order_source TEXT;
    v_order_status TEXT;
    v_sites_with_order INTEGER;
    v_before_users INTEGER;
    v_after_users INTEGER;
    v_fail_msg TEXT;
BEGIN
    SELECT ref_data_id INTO v_role_admin
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'USER_ROLES' AND r.data_code = 'ROLE_ADMIN' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_role_customer
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'USER_ROLES' AND r.data_code = 'ROLE_CUSTOMER' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_acct_active
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'USER_ACCOUNT_STATUSES' AND r.data_code = 'ACCT_ACTIVE' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_reg_self
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'REGISTRATION_SOURCES' AND r.data_code = 'REG_SELF_APP' AND r.active_ind AND c.active_ind;
    SELECT pincode_id INTO v_pincode_id FROM solar_app.ref_pincodes WHERE active_ind IS TRUE ORDER BY pincode_id LIMIT 1;
    SELECT product_id INTO v_product_id FROM solar_app.product_details WHERE active_ind IS TRUE ORDER BY product_id LIMIT 1;

    IF v_role_admin IS NULL OR v_role_customer IS NULL OR v_acct_active IS NULL OR v_reg_self IS NULL THEN
        RAISE EXCEPTION 'Missing required role/account/source reference data';
    END IF;
    IF v_pincode_id IS NULL THEN
        RAISE EXCEPTION 'Missing active pincode fixture';
    END IF;

    INSERT INTO solar_app.user_details (
        country_id, mobile_e164, full_name, role_ref_data_id, pin_hash,
        admin_registered, account_status_ref_data_id, registration_source_ref_data_id,
        created_by, updated_by
    ) VALUES (
        v_country_id, '+919900110001', 'PATHB IT Admin', v_role_admin, NULL,
        TRUE, v_acct_active, v_reg_self, 'PATHB_IT', 'PATHB_IT'
    ) RETURNING user_id INTO v_admin_id;

    INSERT INTO solar_app.user_details (
        country_id, mobile_e164, full_name, role_ref_data_id, pin_hash,
        admin_registered, account_status_ref_data_id, registration_source_ref_data_id,
        created_by, updated_by
    ) VALUES (
        v_country_id, '+919900110002', 'PATHB IT Customer Actor', v_role_customer, NULL,
        TRUE, v_acct_active, v_reg_self, 'PATHB_IT', 'PATHB_IT'
    ) RETURNING user_id INTO v_customer_actor_id;

    INSERT INTO solar_app.log_user_sessions (
        user_id, mobile_e164, jwt_token_hash, session_status, active_ind, created_by, updated_by
    ) VALUES
        (v_admin_id, '+919900110001', v_admin_hash, 'ACTIVE', TRUE, 'PATHB_IT', 'PATHB_IT'),
        (v_customer_actor_id, '+919900110002', v_customer_hash, 'ACTIVE', TRUE, 'PATHB_IT', 'PATHB_IT');

    ------------------------------------------------------------------
    -- 1) Happy path: multi-site + equipment + order + notification
    ------------------------------------------------------------------
    v_payload := jsonb_build_object(
        'api_endpoint', '/api/admin/customers/create',
        'jwt_token_hash', v_admin_hash,
        'logged_in_user_id', v_admin_id::TEXT,
        'role', 'ROLE_CUSTOMER',
        'customer_id', '999999',
        'country_id', v_country_id::TEXT,
        'national_number', '9900110003',
        'full_name', 'PATHB IT Registered Customer',
        'customer_code', 'PATHB-CUST-0001',
        'billing_name', 'PATHB Billing',
        'order_no', 'PATHB-ORD-0001',
        'order_status_code', 'ORD_COMMISSIONED',
        'currency_code', 'INR',
        'gross_amount', '0',
        'sites', jsonb_build_array(
            jsonb_build_object(
                'site_name', 'PATHB Home',
                'address_line1', '1 Test Lane',
                'pincode_id', v_pincode_id::TEXT,
                'installation_status_code', 'INST_COMMISSIONED',
                'commissioning_on', '2026-01-15',
                'is_default', true,
                'equipment', jsonb_build_array(
                    jsonb_build_object(
                        'equipment_type_code', 'EQ_PANEL',
                        'model_name', 'Panel A',
                        'quantity', '8',
                        'panel_wattage', '540',
                        'product_id', CASE WHEN v_product_id IS NULL THEN NULL ELSE v_product_id::TEXT END
                    ),
                    jsonb_build_object(
                        'equipment_type_code', 'EQ_INVERTER',
                        'model_name', 'Inverter A',
                        'quantity', '1',
                        'inverter_capacity_kw', '5'
                    )
                )
            ),
            jsonb_build_object(
                'site_name', 'PATHB Farm',
                'address_line1', '2 Farm Road',
                'pincode_id', v_pincode_id::TEXT,
                'installation_status_code', 'INST_INSTALLED',
                'commissioning_on', '2026-01-20',
                'equipment', jsonb_build_array(
                    jsonb_build_object(
                        'equipment_type_code', 'EQ_PANEL',
                        'model_name', 'Panel B',
                        'quantity', '4'
                    )
                )
            )
        ),
        'order_lines', jsonb_build_array(
            jsonb_build_object(
                'line_no', '1',
                'line_desc', 'Path B kit',
                'quantity', '1',
                'unit_rate', '0',
                'line_amount', '0'
            )
        )
    );

    v_resp := solar_app.fn_create_user_details(v_payload);
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' OR (v_resp->>'code')::INT <> 200 THEN
        RAISE EXCEPTION 'Happy path failed: %', v_resp;
    END IF;

    v_user_id := (v_resp->'data'->>'user_id')::BIGINT;
    v_customer_id := (v_resp->'data'->>'customer_id')::BIGINT;
    v_order_id := (v_resp->'data'->>'order_id')::BIGINT;

    SELECT pin_hash, admin_registered
      INTO v_pin_hash, v_admin_registered
      FROM solar_app.user_details WHERE user_id = v_user_id;
    SELECT role.data_code, acct.data_code, src.data_code
      INTO v_role_code, v_acct_code, v_source_code
      FROM solar_app.user_details u
      JOIN solar_app.ref_data role ON role.ref_data_id = u.role_ref_data_id
      JOIN solar_app.ref_data acct ON acct.ref_data_id = u.account_status_ref_data_id
      JOIN solar_app.ref_data src ON src.ref_data_id = u.registration_source_ref_data_id
     WHERE u.user_id = v_user_id;

    IF v_pin_hash IS NOT NULL THEN
        RAISE EXCEPTION 'PIN hash must be NULL, got %', v_pin_hash;
    END IF;
    IF v_admin_registered IS NOT TRUE THEN
        RAISE EXCEPTION 'admin_registered must be TRUE';
    END IF;
    IF v_role_code <> 'ROLE_CUSTOMER' OR v_acct_code <> 'ACCT_ACTIVE' OR v_source_code <> 'REG_ADMIN_POST_INSTALL' THEN
        RAISE EXCEPTION 'Unexpected user flags % / % / %', v_role_code, v_acct_code, v_source_code;
    END IF;

    SELECT COUNT(*) INTO v_site_count FROM solar_app.site_details WHERE customer_id = v_customer_id AND active_ind;
    SELECT COUNT(*) INTO v_eq_count
      FROM solar_app.equipment_details e
      JOIN solar_app.site_details s ON s.site_id = e.site_id
     WHERE s.customer_id = v_customer_id AND e.active_ind;
    SELECT COUNT(*) INTO v_access_count
      FROM solar_app.user_site_access_details WHERE user_id = v_user_id AND active_ind;
    SELECT COUNT(*) INTO v_default_count
      FROM solar_app.user_site_access_details WHERE user_id = v_user_id AND is_default IS TRUE AND active_ind;
    SELECT order_source, st.data_code
      INTO v_order_source, v_order_status
      FROM solar_app.order_details o
      JOIN solar_app.ref_data st ON st.ref_data_id = o.order_status_ref_data_id
     WHERE o.order_id = v_order_id;
    SELECT COUNT(*) INTO v_sites_with_order
      FROM solar_app.site_details WHERE customer_id = v_customer_id AND order_id = v_order_id;
    SELECT COUNT(*) INTO v_ntf_count
      FROM solar_app.notification_details n
      JOIN solar_app.ref_data t ON t.ref_data_id = n.notification_type_ref_data_id
     WHERE n.recipient_user_id = v_user_id AND t.data_code = 'NTF_ACCOUNT_READY' AND n.active_ind;

    IF v_site_count <> 2 THEN RAISE EXCEPTION 'Expected 2 sites, got %', v_site_count; END IF;
    IF v_eq_count <> 3 THEN RAISE EXCEPTION 'Expected 3 equipment rows, got %', v_eq_count; END IF;
    IF v_access_count <> 2 OR v_default_count <> 1 THEN
        RAISE EXCEPTION 'Access mapping failed sites=% defaults=%', v_access_count, v_default_count;
    END IF;
    IF v_order_source <> 'MANUAL' OR v_order_status <> 'ORD_COMMISSIONED' THEN
        RAISE EXCEPTION 'Order flags failed % / %', v_order_source, v_order_status;
    END IF;
    IF v_sites_with_order <> 2 THEN
        RAISE EXCEPTION 'Expected both sites linked to order, got %', v_sites_with_order;
    END IF;
    IF v_ntf_count <> 1 THEN
        RAISE EXCEPTION 'Expected one NTF_ACCOUNT_READY, got %', v_ntf_count;
    END IF;
    RAISE NOTICE 'PASS happy path multi-site registration';

    ------------------------------------------------------------------
    -- 2) Non-admin rejection
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_user_details(jsonb_build_object(
        'api_endpoint', '/api/admin/customers/create',
        'jwt_token_hash', v_customer_hash,
        'country_id', v_country_id::TEXT,
        'national_number', '9900110099',
        'full_name', 'Should Fail',
        'customer_code', 'PATHB-CUST-NOADMIN',
        'order_no', 'PATHB-ORD-NOADMIN',
        'order_status_code', 'ORD_INSTALLED',
        'currency_code', 'INR',
        'sites', jsonb_build_array(jsonb_build_object(
            'site_name', 'X',
            'address_line1', 'Y',
            'installation_status_code', 'INST_INSTALLED',
            'commissioning_on', '2026-01-01',
            'equipment', jsonb_build_array(jsonb_build_object('equipment_type_code', 'EQ_PANEL'))
        ))
    ));
    IF (v_resp->>'code')::INT <> 403 THEN
        RAISE EXCEPTION 'Non-admin expected 403, got %', v_resp;
    END IF;
    RAISE NOTICE 'PASS non-admin rejection';

    ------------------------------------------------------------------
    -- 3) Forbidden PIN
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_user_details(jsonb_build_object(
        'api_endpoint', '/api/admin/customers/create',
        'jwt_token_hash', v_admin_hash,
        'country_id', v_country_id::TEXT,
        'national_number', '9900110098',
        'full_name', 'PIN Fail',
        'customer_code', 'PATHB-CUST-PIN',
        'order_no', 'PATHB-ORD-PIN',
        'order_status_code', 'ORD_INSTALLED',
        'currency_code', 'INR',
        'pin', '1234',
        'sites', jsonb_build_array(jsonb_build_object(
            'site_name', 'X',
            'address_line1', 'Y',
            'installation_status_code', 'INST_INSTALLED',
            'commissioning_on', '2026-01-01',
            'equipment', jsonb_build_array(jsonb_build_object('equipment_type_code', 'EQ_PANEL'))
        ))
    ));
    IF (v_resp->>'code')::INT <> 400 OR position('PIN' in coalesce(v_resp->>'message','')) = 0 THEN
        RAISE EXCEPTION 'PIN reject expected 400, got %', v_resp;
    END IF;
    RAISE NOTICE 'PASS forbidden PIN rejection';

    ------------------------------------------------------------------
    -- 4) Missing required fields
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_user_details(jsonb_build_object(
        'api_endpoint', '/api/admin/customers/create',
        'jwt_token_hash', v_admin_hash,
        'country_id', v_country_id::TEXT,
        'national_number', '9900110097',
        'full_name', 'Missing Sites',
        'customer_code', 'PATHB-CUST-MISS',
        'order_no', 'PATHB-ORD-MISS',
        'order_status_code', 'ORD_INSTALLED',
        'currency_code', 'INR'
    ));
    IF (v_resp->>'code')::INT <> 400 THEN
        RAISE EXCEPTION 'Missing sites expected 400, got %', v_resp;
    END IF;
    RAISE NOTICE 'PASS missing required fields';

    ------------------------------------------------------------------
    -- 5) Invalid references / status codes
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_user_details(jsonb_build_object(
        'api_endpoint', '/api/admin/customers/create',
        'jwt_token_hash', v_admin_hash,
        'country_id', v_country_id::TEXT,
        'national_number', '9900110096',
        'full_name', 'Bad Status',
        'customer_code', 'PATHB-CUST-BADST',
        'order_no', 'PATHB-ORD-BADST',
        'order_status_code', 'ORD_DRAFT',
        'currency_code', 'INR',
        'sites', jsonb_build_array(jsonb_build_object(
            'site_name', 'X',
            'address_line1', 'Y',
            'installation_status_code', 'INST_INSTALLED',
            'commissioning_on', '2026-01-01',
            'equipment', jsonb_build_array(jsonb_build_object('equipment_type_code', 'EQ_PANEL'))
        ))
    ));
    IF (v_resp->>'code')::INT <> 400 THEN
        RAISE EXCEPTION 'Invalid order status expected 400, got %', v_resp;
    END IF;
    RAISE NOTICE 'PASS invalid status code rejection';

    ------------------------------------------------------------------
    -- 6) Duplicate mobile / customer_code / order_no
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_user_details(jsonb_build_object(
        'api_endpoint', '/api/admin/customers/create',
        'jwt_token_hash', v_admin_hash,
        'country_id', v_country_id::TEXT,
        'national_number', '9900110003',
        'full_name', 'Dup Mobile',
        'customer_code', 'PATHB-CUST-DUPM',
        'order_no', 'PATHB-ORD-DUPM',
        'order_status_code', 'ORD_INSTALLED',
        'currency_code', 'INR',
        'sites', jsonb_build_array(jsonb_build_object(
            'site_name', 'X',
            'address_line1', 'Y',
            'installation_status_code', 'INST_INSTALLED',
            'commissioning_on', '2026-01-01',
            'equipment', jsonb_build_array(jsonb_build_object('equipment_type_code', 'EQ_PANEL'))
        ))
    ));
    IF (v_resp->>'code')::INT <> 409 THEN
        RAISE EXCEPTION 'Duplicate mobile expected 409, got %', v_resp;
    END IF;

    v_resp := solar_app.fn_create_user_details(jsonb_build_object(
        'api_endpoint', '/api/admin/customers/create',
        'jwt_token_hash', v_admin_hash,
        'country_id', v_country_id::TEXT,
        'national_number', '9900110004',
        'full_name', 'Dup Code',
        'customer_code', 'PATHB-CUST-0001',
        'order_no', 'PATHB-ORD-DUPC',
        'order_status_code', 'ORD_INSTALLED',
        'currency_code', 'INR',
        'sites', jsonb_build_array(jsonb_build_object(
            'site_name', 'X',
            'address_line1', 'Y',
            'installation_status_code', 'INST_INSTALLED',
            'commissioning_on', '2026-01-01',
            'equipment', jsonb_build_array(jsonb_build_object('equipment_type_code', 'EQ_PANEL'))
        ))
    ));
    IF (v_resp->>'code')::INT <> 409 THEN
        RAISE EXCEPTION 'Duplicate customer_code expected 409, got %', v_resp;
    END IF;

    v_resp := solar_app.fn_create_user_details(jsonb_build_object(
        'api_endpoint', '/api/admin/customers/create',
        'jwt_token_hash', v_admin_hash,
        'country_id', v_country_id::TEXT,
        'national_number', '9900110005',
        'full_name', 'Dup Order',
        'customer_code', 'PATHB-CUST-0005',
        'order_no', 'PATHB-ORD-0001',
        'order_status_code', 'ORD_INSTALLED',
        'currency_code', 'INR',
        'sites', jsonb_build_array(jsonb_build_object(
            'site_name', 'X',
            'address_line1', 'Y',
            'installation_status_code', 'INST_INSTALLED',
            'commissioning_on', '2026-01-01',
            'equipment', jsonb_build_array(jsonb_build_object('equipment_type_code', 'EQ_PANEL'))
        ))
    ));
    IF (v_resp->>'code')::INT <> 409 THEN
        RAISE EXCEPTION 'Duplicate order_no expected 409, got %', v_resp;
    END IF;
    RAISE NOTICE 'PASS duplicate mobile/customer_code/order_no';

    ------------------------------------------------------------------
    -- 7) Rollback on mid-flight failure (invalid equipment type)
    ------------------------------------------------------------------
    SELECT COUNT(*) INTO v_before_users FROM solar_app.user_details WHERE mobile_e164 = '+919900110077';
    v_resp := solar_app.fn_create_user_details(jsonb_build_object(
        'api_endpoint', '/api/admin/customers/create',
        'jwt_token_hash', v_admin_hash,
        'country_id', v_country_id::TEXT,
        'national_number', '9900110077',
        'full_name', 'Rollback Customer',
        'customer_code', 'PATHB-CUST-ROLL',
        'order_no', 'PATHB-ORD-ROLL',
        'order_status_code', 'ORD_INSTALLED',
        'currency_code', 'INR',
        'sites', jsonb_build_array(jsonb_build_object(
            'site_name', 'Rollback Site',
            'address_line1', 'Y',
            'installation_status_code', 'INST_INSTALLED',
            'commissioning_on', '2026-01-01',
            'equipment', jsonb_build_array(jsonb_build_object('equipment_type_code', 'EQ_NOT_A_REAL_TYPE'))
        ))
    ));
    IF (v_resp->>'code')::INT NOT IN (400, 500) THEN
        RAISE EXCEPTION 'Rollback case expected failure, got %', v_resp;
    END IF;
    SELECT COUNT(*) INTO v_after_users FROM solar_app.user_details WHERE mobile_e164 = '+919900110077';
    IF v_after_users <> v_before_users THEN
        RAISE EXCEPTION 'Rollback failed: user row leaked for +919900110077';
    END IF;
    IF EXISTS (SELECT 1 FROM solar_app.customer_details WHERE customer_code = 'PATHB-CUST-ROLL') THEN
        RAISE EXCEPTION 'Rollback failed: customer_code leaked';
    END IF;
    IF EXISTS (SELECT 1 FROM solar_app.order_details WHERE order_no = 'PATHB-ORD-ROLL') THEN
        RAISE EXCEPTION 'Rollback failed: order_no leaked';
    END IF;
    RAISE NOTICE 'PASS full transaction rollback on failure';

    ------------------------------------------------------------------
    -- 8) Client ownership/role cannot override server-fixed values
    ------------------------------------------------------------------
    -- Already proven in happy path via ROLE_CUSTOMER / REG_ADMIN_POST_INSTALL despite payload role/customer_id.
    IF EXISTS (
        SELECT 1 FROM solar_app.user_details
         WHERE user_id = v_user_id AND role_ref_data_id = v_role_admin
    ) THEN
        RAISE EXCEPTION 'Client role override occurred';
    END IF;
    RAISE NOTICE 'PASS client role/ownership ignored';

    RAISE NOTICE 'ALL PATH B INTEGRATION CHECKS PASSED';
END $$;

-- Cleanup fixtures and created Path B rows
BEGIN;
DELETE FROM solar_app.notification_details
 WHERE recipient_user_id IN (
        SELECT user_id FROM solar_app.user_details
         WHERE mobile_e164 LIKE '+91990011%' OR created_by = 'PATHB_IT'
      );
DELETE FROM solar_app.order_line_details
 WHERE order_id IN (
        SELECT order_id FROM solar_app.order_details
         WHERE order_no LIKE 'PATHB-ORD-%' OR created_by = 'PATHB_IT'
      );
DELETE FROM solar_app.order_details
 WHERE order_no LIKE 'PATHB-ORD-%' OR created_by = 'PATHB_IT';
DELETE FROM solar_app.equipment_details
 WHERE created_by = 'PATHB_IT'
    OR site_id IN (SELECT site_id FROM solar_app.site_details WHERE created_by = 'PATHB_IT' OR site_name LIKE 'PATHB %' OR site_name LIKE 'PATHB%');
DELETE FROM solar_app.user_site_access_details
 WHERE created_by = 'PATHB_IT'
    OR user_id IN (SELECT user_id FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990011%' OR created_by = 'PATHB_IT');
DELETE FROM solar_app.site_details
 WHERE created_by = 'PATHB_IT'
    OR site_name LIKE 'PATHB %'
    OR site_name LIKE 'PATHB%'
    OR customer_id IN (SELECT customer_id FROM solar_app.customer_details WHERE customer_code LIKE 'PATHB-CUST-%');
DELETE FROM solar_app.customer_details
 WHERE customer_code LIKE 'PATHB-CUST-%' OR created_by = 'PATHB_IT';
DELETE FROM solar_app.log_user_sessions
 WHERE jwt_token_hash LIKE 'aa11bb22%' OR created_by = 'PATHB_IT';
DELETE FROM solar_app.user_details
 WHERE mobile_e164 LIKE '+91990011%' OR created_by = 'PATHB_IT';
COMMIT;

SELECT 'PATHB_IT_CLEAN' AS cleanup_status;
