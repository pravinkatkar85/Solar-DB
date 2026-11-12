-- Isolated admin technician list tests for SolarDB_restore_check only.
-- Do not run against SolarDB.
-- Creates M7LIST_IT fixtures, asserts outcomes, then cleans them up.

\set ON_ERROR_STOP on

SELECT current_database() AS db, current_user AS usr;

DO $$
BEGIN
    IF current_database() IS DISTINCT FROM 'SolarDB_restore_check' THEN
        RAISE EXCEPTION 'Refuse to run technician list IT on database %', current_database();
    END IF;
END $$;

BEGIN;

DELETE FROM solar_app.log_user_sessions
 WHERE jwt_token_hash LIKE 'cc33dd44%' OR created_by = 'M7LIST_IT';
DELETE FROM solar_app.technician_details
 WHERE created_by = 'M7LIST_IT'
    OR user_id IN (
        SELECT user_id FROM solar_app.user_details
         WHERE mobile_e164 LIKE '+91990033%' OR created_by = 'M7LIST_IT'
    );
DELETE FROM solar_app.log_sql_functions
 WHERE created_by = 'M7LIST_IT'
    OR (
        function_name = 'fn_get_technician_details'
        AND created_on >= clock_timestamp() - INTERVAL '1 day'
        AND logged_in_user_id IN (
            SELECT user_id::TEXT FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990033%'
        )
    );
DELETE FROM solar_app.user_details
 WHERE mobile_e164 LIKE '+91990033%' OR created_by = 'M7LIST_IT';

COMMIT;

DO $$
DECLARE
    v_role_admin BIGINT;
    v_role_customer BIGINT;
    v_role_tech BIGINT;
    v_acct_active BIGINT;
    v_reg_self BIGINT;
    v_country_id BIGINT := 1;
    v_admin_id BIGINT;
    v_customer_id BIGINT;
    v_tech1_user BIGINT;
    v_tech2_user BIGINT;
    v_tech3_user BIGINT;
    v_tech1_id BIGINT;
    v_tech2_id BIGINT;
    v_tech3_id BIGINT;
    v_admin_hash TEXT := 'cc33dd44ee55ff6677889900aaaabbbbccccddddeeeeffff000011112222aa11';
    v_customer_hash TEXT := 'cc33dd44ee55ff6677889900aaaabbbbccccddddeeeeffff000022223333bb22';
    v_resp JSONB;
    v_count INTEGER;
    v_has_secret BOOLEAN;
    v_ids TEXT[];
