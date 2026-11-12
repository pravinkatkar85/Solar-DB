-- Controlled Path B live validation on SolarDB only.
-- Creates uniquely tagged PATHB_LIVE fixtures, asserts required outcomes,
-- then deletes only those fixtures. Do not reuse on restore_check.

\set ON_ERROR_STOP on

SELECT current_database() AS db, current_user AS usr;

DO $$
BEGIN
    IF current_database() IS DISTINCT FROM 'SolarDB' THEN
        RAISE EXCEPTION 'Refuse to run SolarDB Path B live validation on database %',
            current_database();
    END IF;
END $$;

-- Snapshot existing production-like records that must remain untouched.
CREATE TEMP TABLE pathb_live_baseline AS
SELECT 'user'::text AS kind, user_id::text AS id, mobile_e164 AS marker
  FROM solar_app.user_details
 WHERE mobile_e164 = '+919960841282'
UNION ALL
SELECT 'customer', customer_id::text, customer_code
  FROM solar_app.customer_details
 WHERE customer_code = 'CUST-00000007'
UNION ALL
SELECT 'site', site_id::text, site_name
  FROM solar_app.site_details
 WHERE site_id IN (1, 2);

DO $$
DECLARE
    v_role_admin BIGINT;
    v_role_customer BIGINT;
    v_acct_active BIGINT;
    v_reg_self BIGINT;
    v_admin_id BIGINT;
    v_customer_actor_id BIGINT;
    v_admin_hash TEXT := 'bb22cc33dd44ee55ff6677889900aaaabbbbccccddddeeeeffff000011112222';
    v_customer_hash TEXT := 'bb22cc33dd44ee55ff6677889900aaaabbbbccccddddeeeeffff000022223333';
    v_country_id BIGINT := 1;
    v_pincode_id BIGINT;
    v_payload JSONB;
    v_resp JSONB;
    v_user_id BIGINT;
    v_customer_id BIGINT;
    v_order_id BIGINT;
    v_site_id BIGINT;
    v_eq_id BIGINT;
    v_ntf_id BIGINT;
    v_pin_hash TEXT;
    v_admin_registered BOOLEAN;
    v_role_code TEXT;
    v_acct_code TEXT;
    v_source_code TEXT;
    v_order_source TEXT;
    v_order_status TEXT;
    v_access_code TEXT;
    v_ntf_type TEXT;
    v_before_users INTEGER;
    v_after_users INTEGER;
    v_fail_msg TEXT;
