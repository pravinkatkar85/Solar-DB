-- Isolated M7 Phase 1 technician tests for SolarDB_restore_check only.
-- Do not run against SolarDB.
-- Creates M7P1_IT fixtures, asserts outcomes, then cleans them up.

\set ON_ERROR_STOP on

SELECT current_database() AS db, current_user AS usr;

DO $$
BEGIN
    IF current_database() IS DISTINCT FROM 'SolarDB_restore_check' THEN
        RAISE EXCEPTION 'Refuse to run M7 Phase 1 IT on database %', current_database();
    END IF;
END $$;

BEGIN;

-- Cleanup any prior M7P1_IT leftovers
DELETE FROM solar_app.log_notification_delivery
 WHERE notification_id IN (
        SELECT notification_id FROM solar_app.notification_details
         WHERE created_by = 'M7P1_IT'
            OR recipient_user_id IN (
                SELECT user_id FROM solar_app.user_details
                 WHERE mobile_e164 LIKE '+91990022%' OR created_by = 'M7P1_IT'
            )
      );
DELETE FROM solar_app.notification_details
 WHERE created_by = 'M7P1_IT'
    OR recipient_user_id IN (
        SELECT user_id FROM solar_app.user_details
         WHERE mobile_e164 LIKE '+91990022%' OR created_by = 'M7P1_IT'
    );
DELETE FROM solar_app.job_assignment_details
 WHERE created_by = 'M7P1_IT'
    OR technician_id IN (
        SELECT technician_id FROM solar_app.technician_details WHERE created_by = 'M7P1_IT'
    );
DELETE FROM solar_app.site_visit_details
 WHERE created_by = 'M7P1_IT' OR visit_no LIKE 'M7P1-SV-%';
DELETE FROM solar_app.service_request_details
 WHERE created_by = 'M7P1_IT' OR service_request_no LIKE 'M7P1-SR-%';