BEGIN
    IF to_regprocedure('solar_app.fn_get_technician_details(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'fn_get_technician_details is not installed on SolarDB_restore_check';
    END IF;

    SELECT ref_data_id INTO v_role_admin
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'USER_ROLES' AND r.data_code = 'ROLE_ADMIN' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_role_customer
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'USER_ROLES' AND r.data_code = 'ROLE_CUSTOMER' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_role_tech
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'USER_ROLES' AND r.data_code = 'ROLE_TECHNICIAN' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_acct_active
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'USER_ACCOUNT_STATUSES' AND r.data_code = 'ACCT_ACTIVE' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_reg_self
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'REGISTRATION_SOURCES' AND r.data_code = 'REG_SELF_APP' AND r.active_ind AND c.active_ind;

    IF v_role_admin IS NULL OR v_role_customer IS NULL OR v_role_tech IS NULL
       OR v_acct_active IS NULL OR v_reg_self IS NULL THEN
        RAISE EXCEPTION 'Missing required technician list reference fixtures';
    END IF;

    INSERT INTO solar_app.user_details (
        country_id, mobile_e164, full_name, role_ref_data_id, pin_hash,
        admin_registered, account_status_ref_data_id, registration_source_ref_data_id,
        created_by, updated_by
    ) VALUES (
        v_country_id, '+919900330001', 'M7LIST IT Admin', v_role_admin, NULL,
        TRUE, v_acct_active, v_reg_self, 'M7LIST_IT', 'M7LIST_IT'
    ) RETURNING user_id INTO v_admin_id;

    INSERT INTO solar_app.user_details (
        country_id, mobile_e164, full_name, role_ref_data_id, pin_hash,
        admin_registered, account_status_ref_data_id, registration_source_ref_data_id,
        created_by, updated_by
    ) VALUES (
        v_country_id, '+919900330002', 'M7LIST IT Customer', v_role_customer, NULL,
        TRUE, v_acct_active, v_reg_self, 'M7LIST_IT', 'M7LIST_IT'
    ) RETURNING user_id INTO v_customer_id;

    INSERT INTO solar_app.log_user_sessions (
        user_id, mobile_e164, jwt_token_hash, session_status, active_ind, created_by, updated_by
    ) VALUES
        (v_admin_id, '+919900330001', v_admin_hash, 'ACTIVE', TRUE, 'M7LIST_IT', 'M7LIST_IT'),
        (v_customer_id, '+919900330002', v_customer_hash, 'ACTIVE', TRUE, 'M7LIST_IT', 'M7LIST_IT');

    INSERT INTO solar_app.user_details (
        country_id, mobile_e164, full_name, role_ref_data_id, pin_hash,
        admin_registered, account_status_ref_data_id, registration_source_ref_data_id,
        created_by, updated_by
    ) VALUES (
        v_country_id, '+919900330011', 'List Tech Active', v_role_tech, 'SHOULD_NOT_LEAK',
        TRUE, v_acct_active, v_reg_self, 'M7LIST_IT', 'M7LIST_IT'
    ) RETURNING user_id INTO v_tech1_user;
    INSERT INTO solar_app.technician_details (
        user_id, employee_code, is_available, active_ind, created_by, updated_by
    ) VALUES (
        v_tech1_user, 'M7LIST-A', TRUE, TRUE, 'M7LIST_IT', 'M7LIST_IT'
    ) RETURNING technician_id INTO v_tech1_id;

    INSERT INTO solar_app.user_details (
        country_id, mobile_e164, full_name, role_ref_data_id, pin_hash,
        admin_registered, account_status_ref_data_id, registration_source_ref_data_id,
        created_by, updated_by
    ) VALUES (
        v_country_id, '+919900330012', 'List Tech Unavailable', v_role_tech, NULL,
        TRUE, v_acct_active, v_reg_self, 'M7LIST_IT', 'M7LIST_IT'
    ) RETURNING user_id INTO v_tech2_user;
    INSERT INTO solar_app.technician_details (
        user_id, employee_code, is_available, active_ind, created_by, updated_by
    ) VALUES (
        v_tech2_user, 'M7LIST-B', FALSE, TRUE, 'M7LIST_IT', 'M7LIST_IT'
    ) RETURNING technician_id INTO v_tech2_id;

    INSERT INTO solar_app.user_details (
        country_id, mobile_e164, full_name, role_ref_data_id, pin_hash,
        admin_registered, account_status_ref_data_id, registration_source_ref_data_id,
        created_by, updated_by
    ) VALUES (
        v_country_id, '+919900330013', 'List Tech Inactive', v_role_tech, NULL,
        TRUE, v_acct_active, v_reg_self, 'M7LIST_IT', 'M7LIST_IT'
    ) RETURNING user_id INTO v_tech3_user;
    INSERT INTO solar_app.technician_details (
        user_id, employee_code, is_available, active_ind, created_by, updated_by
    ) VALUES (
        v_tech3_user, 'M7LIST-C', TRUE, FALSE, 'M7LIST_IT', 'M7LIST_IT'
    ) RETURNING technician_id INTO v_tech3_id;

    -- Admin list (all fixture technicians present)
    v_resp := solar_app.fn_get_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians',
        'jwt_token_hash', v_admin_hash
    ));
    IF v_resp->>'status' IS DISTINCT FROM 'SUCCESS' OR (v_resp->>'code')::INT IS DISTINCT FROM 200 THEN
        RAISE EXCEPTION 'Admin list failed: %', v_resp;
    END IF;
    SELECT COUNT(*) INTO v_count
      FROM jsonb_array_elements(v_resp->'data'->'technicians') t
     WHERE t->>'employee_code' LIKE 'M7LIST-%';
    IF v_count IS DISTINCT FROM 3 THEN
        RAISE EXCEPTION 'Expected 3 M7LIST technicians, got % in %', v_count, v_resp;
    END IF;

    SELECT bool_or(
        (t::TEXT LIKE '%SHOULD_NOT_LEAK%')
        OR (t ? 'pin_hash')
        OR (t ? 'pin')
        OR (t ? 'jwt_token_hash')
    )
      INTO v_has_secret
      FROM jsonb_array_elements(v_resp->'data'->'technicians') t;
    IF v_has_secret IS TRUE THEN
        RAISE EXCEPTION 'List leaked authentication secret fields: %', v_resp;
    END IF;

    -- active_ind = true
    v_resp := solar_app.fn_get_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians',
        'jwt_token_hash', v_admin_hash,
        'active_ind', TRUE
    ));
    SELECT array_agg(t->>'employee_code' ORDER BY t->>'employee_code')
      INTO v_ids
      FROM jsonb_array_elements(v_resp->'data'->'technicians') t
     WHERE t->>'employee_code' LIKE 'M7LIST-%';
    IF v_ids IS DISTINCT FROM ARRAY['M7LIST-A', 'M7LIST-B']::TEXT[] THEN
        RAISE EXCEPTION 'active_ind=true filter mismatch: %', v_ids;
    END IF;

    -- is_available = false
    v_resp := solar_app.fn_get_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians',
        'jwt_token_hash', v_admin_hash,
        'is_available', FALSE
    ));
    SELECT array_agg(t->>'employee_code' ORDER BY t->>'employee_code')
      INTO v_ids
      FROM jsonb_array_elements(v_resp->'data'->'technicians') t
     WHERE t->>'employee_code' LIKE 'M7LIST-%';
    IF v_ids IS DISTINCT FROM ARRAY['M7LIST-B']::TEXT[] THEN
        RAISE EXCEPTION 'is_available=false filter mismatch: %', v_ids;
    END IF;

    -- combined filter that yields empty for fixtures
    v_resp := solar_app.fn_get_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians',
        'jwt_token_hash', v_admin_hash,
        'active_ind', FALSE,
        'is_available', FALSE
    ));
    IF v_resp->>'status' IS DISTINCT FROM 'SUCCESS' THEN
        RAISE EXCEPTION 'Empty filtered list should still succeed: %', v_resp;
    END IF;
    SELECT COUNT(*) INTO v_count
      FROM jsonb_array_elements(v_resp->'data'->'technicians') t
     WHERE t->>'employee_code' LIKE 'M7LIST-%';
    IF v_count IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'Expected empty M7LIST filter result, got %', v_resp;
    END IF;

    -- Non-admin rejection
    v_resp := solar_app.fn_get_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians',
        'jwt_token_hash', v_customer_hash
    ));
    IF v_resp->>'status' IS DISTINCT FROM 'ERROR' OR (v_resp->>'code')::INT IS DISTINCT FROM 403 THEN
        RAISE EXCEPTION 'Non-admin should be 403: %', v_resp;
    END IF;

    -- Invalid session
    v_resp := solar_app.fn_get_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians',
        'jwt_token_hash', 'cc33dd44ee55ff6677889900aaaabbbbccccddddeeeeffff000099998888cc99'
    ));
    IF v_resp->>'status' IS DISTINCT FROM 'ERROR' OR (v_resp->>'code')::INT IS DISTINCT FROM 401 THEN
        RAISE EXCEPTION 'Missing session should be 401: %', v_resp;
    END IF;

    -- Invalid active_ind
    v_resp := solar_app.fn_get_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians',
        'jwt_token_hash', v_admin_hash,
        'active_ind', 'maybe'
    ));
    IF v_resp->>'status' IS DISTINCT FROM 'ERROR' OR (v_resp->>'code')::INT IS DISTINCT FROM 400 THEN
        RAISE EXCEPTION 'Invalid active_ind should be 400: %', v_resp;
    END IF;

    RAISE NOTICE 'fn_get_technician_details IT passed (admin=%, tech1=%, tech2=%, tech3=%)',
        v_admin_id, v_tech1_id, v_tech2_id, v_tech3_id;
END $$;

BEGIN;

DELETE FROM solar_app.log_user_sessions
 WHERE jwt_token_hash LIKE 'cc33dd44%' OR created_by = 'M7LIST_IT';
DELETE FROM solar_app.technician_details
 WHERE created_by = 'M7LIST_IT'
    OR user_id IN (
        SELECT user_id FROM solar_app.user_details
         WHERE mobile_e164 LIKE '+91990033%' OR created_by = 'M7LIST_IT'
    );
DELETE FROM solar_app.log_sql_functions
 WHERE created_by = 'M7LIST_IT'
    OR (
        function_name = 'fn_get_technician_details'
        AND created_on >= clock_timestamp() - INTERVAL '1 day'
        AND logged_in_user_id IN (
            SELECT user_id::TEXT FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990033%'
        )
    );
DELETE FROM solar_app.user_details
 WHERE mobile_e164 LIKE '+91990033%' OR created_by = 'M7LIST_IT';

COMMIT;

SELECT 'technician_list_it_complete' AS status;