BEGIN
    SELECT ref_data_id INTO v_role_admin
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'USER_ROLES' AND r.data_code = 'ROLE_ADMIN'
       AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_role_customer
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'USER_ROLES' AND r.data_code = 'ROLE_CUSTOMER'
       AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_acct_active
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'USER_ACCOUNT_STATUSES' AND r.data_code = 'ACCT_ACTIVE'
       AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_reg_self
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'REGISTRATION_SOURCES' AND r.data_code = 'REG_SELF_APP'
       AND r.active_ind AND c.active_ind;
    SELECT pincode_id INTO v_pincode_id
      FROM solar_app.ref_pincodes WHERE active_ind IS TRUE ORDER BY pincode_id LIMIT 1;

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
        v_country_id, '+919988770001', 'PATHB_LIVE Admin', v_role_admin, NULL,
        TRUE, v_acct_active, v_reg_self, 'PATHB_LIVE', 'PATHB_LIVE'
    ) RETURNING user_id INTO v_admin_id;

    INSERT INTO solar_app.user_details (
        country_id, mobile_e164, full_name, role_ref_data_id, pin_hash,
        admin_registered, account_status_ref_data_id, registration_source_ref_data_id,
        created_by, updated_by
    ) VALUES (
        v_country_id, '+919988770002', 'PATHB_LIVE Customer Actor', v_role_customer, NULL,
        TRUE, v_acct_active, v_reg_self, 'PATHB_LIVE', 'PATHB_LIVE'
    ) RETURNING user_id INTO v_customer_actor_id;

    INSERT INTO solar_app.log_user_sessions (
        user_id, mobile_e164, jwt_token_hash, session_status, active_ind, created_by, updated_by
    ) VALUES
        (v_admin_id, '+919988770001', v_admin_hash, 'ACTIVE', TRUE, 'PATHB_LIVE', 'PATHB_LIVE'),
        (v_customer_actor_id, '+919988770002', v_customer_hash, 'ACTIVE', TRUE, 'PATHB_LIVE', 'PATHB_LIVE');

    ------------------------------------------------------------------
    -- 1) Happy path: one customer, one site, one equipment
    ------------------------------------------------------------------
    v_payload := jsonb_build_object(
        'api_endpoint', '/api/admin/customers/create',
        'jwt_token_hash', v_admin_hash,
        'country_id', v_country_id::TEXT,
        'national_number', '9988770003',
        'full_name', 'PATHB_LIVE Registered Customer',
        'customer_code', 'PATHB-LIVE-CUST-01',
        'order_no', 'PATHB-LIVE-ORD-01',
        'order_status_code', 'ORD_COMMISSIONED',
        'currency_code', 'INR',
        'sites', jsonb_build_array(
            jsonb_build_object(
                'site_name', 'PATHB_LIVE Home',
                'address_line1', '11 Live Lane',
                'pincode_id', v_pincode_id::TEXT,
                'installation_status_code', 'INST_COMMISSIONED',
                'commissioning_on', '2026-02-01',
                'is_default', true,
                'equipment', jsonb_build_array(
                    jsonb_build_object(
                        'equipment_type_code', 'EQ_PANEL',
                        'model_name', 'PATHB_LIVE Panel',
                        'quantity', '6'
                    )
                )
            )
        )
    );

    v_resp := solar_app.fn_create_user_details(v_payload);
    IF COALESCE(v_resp->>'status', '') <> 'SUCCESS' OR COALESCE((v_resp->>'code')::INT, 0) <> 200 THEN
        RAISE EXCEPTION 'Happy path failed: %', v_resp;
    END IF;

    v_user_id := (v_resp->'data'->>'user_id')::BIGINT;
    v_customer_id := (v_resp->'data'->>'customer_id')::BIGINT;
    v_order_id := (v_resp->'data'->>'order_id')::BIGINT;
    v_site_id := (v_resp->'data'->'site_ids'->>0)::BIGINT;
    v_eq_id := (v_resp->'data'->'equipment_ids'->>0)::BIGINT;
    v_ntf_id := (v_resp->'data'->>'notification_id')::BIGINT;

    IF v_user_id IS NULL OR v_customer_id IS NULL OR v_order_id IS NULL
       OR v_site_id IS NULL OR v_eq_id IS NULL OR v_ntf_id IS NULL THEN
        RAISE EXCEPTION 'Happy path response missing ids: %', v_resp->'data';
    END IF;

    SELECT pin_hash, admin_registered INTO v_pin_hash, v_admin_registered
      FROM solar_app.user_details WHERE user_id = v_user_id;
    IF v_pin_hash IS NOT NULL THEN
        RAISE EXCEPTION 'Expected pin_hash IS NULL';
    END IF;
    IF v_admin_registered IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'Expected admin_registered TRUE';
    END IF;

    SELECT role_row.data_code, acct_row.data_code, src_row.data_code
      INTO v_role_code, v_acct_code, v_source_code
      FROM solar_app.user_details u
      JOIN solar_app.ref_data role_row ON role_row.ref_data_id = u.role_ref_data_id
      JOIN solar_app.ref_data acct_row ON acct_row.ref_data_id = u.account_status_ref_data_id
      JOIN solar_app.ref_data src_row ON src_row.ref_data_id = u.registration_source_ref_data_id
     WHERE u.user_id = v_user_id;
    IF v_role_code <> 'ROLE_CUSTOMER' OR v_acct_code <> 'ACCT_ACTIVE'
       OR v_source_code <> 'REG_ADMIN_POST_INSTALL' THEN
        RAISE EXCEPTION 'Unexpected user codes role=% acct=% source=%',
            v_role_code, v_acct_code, v_source_code;
    END IF;

    SELECT o.order_source, status_row.data_code
      INTO v_order_source, v_order_status
      FROM solar_app.order_details o
      JOIN solar_app.ref_data status_row ON status_row.ref_data_id = o.order_status_ref_data_id
     WHERE o.order_id = v_order_id;
    IF v_order_source <> 'MANUAL' OR v_order_status <> 'ORD_COMMISSIONED' THEN
        RAISE EXCEPTION 'Unexpected order source/status: % / %', v_order_source, v_order_status;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM solar_app.site_details
         WHERE site_id = v_site_id AND order_id = v_order_id AND customer_id = v_customer_id
    ) THEN
        RAISE EXCEPTION 'Site-order/customer link missing';
    END IF;

    SELECT access_row.data_code INTO v_access_code
      FROM solar_app.user_site_access_details a
      JOIN solar_app.ref_data access_row ON access_row.ref_data_id = a.access_role_ref_data_id
     WHERE a.user_id = v_user_id AND a.site_id = v_site_id AND a.active_ind;
    IF v_access_code <> 'ACCESS_OWNER' THEN
        RAISE EXCEPTION 'Expected ACCESS_OWNER, got %', v_access_code;
    END IF;

    SELECT type_row.data_code INTO v_ntf_type
      FROM solar_app.notification_details n
      JOIN solar_app.ref_data type_row ON type_row.ref_data_id = n.notification_type_ref_data_id
     WHERE n.notification_id = v_ntf_id;
    IF v_ntf_type <> 'NTF_ACCOUNT_READY' THEN
        RAISE EXCEPTION 'Expected NTF_ACCOUNT_READY, got %', v_ntf_type;
    END IF;

    RAISE NOTICE 'PASS happy_path user=% customer=% order=% site=% eq=% ntf=%',
        v_user_id, v_customer_id, v_order_id, v_site_id, v_eq_id, v_ntf_id;

    ------------------------------------------------------------------
    -- 2) Non-admin rejection
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_user_details(jsonb_build_object(
        'api_endpoint', '/api/admin/customers/create',
        'jwt_token_hash', v_customer_hash,
        'country_id', v_country_id::TEXT,
        'national_number', '9988770004',
        'full_name', 'PATHB_LIVE NonAdmin',
        'customer_code', 'PATHB-LIVE-CUST-NA',
        'order_no', 'PATHB-LIVE-ORD-NA',
        'order_status_code', 'ORD_COMMISSIONED',
        'currency_code', 'INR',
        'sites', jsonb_build_array(jsonb_build_object(
            'site_name', 'PATHB_LIVE NA Site',
            'address_line1', 'NA Road',
            'installation_status_code', 'INST_COMMISSIONED',
            'commissioning_on', '2026-02-01',
            'equipment', jsonb_build_array(jsonb_build_object('equipment_type_code', 'EQ_PANEL'))
        ))
    ));
    IF COALESCE(v_resp->>'status', '') <> 'ERROR' OR COALESCE((v_resp->>'code')::INT, 0) <> 403 THEN
        RAISE EXCEPTION 'Non-admin expected 403, got %', v_resp;
    END IF;
    RAISE NOTICE 'PASS non_admin_403';

    ------------------------------------------------------------------
    -- 3) Duplicate mobile rejection
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_user_details(jsonb_build_object(
        'api_endpoint', '/api/admin/customers/create',
        'jwt_token_hash', v_admin_hash,
        'country_id', v_country_id::TEXT,
        'national_number', '9988770003',
        'full_name', 'PATHB_LIVE Duplicate',
        'customer_code', 'PATHB-LIVE-CUST-DUP',
        'order_no', 'PATHB-LIVE-ORD-DUP',
        'order_status_code', 'ORD_COMMISSIONED',
        'currency_code', 'INR',
        'sites', jsonb_build_array(jsonb_build_object(
            'site_name', 'PATHB_LIVE Dup Site',
            'address_line1', 'Dup Road',
            'installation_status_code', 'INST_COMMISSIONED',
            'commissioning_on', '2026-02-01',
            'equipment', jsonb_build_array(jsonb_build_object('equipment_type_code', 'EQ_PANEL'))
        ))
    ));
    IF COALESCE(v_resp->>'status', '') <> 'ERROR' OR COALESCE((v_resp->>'code')::INT, 0) <> 409 THEN
        RAISE EXCEPTION 'Duplicate mobile expected 409, got %', v_resp;
    END IF;
    RAISE NOTICE 'PASS duplicate_mobile_409';

    ------------------------------------------------------------------
    -- 4) Invalid equipment causes complete rollback
    ------------------------------------------------------------------
    SELECT COUNT(*) INTO v_before_users
      FROM solar_app.user_details WHERE mobile_e164 = '+919988770099';

    BEGIN
        v_resp := solar_app.fn_create_user_details(jsonb_build_object(
            'api_endpoint', '/api/admin/customers/create',
            'jwt_token_hash', v_admin_hash,
            'country_id', v_country_id::TEXT,
            'national_number', '9988770099',
            'full_name', 'PATHB_LIVE Rollback',
            'customer_code', 'PATHB-LIVE-CUST-ROLL',
            'order_no', 'PATHB-LIVE-ORD-ROLL',
            'order_status_code', 'ORD_COMMISSIONED',
            'currency_code', 'INR',
            'sites', jsonb_build_array(jsonb_build_object(
                'site_name', 'PATHB_LIVE Roll Site',
                'address_line1', 'Roll Road',
                'installation_status_code', 'INST_COMMISSIONED',
                'commissioning_on', '2026-02-01',
                'equipment', jsonb_build_array(
                    jsonb_build_object('equipment_type_code', 'EQ_NOT_A_REAL_TYPE')
                )
            ))
        ));
        -- Function should catch and return ERROR 400/500 rather than leave partial rows.
        IF COALESCE(v_resp->>'status', '') = 'SUCCESS' THEN
            RAISE EXCEPTION 'Invalid equipment unexpectedly succeeded: %', v_resp;
        END IF;
        v_fail_msg := v_resp->>'message';
    EXCEPTION
        WHEN OTHERS THEN
            v_fail_msg := SQLERRM;
    END;

    SELECT COUNT(*) INTO v_after_users
      FROM solar_app.user_details WHERE mobile_e164 = '+919988770099';
    IF v_after_users <> v_before_users THEN
        RAISE EXCEPTION 'Rollback failed; user row remains for +919988770099';
    END IF;
    IF EXISTS (SELECT 1 FROM solar_app.customer_details WHERE customer_code = 'PATHB-LIVE-CUST-ROLL') THEN
        RAISE EXCEPTION 'Rollback failed; customer PATHB-LIVE-CUST-ROLL remains';
    END IF;
    IF EXISTS (SELECT 1 FROM solar_app.order_details WHERE order_no = 'PATHB-LIVE-ORD-ROLL') THEN
        RAISE EXCEPTION 'Rollback failed; order PATHB-LIVE-ORD-ROLL remains';
    END IF;
    RAISE NOTICE 'PASS invalid_equipment_rollback msg=%', v_fail_msg;