DELETE FROM solar_app.technician_details
 WHERE created_by = 'M7P1_IT'
    OR user_id IN (SELECT user_id FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990022%' OR created_by = 'M7P1_IT');
DELETE FROM solar_app.site_details
 WHERE created_by = 'M7P1_IT'
    OR customer_id IN (SELECT customer_id FROM solar_app.customer_details WHERE customer_code LIKE 'M7P1-CUST-%');
DELETE FROM solar_app.customer_details
 WHERE customer_code LIKE 'M7P1-CUST-%' OR created_by = 'M7P1_IT';
DELETE FROM solar_app.log_user_sessions
 WHERE jwt_token_hash LIKE 'bb22cc33%' OR created_by = 'M7P1_IT';
DELETE FROM solar_app.log_sql_functions
 WHERE created_by = 'M7P1_IT'
    OR function_name IN (
        'fn_create_technician_details',
        'fn_update_technician_details',
        'fn_create_job_assignment_details'
    )
   AND created_on >= clock_timestamp() - INTERVAL '1 day'
   AND logged_in_user_id IN (
        SELECT user_id::TEXT FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990022%'
    );
DELETE FROM solar_app.user_details
 WHERE mobile_e164 LIKE '+91990022%' OR created_by = 'M7P1_IT';

COMMIT;

DO $$
DECLARE
    v_role_admin BIGINT;
    v_role_customer BIGINT;
    v_role_tech BIGINT;
    v_acct_active BIGINT;
    v_reg_self BIGINT;
    v_sr_open BIGINT;
    v_sr_assigned BIGINT;
    v_visit_scheduled BIGINT;
    v_visit_assigned BIGINT;
    v_visit_purpose BIGINT;
    v_service_type BIGINT;
    v_country_id BIGINT := 1;
    v_office_id BIGINT;
    v_currency CHAR(3);
    v_admin_id BIGINT;
    v_customer_actor_id BIGINT;
    v_customer_id BIGINT;
    v_site_id BIGINT;
    v_admin_hash TEXT := 'bb22cc33dd44ee55ff6677889900aaaabbbbccccddddeeeeffff00001111aa11';
    v_customer_hash TEXT := 'bb22cc33dd44ee55ff6677889900aaaabbbbccccddddeeeeffff00002222bb22';
    v_payload JSONB;
    v_resp JSONB;
    v_tech_id BIGINT;
    v_tech_user_id BIGINT;
    v_tech2_id BIGINT;
    v_sr_id BIGINT;
    v_sr2_id BIGINT;
    v_visit_id BIGINT;
    v_job_id BIGINT;
    v_job_count INTEGER;
    v_ntf_count INTEGER;
    v_sr_status TEXT;
    v_visit_status TEXT;
    v_assignee BIGINT;
    v_is_available BOOLEAN;
    v_active_ind BOOLEAN;
    v_user_active BOOLEAN;
    v_before_jobs INTEGER;
    v_after_jobs INTEGER;
    v_before_sr_tech BIGINT;
    v_after_sr_tech BIGINT;
    v_ntf_active BOOLEAN;
BEGIN
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
    SELECT ref_data_id INTO v_sr_open
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'SERVICE_REQUEST_STATUSES' AND r.data_code = 'SR_OPEN' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_sr_assigned
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'SERVICE_REQUEST_STATUSES' AND r.data_code = 'SR_ASSIGNED' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_visit_scheduled
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'SITE_VISIT_STATUSES' AND r.data_code = 'VISIT_SCHEDULED' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_visit_assigned
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'SITE_VISIT_STATUSES' AND r.data_code = 'VISIT_ASSIGNED' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_visit_purpose
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'SITE_VISIT_PURPOSES' AND r.data_code = 'VISIT_SERVICE' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_service_type
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'SERVICE_TYPES' AND r.active_ind AND c.active_ind
     ORDER BY r.ref_data_id LIMIT 1;
    SELECT office_location_id INTO v_office_id
      FROM solar_app.ref_office_locations WHERE active_ind IS TRUE ORDER BY office_location_id LIMIT 1;
    SELECT currency_code INTO v_currency
      FROM solar_app.ref_currencies WHERE active_ind IS TRUE ORDER BY currency_code LIMIT 1;

    IF v_role_admin IS NULL OR v_role_customer IS NULL OR v_role_tech IS NULL
       OR v_acct_active IS NULL OR v_reg_self IS NULL OR v_sr_open IS NULL
       OR v_sr_assigned IS NULL OR v_visit_scheduled IS NULL OR v_visit_assigned IS NULL
       OR v_visit_purpose IS NULL OR v_service_type IS NULL OR v_office_id IS NULL
       OR v_currency IS NULL THEN
        RAISE EXCEPTION 'Missing required M7 Phase 1 reference fixtures';
    END IF;

    IF to_regprocedure('solar_app.fn_create_notification_details(jsonb)') IS NULL
       OR to_regprocedure('solar_app.fn_create_technician_details(jsonb)') IS NULL
       OR to_regprocedure('solar_app.fn_update_technician_details(jsonb)') IS NULL
       OR to_regprocedure('solar_app.fn_create_job_assignment_details(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'Required M7 Phase 1 functions are not installed on SolarDB_restore_check';
    END IF;

    INSERT INTO solar_app.user_details (
        country_id, mobile_e164, full_name, role_ref_data_id, pin_hash,
        admin_registered, account_status_ref_data_id, registration_source_ref_data_id,
        created_by, updated_by
    ) VALUES (
        v_country_id, '+919900220001', 'M7P1 IT Admin', v_role_admin, NULL,
        TRUE, v_acct_active, v_reg_self, 'M7P1_IT', 'M7P1_IT'
    ) RETURNING user_id INTO v_admin_id;

    INSERT INTO solar_app.user_details (
        country_id, mobile_e164, full_name, role_ref_data_id, pin_hash,
        admin_registered, account_status_ref_data_id, registration_source_ref_data_id,
        created_by, updated_by
    ) VALUES (
        v_country_id, '+919900220002', 'M7P1 IT Customer Actor', v_role_customer, NULL,
        TRUE, v_acct_active, v_reg_self, 'M7P1_IT', 'M7P1_IT'
    ) RETURNING user_id INTO v_customer_actor_id;

    INSERT INTO solar_app.customer_details (
        user_id, customer_code, billing_name, created_by, updated_by
    ) VALUES (
        v_customer_actor_id, 'M7P1-CUST-0001', 'M7P1 Customer', 'M7P1_IT', 'M7P1_IT'
    ) RETURNING customer_id INTO v_customer_id;

    INSERT INTO solar_app.site_details (
        customer_id, site_name, address_line1, installation_status_ref_data_id,
        commissioning_on, created_by, updated_by
    )
    SELECT v_customer_id, 'M7P1 Site', '1 M7 Lane',
           r.ref_data_id, CURRENT_DATE, 'M7P1_IT', 'M7P1_IT'
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'INSTALLATION_STATUSES'
       AND r.data_code = 'INST_COMMISSIONED'
       AND r.active_ind AND c.active_ind
     LIMIT 1
    RETURNING site_id INTO v_site_id;
    IF v_site_id IS NULL THEN
        RAISE EXCEPTION 'Could not create M7P1 site fixture';
    END IF;

    INSERT INTO solar_app.log_user_sessions (
        user_id, mobile_e164, jwt_token_hash, session_status, active_ind, created_by, updated_by
    ) VALUES
        (v_admin_id, '+919900220001', v_admin_hash, 'ACTIVE', TRUE, 'M7P1_IT', 'M7P1_IT'),
        (v_customer_actor_id, '+919900220002', v_customer_hash, 'ACTIVE', TRUE, 'M7P1_IT', 'M7P1_IT');

    ------------------------------------------------------------------
    -- 1) Admin technician creation
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians/create',
        'jwt_token_hash', v_admin_hash,
        'logged_in_user_id', v_admin_id::TEXT,
        'role', 'ROLE_ADMIN',
        'country_id', v_country_id::TEXT,
        'national_number', '9900220003',
        'full_name', 'M7P1 Technician One',
        'employee_code', 'M7P1-EMP-001',
        'email', 'm7p1.tech1@example.com',
        'service_radius_km', '25',
        'is_available', true
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' OR (v_resp->>'code')::INT <> 200 THEN
        RAISE EXCEPTION 'Admin create technician failed: %', v_resp;
    END IF;
    v_tech_id := (v_resp->'data'->>'technician_id')::BIGINT;
    v_tech_user_id := (v_resp->'data'->>'user_id')::BIGINT;
    IF COALESCE(v_resp->'data'->>'role_code','') <> 'ROLE_TECHNICIAN'
       OR COALESCE(v_resp->'data'->>'admin_registered','') <> 'true' THEN
        RAISE EXCEPTION 'Technician create response fields unexpected: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 2) Non-admin rejection
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians/create',
        'jwt_token_hash', v_customer_hash,
        'country_id', v_country_id::TEXT,
        'national_number', '9900220004',
        'full_name', 'Should Fail',
        'employee_code', 'M7P1-EMP-FAIL'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 403 THEN
        RAISE EXCEPTION 'Non-admin create should be 403: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 3) Duplicate mobile and employee code
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians/create',
        'jwt_token_hash', v_admin_hash,
        'country_id', v_country_id::TEXT,
        'national_number', '9900220003',
        'full_name', 'Dup Mobile',
        'employee_code', 'M7P1-EMP-002'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 409 THEN
        RAISE EXCEPTION 'Duplicate mobile should be 409: %', v_resp;
    END IF;

    v_resp := solar_app.fn_create_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians/create',
        'jwt_token_hash', v_admin_hash,
        'country_id', v_country_id::TEXT,
        'national_number', '9900220005',
        'full_name', 'Dup Emp',
        'employee_code', 'M7P1-EMP-001'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 409 THEN
        RAISE EXCEPTION 'Duplicate employee code should be 409: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 4) Availability + activation/deactivation
    ------------------------------------------------------------------
    v_resp := solar_app.fn_update_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians/update',
        'jwt_token_hash', v_admin_hash,
        'technician_id', v_tech_id::TEXT,
        'is_available', false
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Set unavailable failed: %', v_resp;
    END IF;
    SELECT is_available INTO v_is_available FROM solar_app.technician_details WHERE technician_id = v_tech_id;
    IF v_is_available IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'is_available not false after update';
    END IF;

    v_resp := solar_app.fn_update_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians/update',
        'jwt_token_hash', v_admin_hash,
        'technician_id', v_tech_id::TEXT,
        'active_ind', false
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Deactivate failed: %', v_resp;
    END IF;
    SELECT tech.active_ind, app_user.active_ind
      INTO v_active_ind, v_user_active
      FROM solar_app.technician_details tech
      JOIN solar_app.user_details app_user ON app_user.user_id = tech.user_id
     WHERE tech.technician_id = v_tech_id;
    IF v_active_ind IS DISTINCT FROM FALSE OR v_user_active IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'Deactivation did not sync active_ind flags';
    END IF;

    v_resp := solar_app.fn_update_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians/update',
        'jwt_token_hash', v_admin_hash,
        'technician_id', v_tech_id::TEXT,
        'active_ind', true,
        'is_available', true
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Reactivate failed: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- Fixtures: open SR + scheduled visit (+ second open SR for customer-unaffected)
    ------------------------------------------------------------------
    INSERT INTO solar_app.service_request_details (
        service_request_no, site_id, customer_id, service_type_ref_data_id,
        status_ref_data_id, preferred_on, created_by, updated_by
    ) VALUES (
        'M7P1-SR-0001', v_site_id, v_customer_id, v_service_type,
        v_sr_open, CURRENT_DATE + 2, 'M7P1_IT', 'M7P1_IT'
    ) RETURNING service_request_id INTO v_sr_id;

    INSERT INTO solar_app.service_request_details (
        service_request_no, site_id, customer_id, service_type_ref_data_id,
        status_ref_data_id, preferred_on, created_by, updated_by
    ) VALUES (
        'M7P1-SR-0002', v_site_id, v_customer_id, v_service_type,
        v_sr_open, CURRENT_DATE + 3, 'M7P1_IT', 'M7P1_IT'
    ) RETURNING service_request_id INTO v_sr2_id;

    INSERT INTO solar_app.site_visit_details (
        visit_no, visit_purpose_ref_data_id, customer_id, site_id,
        office_location_id, visit_status_ref_data_id, scheduled_on,
        charge_amount, currency_code, created_by, updated_by
    ) VALUES (
        'M7P1-SV-0001', v_visit_purpose, v_customer_id, v_site_id,
        v_office_id, v_visit_scheduled, CURRENT_DATE + 4,
        0, v_currency, 'M7P1_IT', 'M7P1_IT'
    ) RETURNING site_visit_id INTO v_visit_id;

    ------------------------------------------------------------------
    -- 5) Inactive / unavailable technician rejection
    ------------------------------------------------------------------
    PERFORM solar_app.fn_update_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians/update',
        'jwt_token_hash', v_admin_hash,
        'technician_id', v_tech_id::TEXT,
        'is_available', false
    ));
    v_resp := solar_app.fn_create_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/jobs/assign',
        'jwt_token_hash', v_admin_hash,
        'job_type', 'SERVICE_REQUEST',
        'technician_id', v_tech_id::TEXT,
        'service_request_id', v_sr_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 409 THEN
        RAISE EXCEPTION 'Unavailable technician assign should be 409: %', v_resp;
    END IF;
    PERFORM solar_app.fn_update_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians/update',
        'jwt_token_hash', v_admin_hash,
        'technician_id', v_tech_id::TEXT,
        'is_available', true
    ));

    ------------------------------------------------------------------
    -- 6) Valid SR assignment + notifications
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/jobs/assign',
        'jwt_token_hash', v_admin_hash,
        'job_type', 'SERVICE_REQUEST',
        'technician_id', v_tech_id::TEXT,
        'service_request_id', v_sr_id::TEXT,
        'sequence_no', '1'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' OR (v_resp->>'code')::INT <> 200 THEN
        RAISE EXCEPTION 'Valid SR assignment failed: %', v_resp;
    END IF;
    v_job_id := (v_resp->'data'->>'job_id')::BIGINT;

    SELECT status_row.data_code, sr.technician_id
      INTO v_sr_status, v_assignee
      FROM solar_app.service_request_details sr
      JOIN solar_app.ref_data status_row ON status_row.ref_data_id = sr.status_ref_data_id
     WHERE sr.service_request_id = v_sr_id;
    IF v_sr_status <> 'SR_ASSIGNED' OR v_assignee IS DISTINCT FROM v_tech_id THEN
        RAISE EXCEPTION 'SR not marked assigned to technician';
    END IF;

    SELECT COUNT(*) INTO v_ntf_count
      FROM solar_app.notification_details n
      JOIN solar_app.ref_data t ON t.ref_data_id = n.notification_type_ref_data_id
     WHERE n.related_entity_id = v_job_id AND t.data_code = 'NTF_JOB_ASSIGNED';
    IF v_ntf_count < 1 THEN
        RAISE EXCEPTION 'NTF_JOB_ASSIGNED missing after SR assign';
    END IF;
    SELECT COUNT(*) INTO v_ntf_count
      FROM solar_app.notification_details n
      JOIN solar_app.ref_data t ON t.ref_data_id = n.notification_type_ref_data_id
     WHERE n.related_entity_id = v_sr_id AND t.data_code = 'NTF_SERVICE_REQUEST';
    IF v_ntf_count < 2 THEN
        RAISE EXCEPTION 'Expected tech+customer NTF_SERVICE_REQUEST rows, found %', v_ntf_count;
    END IF;

    ------------------------------------------------------------------
    -- 7) Duplicate active assignment prevention
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/jobs/assign',
        'jwt_token_hash', v_admin_hash,
        'job_type', 'SERVICE_REQUEST',
        'technician_id', v_tech_id::TEXT,
        'service_request_id', v_sr_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 409 THEN
        RAISE EXCEPTION 'Duplicate SR assignment should be 409: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 8) Valid site-visit assignment + notifications
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/jobs/assign',
        'jwt_token_hash', v_admin_hash,
        'job_type', 'SITE_VISIT',
        'technician_id', v_tech_id::TEXT,
        'site_visit_id', v_visit_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' OR (v_resp->>'code')::INT <> 200 THEN
        RAISE EXCEPTION 'Valid site-visit assignment failed: %', v_resp;
    END IF;

    SELECT status_row.data_code, visit.assigned_to_user_id
      INTO v_visit_status, v_assignee
      FROM solar_app.site_visit_details visit
      JOIN solar_app.ref_data status_row ON status_row.ref_data_id = visit.visit_status_ref_data_id
     WHERE visit.site_visit_id = v_visit_id;
    IF v_visit_status <> 'VISIT_ASSIGNED' OR v_assignee IS DISTINCT FROM v_tech_user_id THEN
        RAISE EXCEPTION 'Visit not assigned to technician user';
    END IF;

    SELECT COUNT(*) INTO v_ntf_count
      FROM solar_app.notification_details n
      JOIN solar_app.ref_data t ON t.ref_data_id = n.notification_type_ref_data_id
     WHERE n.related_entity_id = v_visit_id AND t.data_code = 'NTF_SITE_VISIT_ASSIGNED';
    IF v_ntf_count < 2 THEN
        RAISE EXCEPTION 'Expected tech+customer NTF_SITE_VISIT_ASSIGNED rows, found %', v_ntf_count;
    END IF;

    ------------------------------------------------------------------
    -- 9) Invalid references
    ------------------------------------------------------------------
    v_resp := solar_app.fn_create_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/jobs/assign',
        'jwt_token_hash', v_admin_hash,
        'job_type', 'SERVICE_REQUEST',
        'technician_id', v_tech_id::TEXT,
        'service_request_id', '999999999'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 404 THEN
        RAISE EXCEPTION 'Missing SR should be 404: %', v_resp;
    END IF;

    v_resp := solar_app.fn_create_technician_details(jsonb_build_object(
        'api_endpoint', '/api/admin/technicians/create',
        'jwt_token_hash', v_admin_hash,
        'country_id', '999999999',
        'national_number', '9900220099',
        'full_name', 'Bad Country',
        'employee_code', 'M7P1-EMP-BAD'
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 400 THEN
        RAISE EXCEPTION 'Invalid country should be 400: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 10) Notification failure rolls back assignment
    ------------------------------------------------------------------
    SELECT COUNT(*) INTO v_before_jobs FROM solar_app.job_assignment_details WHERE service_request_id = v_sr2_id;
    SELECT technician_id INTO v_before_sr_tech FROM solar_app.service_request_details WHERE service_request_id = v_sr2_id;

    SELECT r.active_ind INTO v_ntf_active
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'NOTIFICATION_TYPES' AND r.data_code = 'NTF_JOB_ASSIGNED';
    UPDATE solar_app.ref_data r
       SET active_ind = FALSE
      FROM solar_app.ref_data_categories c
     WHERE c.category_id = r.category_id
       AND c.category_code = 'NOTIFICATION_TYPES'
       AND r.data_code = 'NTF_JOB_ASSIGNED';

    v_resp := solar_app.fn_create_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/jobs/assign',
        'jwt_token_hash', v_admin_hash,
        'job_type', 'SERVICE_REQUEST',
        'technician_id', v_tech_id::TEXT,
        'service_request_id', v_sr2_id::TEXT
    ));

    UPDATE solar_app.ref_data r
       SET active_ind = COALESCE(v_ntf_active, TRUE)
      FROM solar_app.ref_data_categories c
     WHERE c.category_id = r.category_id
       AND c.category_code = 'NOTIFICATION_TYPES'
       AND r.data_code = 'NTF_JOB_ASSIGNED';

    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 500 THEN
        RAISE EXCEPTION 'Notification failure should return 500: %', v_resp;
    END IF;
    SELECT COUNT(*) INTO v_after_jobs FROM solar_app.job_assignment_details WHERE service_request_id = v_sr2_id;
    SELECT technician_id INTO v_after_sr_tech FROM solar_app.service_request_details WHERE service_request_id = v_sr2_id;
    IF v_after_jobs IS DISTINCT FROM v_before_jobs OR v_after_sr_tech IS DISTINCT FROM v_before_sr_tech THEN
        RAISE EXCEPTION 'Notification failure did not roll back SR/job changes';
    END IF;

    ------------------------------------------------------------------
    -- 11) Existing customer workflow untouched (second SR remains open/unassigned)
    ------------------------------------------------------------------
    SELECT status_row.data_code, sr.technician_id
      INTO v_sr_status, v_assignee
      FROM solar_app.service_request_details sr
      JOIN solar_app.ref_data status_row ON status_row.ref_data_id = sr.status_ref_data_id
     WHERE sr.service_request_id = v_sr2_id;
    IF v_sr_status <> 'SR_OPEN' OR v_assignee IS NOT NULL THEN
        RAISE EXCEPTION 'Unaffected customer SR was modified';
    END IF;

    -- Non-admin cannot assign either
    v_resp := solar_app.fn_create_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/admin/jobs/assign',
        'jwt_token_hash', v_customer_hash,
        'job_type', 'SERVICE_REQUEST',
        'technician_id', v_tech_id::TEXT,
        'service_request_id', v_sr2_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 403 THEN
        RAISE EXCEPTION 'Non-admin assign should be 403: %', v_resp;
    END IF;

    RAISE NOTICE 'M7 Phase 1 restore IT passed';
END $$;

-- Cleanup fixtures
BEGIN;

DELETE FROM solar_app.log_notification_delivery
 WHERE notification_id IN (
        SELECT notification_id FROM solar_app.notification_details
         WHERE created_by = 'M7P1_IT'
            OR recipient_user_id IN (
                SELECT user_id FROM solar_app.user_details
                 WHERE mobile_e164 LIKE '+91990022%' OR created_by = 'M7P1_IT'
            )
      );
DELETE FROM solar_app.notification_details
 WHERE created_by = 'M7P1_IT'
    OR recipient_user_id IN (
        SELECT user_id FROM solar_app.user_details
         WHERE mobile_e164 LIKE '+91990022%' OR created_by = 'M7P1_IT'
    );
DELETE FROM solar_app.job_assignment_details
 WHERE created_by = 'M7P1_IT'
    OR technician_id IN (
        SELECT technician_id FROM solar_app.technician_details WHERE created_by = 'M7P1_IT'
    )
    OR technician_id IN (
        SELECT technician_id FROM solar_app.technician_details
         WHERE user_id IN (SELECT user_id FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990022%')
    );
DELETE FROM solar_app.site_visit_details
 WHERE created_by = 'M7P1_IT' OR visit_no LIKE 'M7P1-SV-%';
DELETE FROM solar_app.service_request_details
 WHERE created_by = 'M7P1_IT' OR service_request_no LIKE 'M7P1-SR-%';
DELETE FROM solar_app.technician_details
 WHERE created_by = 'M7P1_IT'
    OR user_id IN (SELECT user_id FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990022%' OR created_by = 'M7P1_IT');
DELETE FROM solar_app.site_details
 WHERE created_by = 'M7P1_IT'
    OR customer_id IN (SELECT customer_id FROM solar_app.customer_details WHERE customer_code LIKE 'M7P1-CUST-%');
DELETE FROM solar_app.customer_details
 WHERE customer_code LIKE 'M7P1-CUST-%' OR created_by = 'M7P1_IT';
DELETE FROM solar_app.log_user_sessions
 WHERE jwt_token_hash LIKE 'bb22cc33%' OR created_by = 'M7P1_IT';
DELETE FROM solar_app.user_details
 WHERE mobile_e164 LIKE '+91990022%' OR created_by = 'M7P1_IT';

COMMIT;

SELECT 'M7_PHASE1_RESTORE_IT_COMPLETE' AS result;