END $$;

-- Cleanup only PATHB_LIVE fixtures and report counts.
DO $$
DECLARE
    v_ntf INTEGER;
    v_order_lines INTEGER;
    v_orders INTEGER;
    v_equipment INTEGER;
    v_access INTEGER;
    v_sites INTEGER;
    v_customers INTEGER;
    v_sessions INTEGER;
    v_users INTEGER;
    v_sql_logs INTEGER := 0;
BEGIN
    DELETE FROM solar_app.notification_details
     WHERE recipient_user_id IN (
            SELECT user_id FROM solar_app.user_details
             WHERE mobile_e164 LIKE '+91998877%'
                OR created_by = 'PATHB_LIVE'
          )
        OR created_by = 'PATHB_LIVE';
    GET DIAGNOSTICS v_ntf = ROW_COUNT;

    DELETE FROM solar_app.order_line_details
     WHERE order_id IN (
            SELECT order_id FROM solar_app.order_details
             WHERE order_no LIKE 'PATHB-LIVE-%' OR created_by = 'PATHB_LIVE'
          );
    GET DIAGNOSTICS v_order_lines = ROW_COUNT;

    DELETE FROM solar_app.order_details
     WHERE order_no LIKE 'PATHB-LIVE-%' OR created_by = 'PATHB_LIVE';
    GET DIAGNOSTICS v_orders = ROW_COUNT;

    DELETE FROM solar_app.equipment_details
     WHERE created_by = 'PATHB_LIVE'
        OR site_id IN (
            SELECT site_id FROM solar_app.site_details
             WHERE created_by = 'PATHB_LIVE' OR site_name LIKE 'PATHB_LIVE%'
          );
    GET DIAGNOSTICS v_equipment = ROW_COUNT;

    DELETE FROM solar_app.user_site_access_details
     WHERE created_by = 'PATHB_LIVE'
        OR user_id IN (
            SELECT user_id FROM solar_app.user_details
             WHERE mobile_e164 LIKE '+91998877%' OR created_by = 'PATHB_LIVE'
          );
    GET DIAGNOSTICS v_access = ROW_COUNT;

    DELETE FROM solar_app.site_details
     WHERE created_by = 'PATHB_LIVE'
        OR site_name LIKE 'PATHB_LIVE%'
        OR customer_id IN (
            SELECT customer_id FROM solar_app.customer_details
             WHERE customer_code LIKE 'PATHB-LIVE-%' OR created_by = 'PATHB_LIVE'
          );
    GET DIAGNOSTICS v_sites = ROW_COUNT;

    DELETE FROM solar_app.customer_details
     WHERE customer_code LIKE 'PATHB-LIVE-%' OR created_by = 'PATHB_LIVE';
    GET DIAGNOSTICS v_customers = ROW_COUNT;

    DELETE FROM solar_app.log_user_sessions
     WHERE jwt_token_hash LIKE 'bb22cc33%' OR created_by = 'PATHB_LIVE';
    GET DIAGNOSTICS v_sessions = ROW_COUNT;

    DELETE FROM solar_app.user_details
     WHERE mobile_e164 LIKE '+91998877%' OR created_by = 'PATHB_LIVE';
    GET DIAGNOSTICS v_users = ROW_COUNT;

    IF to_regclass('solar_app.log_sql_functions') IS NOT NULL THEN
        DELETE FROM solar_app.log_sql_functions
         WHERE function_name = 'fn_create_user_details'
           AND (
                created_by = 'PATHB_LIVE'
                OR COALESCE(request_payload->>'customer_code', '') LIKE 'PATHB-LIVE-%'
                OR COALESCE(request_payload->>'national_number', '') LIKE '998877%'
           );
        GET DIAGNOSTICS v_sql_logs = ROW_COUNT;
    END IF;

    RAISE NOTICE 'CLEANUP ntf=% order_lines=% orders=% equipment=% access=% sites=% customers=% sessions=% users=% sql_logs=%',
        v_ntf, v_order_lines, v_orders, v_equipment, v_access, v_sites, v_customers, v_sessions, v_users, v_sql_logs;
END $$;

-- Preservation checks
SELECT 'PRESERVE_USERS' AS check_name,
       COUNT(*) AS remaining
  FROM solar_app.user_details u
  JOIN pathb_live_baseline b ON b.kind = 'user' AND b.id = u.user_id::text;

SELECT 'PRESERVE_CUSTOMERS' AS check_name,
       COUNT(*) AS remaining
  FROM solar_app.customer_details c
  JOIN pathb_live_baseline b ON b.kind = 'customer' AND b.id = c.customer_id::text;

SELECT 'PRESERVE_SITES' AS check_name,
       COUNT(*) AS remaining
  FROM solar_app.site_details s
  JOIN pathb_live_baseline b ON b.kind = 'site' AND b.id = s.site_id::text;

SELECT 'LEFTOVER_PATHB_LIVE_USERS' AS check_name, COUNT(*) AS remaining
  FROM solar_app.user_details
 WHERE mobile_e164 LIKE '+91998877%' OR created_by = 'PATHB_LIVE';

SELECT 'LEFTOVER_PATHB_LIVE_CUSTOMERS' AS check_name, COUNT(*) AS remaining
  FROM solar_app.customer_details
 WHERE customer_code LIKE 'PATHB-LIVE-%' OR created_by = 'PATHB_LIVE';

SELECT current_database() AS db,
       to_regprocedure('solar_app.fn_create_user_details(jsonb)') AS pathb_fn,
       to_regprocedure('solar_app.fn_create_notification_details(jsonb)') AS ntf_fn,
       to_regprocedure('solar_app.fn_create_pin_user(jsonb)') AS patha_fn,
       to_regclass('solar_app.amc_credit_reservation_details') AS amc_reservation;
