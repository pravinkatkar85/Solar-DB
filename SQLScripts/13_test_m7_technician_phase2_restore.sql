-- Isolated M7 Phase 2 technician job-execution tests for SolarDB_restore_check only.
-- Do not run against SolarDB.

\set ON_ERROR_STOP on

SELECT current_database() AS db, current_user AS usr;

DO $$
BEGIN
    IF current_database() IS DISTINCT FROM 'SolarDB_restore_check' THEN
        RAISE EXCEPTION 'Refuse to run M7 Phase 2 IT on database %', current_database();
    END IF;
END $$;

BEGIN;

DELETE FROM solar_app.log_notification_delivery
 WHERE notification_id IN (
        SELECT notification_id FROM solar_app.notification_details
         WHERE created_by = 'M7P2_IT'
            OR recipient_user_id IN (
                SELECT user_id FROM solar_app.user_details
                 WHERE mobile_e164 LIKE '+91990033%' OR created_by = 'M7P2_IT'
            )
      );
DELETE FROM solar_app.notification_details
 WHERE created_by = 'M7P2_IT'
    OR recipient_user_id IN (
        SELECT user_id FROM solar_app.user_details
         WHERE mobile_e164 LIKE '+91990033%' OR created_by = 'M7P2_IT'
    );
DELETE FROM solar_app.job_signoff_details
 WHERE job_id IN (SELECT job_id FROM solar_app.job_assignment_details WHERE created_by = 'M7P2_IT');
DELETE FROM solar_app.job_media_details
 WHERE job_id IN (SELECT job_id FROM solar_app.job_assignment_details WHERE created_by = 'M7P2_IT');
DELETE FROM solar_app.job_checklist_response_details
 WHERE job_id IN (SELECT job_id FROM solar_app.job_assignment_details WHERE created_by = 'M7P2_IT');
DELETE FROM solar_app.job_assignment_details WHERE created_by = 'M7P2_IT';
DELETE FROM solar_app.site_visit_details WHERE created_by = 'M7P2_IT' OR visit_no LIKE 'M7P2-SV-%';
DELETE FROM solar_app.service_request_details WHERE created_by = 'M7P2_IT' OR service_request_no LIKE 'M7P2-SR-%';
DELETE FROM solar_app.technician_details
 WHERE created_by = 'M7P2_IT'
    OR user_id IN (SELECT user_id FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990033%' OR created_by = 'M7P2_IT');
DELETE FROM solar_app.site_details
 WHERE created_by = 'M7P2_IT'
    OR customer_id IN (SELECT customer_id FROM solar_app.customer_details WHERE customer_code LIKE 'M7P2-CUST-%');
DELETE FROM solar_app.customer_details WHERE customer_code LIKE 'M7P2-CUST-%' OR created_by = 'M7P2_IT';
DELETE FROM solar_app.log_user_sessions WHERE jwt_token_hash LIKE 'cc33dd44%' OR created_by = 'M7P2_IT';
DELETE FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990033%' OR created_by = 'M7P2_IT';

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
    v_job_queued BIGINT;
    v_visit_scheduled BIGINT;
    v_visit_purpose BIGINT;
    v_service_type BIGINT;
    v_country_id BIGINT := 1;
    v_office_id BIGINT;
    v_currency CHAR(3);
    v_admin_id BIGINT;
    v_customer_user_id BIGINT;
    v_customer_id BIGINT;
    v_site_id BIGINT;
    v_tech1_user_id BIGINT;
    v_tech2_user_id BIGINT;
    v_tech1_id BIGINT;
    v_tech2_id BIGINT;
    v_sr1_id BIGINT;
    v_sr2_id BIGINT;
    v_visit_id BIGINT;
    v_job1_id BIGINT;
    v_job2_id BIGINT;
    v_job_visit_id BIGINT;
    v_admin_hash TEXT := 'cc33dd44ee55ff6677889900aaaabbbbccccddddeeeeffff00001111aa11bb22';
    v_customer_hash TEXT := 'cc33dd44ee55ff6677889900aaaabbbbccccddddeeeeffff00002222bb22cc33';
    v_tech1_hash TEXT := 'cc33dd44ee55ff6677889900aaaabbbbccccddddeeeeffff00003333cc33dd44';
    v_tech2_hash TEXT := 'cc33dd44ee55ff6677889900aaaabbbbccccddddeeeeffff00004444dd44ee55';
    v_resp JSONB;
    v_list JSONB;
    v_checklist JSONB;
    v_media JSONB;
    v_job_status TEXT;
    v_sr_status TEXT;
    v_visit_status TEXT;
    v_count INTEGER;
    v_before_completed TIMESTAMPTZ;
    v_after_completed TIMESTAMPTZ;
    v_before_media INTEGER;
    v_after_media INTEGER;
    v_ntf_active BOOLEAN;
    v_item_voc BIGINT;
    v_item_acdc BIGINT;
    v_item_clean BIGINT;
    v_item_inv BIGINT;
    v_customer_fn_def TEXT;
BEGIN
    SELECT ref_data_id INTO v_role_admin FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='USER_ROLES' AND r.data_code='ROLE_ADMIN' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_role_customer FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='USER_ROLES' AND r.data_code='ROLE_CUSTOMER' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_role_tech FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='USER_ROLES' AND r.data_code='ROLE_TECHNICIAN' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_acct_active FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='USER_ACCOUNT_STATUSES' AND r.data_code='ACCT_ACTIVE' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_reg_self FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='REGISTRATION_SOURCES' AND r.data_code='REG_SELF_APP' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_sr_open FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='SERVICE_REQUEST_STATUSES' AND r.data_code='SR_OPEN' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_sr_assigned FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='SERVICE_REQUEST_STATUSES' AND r.data_code='SR_ASSIGNED' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_job_queued FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='JOB_STATUSES' AND r.data_code='JOB_QUEUED' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_visit_scheduled FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='SITE_VISIT_STATUSES' AND r.data_code='VISIT_SCHEDULED' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_visit_purpose FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='SITE_VISIT_PURPOSES' AND r.data_code='VISIT_SERVICE' AND r.active_ind AND c.active_ind;
    SELECT ref_data_id INTO v_service_type FROM solar_app.ref_data r JOIN solar_app.ref_data_categories c ON c.category_id=r.category_id WHERE c.category_code='SERVICE_TYPES' AND r.active_ind AND c.active_ind ORDER BY r.ref_data_id LIMIT 1;
    SELECT office_location_id INTO v_office_id FROM solar_app.ref_office_locations WHERE active_ind IS TRUE ORDER BY office_location_id LIMIT 1;
    SELECT currency_code INTO v_currency FROM solar_app.ref_currencies WHERE active_ind IS TRUE ORDER BY currency_code LIMIT 1;
    SELECT checklist_item_id INTO v_item_voc FROM solar_app.ref_checklist_items WHERE job_type='SERVICE_REQUEST' AND item_code='VOC_ISC' AND active_ind;
    SELECT checklist_item_id INTO v_item_acdc FROM solar_app.ref_checklist_items WHERE job_type='SERVICE_REQUEST' AND item_code='ACDC_EARTH' AND active_ind;
    SELECT checklist_item_id INTO v_item_clean FROM solar_app.ref_checklist_items WHERE job_type='SERVICE_REQUEST' AND item_code='PANEL_CLEAN' AND active_ind;
    SELECT checklist_item_id INTO v_item_inv FROM solar_app.ref_checklist_items WHERE job_type='SERVICE_REQUEST' AND item_code='INV_LOGGER' AND active_ind;

    IF v_role_admin IS NULL OR v_role_customer IS NULL OR v_role_tech IS NULL OR v_acct_active IS NULL
       OR v_job_queued IS NULL OR v_sr_assigned IS NULL OR v_office_id IS NULL OR v_currency IS NULL
       OR v_item_voc IS NULL OR v_item_acdc IS NULL OR v_item_clean IS NULL OR v_item_inv IS NULL THEN
        RAISE EXCEPTION 'Missing M7 Phase 2 reference fixtures';
    END IF;

    IF to_regprocedure('solar_app.fn_create_notification_details(jsonb)') IS NULL
       OR to_regprocedure('solar_app.fn_get_job_assignment_details(jsonb)') IS NULL
       OR to_regprocedure('solar_app.fn_update_job_assignment_details(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'Required M7 Phase 2 functions are not installed on SolarDB_restore_check';
    END IF;

    -- Customer completion function must remain present and unmodified in contract wording
    IF to_regprocedure('solar_app.fn_update_site_visit_details(jsonb)') IS NOT NULL THEN
        v_customer_fn_def := pg_get_functiondef('solar_app.fn_update_site_visit_details(jsonb)'::regprocedure);
        IF position('This account cannot complete a site visit' IN v_customer_fn_def) = 0 THEN
            RAISE EXCEPTION 'Customer completion function contract text unexpected';
        END IF;
    END IF;

    INSERT INTO solar_app.user_details (country_id, mobile_e164, full_name, role_ref_data_id, pin_hash, admin_registered, account_status_ref_data_id, registration_source_ref_data_id, created_by, updated_by)
    VALUES (v_country_id, '+919900330001', 'M7P2 Admin', v_role_admin, NULL, TRUE, v_acct_active, v_reg_self, 'M7P2_IT', 'M7P2_IT')
    RETURNING user_id INTO v_admin_id;

    INSERT INTO solar_app.user_details (country_id, mobile_e164, full_name, role_ref_data_id, pin_hash, admin_registered, account_status_ref_data_id, registration_source_ref_data_id, created_by, updated_by)
    VALUES (v_country_id, '+919900330002', 'M7P2 Customer', v_role_customer, NULL, TRUE, v_acct_active, v_reg_self, 'M7P2_IT', 'M7P2_IT')
    RETURNING user_id INTO v_customer_user_id;

    INSERT INTO solar_app.customer_details (user_id, customer_code, billing_name, created_by, updated_by)
    VALUES (v_customer_user_id, 'M7P2-CUST-0001', 'M7P2 Customer', 'M7P2_IT', 'M7P2_IT')
    RETURNING customer_id INTO v_customer_id;

    INSERT INTO solar_app.site_details (customer_id, site_name, address_line1, created_by, updated_by)
    VALUES (v_customer_id, 'M7P2 Site', '2 M7 Lane', 'M7P2_IT', 'M7P2_IT')
    RETURNING site_id INTO v_site_id;

    INSERT INTO solar_app.user_details (country_id, mobile_e164, full_name, role_ref_data_id, pin_hash, admin_registered, account_status_ref_data_id, registration_source_ref_data_id, created_by, updated_by)
    VALUES (v_country_id, '+919900330003', 'M7P2 Tech One', v_role_tech, NULL, TRUE, v_acct_active, v_reg_self, 'M7P2_IT', 'M7P2_IT')
    RETURNING user_id INTO v_tech1_user_id;

    INSERT INTO solar_app.user_details (country_id, mobile_e164, full_name, role_ref_data_id, pin_hash, admin_registered, account_status_ref_data_id, registration_source_ref_data_id, created_by, updated_by)
    VALUES (v_country_id, '+919900330004', 'M7P2 Tech Two', v_role_tech, NULL, TRUE, v_acct_active, v_reg_self, 'M7P2_IT', 'M7P2_IT')
    RETURNING user_id INTO v_tech2_user_id;

    INSERT INTO solar_app.technician_details (user_id, employee_code, is_available, created_by, updated_by)
    VALUES (v_tech1_user_id, 'M7P2-EMP-001', TRUE, 'M7P2_IT', 'M7P2_IT')
    RETURNING technician_id INTO v_tech1_id;

    INSERT INTO solar_app.technician_details (user_id, employee_code, is_available, created_by, updated_by)
    VALUES (v_tech2_user_id, 'M7P2-EMP-002', TRUE, 'M7P2_IT', 'M7P2_IT')
    RETURNING technician_id INTO v_tech2_id;

    INSERT INTO solar_app.log_user_sessions (user_id, mobile_e164, jwt_token_hash, session_status, active_ind, created_by, updated_by)
    VALUES
        (v_admin_id, '+919900330001', v_admin_hash, 'ACTIVE', TRUE, 'M7P2_IT', 'M7P2_IT'),
        (v_customer_user_id, '+919900330002', v_customer_hash, 'ACTIVE', TRUE, 'M7P2_IT', 'M7P2_IT'),
        (v_tech1_user_id, '+919900330003', v_tech1_hash, 'ACTIVE', TRUE, 'M7P2_IT', 'M7P2_IT'),
        (v_tech2_user_id, '+919900330004', v_tech2_hash, 'ACTIVE', TRUE, 'M7P2_IT', 'M7P2_IT');

    INSERT INTO solar_app.service_request_details (
        service_request_no, site_id, customer_id, technician_id, service_type_ref_data_id,
        status_ref_data_id, preferred_on, created_by, updated_by
    ) VALUES (
        'M7P2-SR-0001', v_site_id, v_customer_id, v_tech1_id, v_service_type,
        v_sr_assigned, CURRENT_DATE + 1, 'M7P2_IT', 'M7P2_IT'
    ) RETURNING service_request_id INTO v_sr1_id;

    INSERT INTO solar_app.service_request_details (
        service_request_no, site_id, customer_id, technician_id, service_type_ref_data_id,
        status_ref_data_id, preferred_on, created_by, updated_by
    ) VALUES (
        'M7P2-SR-0002', v_site_id, v_customer_id, v_tech1_id, v_service_type,
        v_sr_assigned, CURRENT_DATE + 2, 'M7P2_IT', 'M7P2_IT'
    ) RETURNING service_request_id INTO v_sr2_id;

    INSERT INTO solar_app.site_visit_details (
        visit_no, visit_purpose_ref_data_id, customer_id, site_id, office_location_id,
        visit_status_ref_data_id, scheduled_on, charge_amount, currency_code, created_by, updated_by
    ) VALUES (
        'M7P2-SV-0001', v_visit_purpose, v_customer_id, v_site_id, v_office_id,
        v_visit_scheduled, CURRENT_DATE + 5, 0, v_currency, 'M7P2_IT', 'M7P2_IT'
    ) RETURNING site_visit_id INTO v_visit_id;

    INSERT INTO solar_app.job_assignment_details (
        job_type, site_id, technician_id, service_request_id, job_status_ref_data_id, scheduled_on, created_by, updated_by
    ) VALUES (
        'SERVICE_REQUEST', v_site_id, v_tech1_id, v_sr1_id, v_job_queued, CURRENT_DATE + 1, 'M7P2_IT', 'M7P2_IT'
    ) RETURNING job_id INTO v_job1_id;

    INSERT INTO solar_app.job_assignment_details (
        job_type, site_id, technician_id, service_request_id, job_status_ref_data_id, scheduled_on, created_by, updated_by
    ) VALUES (
        'SERVICE_REQUEST', v_site_id, v_tech1_id, v_sr2_id, v_job_queued, CURRENT_DATE + 2, 'M7P2_IT', 'M7P2_IT'
    ) RETURNING job_id INTO v_job2_id;

    INSERT INTO solar_app.job_assignment_details (
        job_type, site_id, technician_id, site_visit_id, job_status_ref_data_id, scheduled_on, created_by, updated_by
    ) VALUES (
        'SITE_VISIT', v_site_id, v_tech1_id, v_visit_id, v_job_queued, CURRENT_DATE + 5, 'M7P2_IT', 'M7P2_IT'
    ) RETURNING job_id INTO v_job_visit_id;

    ------------------------------------------------------------------
    -- 1) Technician sees only own jobs
    ------------------------------------------------------------------
    v_resp := solar_app.fn_get_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs',
        'jwt_token_hash', v_tech1_hash
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Tech1 list failed: %', v_resp;
    END IF;
    v_list := v_resp->'data'->'jobs';
    IF jsonb_array_length(v_list) < 3 THEN
        RAISE EXCEPTION 'Tech1 should see own jobs, found %', v_list;
    END IF;

    ------------------------------------------------------------------
    -- 2) Other technician cannot access job
    ------------------------------------------------------------------
    v_resp := solar_app.fn_get_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs',
        'jwt_token_hash', v_tech2_hash,
        'job_id', v_job1_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 404 THEN
        RAISE EXCEPTION 'Tech2 detail should be 404: %', v_resp;
    END IF;

    v_resp := solar_app.fn_update_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs/update',
        'jwt_token_hash', v_tech2_hash,
        'action', 'ACCEPT',
        'job_id', v_job1_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 404 THEN
        RAISE EXCEPTION 'Tech2 accept should be 404: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 3) Admin/customer cannot execute technician actions
    ------------------------------------------------------------------
    v_resp := solar_app.fn_get_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs',
        'jwt_token_hash', v_admin_hash
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 403 THEN
        RAISE EXCEPTION 'Admin get should be 403: %', v_resp;
    END IF;
    v_resp := solar_app.fn_update_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs/update',
        'jwt_token_hash', v_customer_hash,
        'action', 'ACCEPT',
        'job_id', v_job1_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 403 THEN
        RAISE EXCEPTION 'Customer update should be 403: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 4) Accept / reschedule / start lifecycle
    ------------------------------------------------------------------
    v_resp := solar_app.fn_update_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs/update',
        'jwt_token_hash', v_tech1_hash,
        'action', 'ACCEPT',
        'job_id', v_job1_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Accept failed: %', v_resp;
    END IF;

    v_resp := solar_app.fn_update_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs/update',
        'jwt_token_hash', v_tech1_hash,
        'action', 'RESCHEDULE',
        'job_id', v_job1_id::TEXT,
        'scheduled_on', (CURRENT_DATE + 7)::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 400 THEN
        RAISE EXCEPTION 'Missing reschedule reason should be 400: %', v_resp;
    END IF;

    v_resp := solar_app.fn_update_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs/update',
        'jwt_token_hash', v_tech1_hash,
        'action', 'RESCHEDULE',
        'job_id', v_job1_id::TEXT,
        'scheduled_on', (CURRENT_DATE + 7)::TEXT,
        'accept_reject_reason', 'Customer asked for later slot'
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Reschedule failed: %', v_resp;
    END IF;

    v_resp := solar_app.fn_update_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs/update',
        'jwt_token_hash', v_tech1_hash,
        'action', 'ACCEPT',
        'job_id', v_job1_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Re-accept after reschedule failed: %', v_resp;
    END IF;

    v_resp := solar_app.fn_update_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs/update',
        'jwt_token_hash', v_tech1_hash,
        'action', 'START',
        'job_id', v_job1_id::TEXT
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Start failed: %', v_resp;
    END IF;

    SELECT status_row.data_code INTO v_job_status
      FROM solar_app.job_assignment_details job
      JOIN solar_app.ref_data status_row ON status_row.ref_data_id = job.job_status_ref_data_id
     WHERE job.job_id = v_job1_id;
    SELECT status_row.data_code INTO v_sr_status
      FROM solar_app.service_request_details sr
      JOIN solar_app.ref_data status_row ON status_row.ref_data_id = sr.status_ref_data_id
     WHERE sr.service_request_id = v_sr1_id;
    IF v_job_status <> 'JOB_IN_PROGRESS' OR v_sr_status <> 'SR_IN_PROGRESS' THEN
        RAISE EXCEPTION 'Start sync unexpected job=% sr=%', v_job_status, v_sr_status;
    END IF;

    ------------------------------------------------------------------
    -- 5) Completion validation + success
    ------------------------------------------------------------------
    v_checklist := jsonb_build_array(
        jsonb_build_object('checklist_item_id', v_item_voc::TEXT, 'measured_value', '40.5'),
        jsonb_build_object('checklist_item_id', v_item_acdc::TEXT, 'is_pass', true),
        jsonb_build_object('checklist_item_id', v_item_clean::TEXT, 'is_pass', true),
        jsonb_build_object('checklist_item_id', v_item_inv::TEXT, 'is_pass', true)
    );
    v_media := jsonb_build_array(
        jsonb_build_object('media_purpose', 'BEFORE', 'file_url', 'https://example.test/before.jpg'),
        jsonb_build_object('media_purpose', 'AFTER', 'file_url', 'https://example.test/after.jpg')
    );

    -- missing checklist item
    v_resp := solar_app.fn_update_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs/update',
        'jwt_token_hash', v_tech1_hash,
        'action', 'COMPLETE',
        'job_id', v_job1_id::TEXT,
        'checklist_responses', jsonb_build_array(
            jsonb_build_object('checklist_item_id', v_item_voc::TEXT, 'measured_value', '40.5')
        ),
        'media', v_media,
        'signature', jsonb_build_object('signature_url', 'https://example.test/sign.png', 'signer_name', 'Customer')
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 400 THEN
        RAISE EXCEPTION 'Incomplete checklist should be 400: %', v_resp;
    END IF;

    -- missing after photo
    v_resp := solar_app.fn_update_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs/update',
        'jwt_token_hash', v_tech1_hash,
        'action', 'COMPLETE',
        'job_id', v_job1_id::TEXT,
        'checklist_responses', v_checklist,
        'media', jsonb_build_array(
            jsonb_build_object('media_purpose', 'BEFORE', 'file_url', 'https://example.test/before.jpg')
        ),
        'signature', jsonb_build_object('signature_url', 'https://example.test/sign.png')
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 400 THEN
        RAISE EXCEPTION 'Missing after photo should be 400: %', v_resp;
    END IF;

    -- missing signature
    v_resp := solar_app.fn_update_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs/update',
        'jwt_token_hash', v_tech1_hash,
        'action', 'COMPLETE',
        'job_id', v_job1_id::TEXT,
        'checklist_responses', v_checklist,
        'media', v_media
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 400 THEN
        RAISE EXCEPTION 'Missing signature should be 400: %', v_resp;
    END IF;

    v_resp := solar_app.fn_update_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs/update',
        'jwt_token_hash', v_tech1_hash,
        'action', 'COMPLETE',
        'job_id', v_job1_id::TEXT,
        'checklist_responses', v_checklist,
        'media', v_media,
        'signature', jsonb_build_object(
            'signature_url', 'https://example.test/sign.png',
            'signer_name', 'M7P2 Customer'
        )
    ));
    IF COALESCE(v_resp->>'status','') <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Successful completion failed: %', v_resp;
    END IF;

    SELECT status_row.data_code INTO v_job_status
      FROM solar_app.job_assignment_details job
      JOIN solar_app.ref_data status_row ON status_row.ref_data_id = job.job_status_ref_data_id
     WHERE job.job_id = v_job1_id;
    SELECT status_row.data_code INTO v_sr_status
      FROM solar_app.service_request_details sr
      JOIN solar_app.ref_data status_row ON status_row.ref_data_id = sr.status_ref_data_id
     WHERE sr.service_request_id = v_sr1_id;
    IF v_job_status <> 'JOB_COMPLETED' OR v_sr_status <> 'SR_COMPLETED' THEN
        RAISE EXCEPTION 'Complete sync unexpected job=% sr=%', v_job_status, v_sr_status;
    END IF;

    SELECT COUNT(*) INTO v_count
      FROM solar_app.job_checklist_response_details WHERE job_id=v_job1_id AND active_ind;
    IF v_count <> 4 THEN
        RAISE EXCEPTION 'Expected 4 checklist responses, found %', v_count;
    END IF;
    SELECT COUNT(*) INTO v_count
      FROM solar_app.job_media_details WHERE job_id=v_job1_id AND active_ind;
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'Expected 2 media rows, found %', v_count;
    END IF;
    SELECT COUNT(*) INTO v_count
      FROM solar_app.job_signoff_details WHERE job_id=v_job1_id AND active_ind;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'Expected 1 signoff, found %', v_count;
    END IF;
    SELECT COUNT(*) INTO v_count
      FROM solar_app.notification_details n
      JOIN solar_app.ref_data t ON t.ref_data_id = n.notification_type_ref_data_id
     WHERE n.related_entity_id = v_sr1_id AND t.data_code = 'NTF_SERVICE_REQUEST'
       AND n.recipient_user_id = v_customer_user_id;
    IF v_count < 1 THEN
        RAISE EXCEPTION 'Customer NTF_SERVICE_REQUEST on complete missing';
    END IF;

    ------------------------------------------------------------------
    -- 6) Duplicate completion prevented
    ------------------------------------------------------------------
    v_resp := solar_app.fn_update_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs/update',
        'jwt_token_hash', v_tech1_hash,
        'action', 'COMPLETE',
        'job_id', v_job1_id::TEXT,
        'checklist_responses', v_checklist,
        'media', v_media,
        'signature', jsonb_build_object('signature_url', 'https://example.test/sign2.png')
    ));
    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 409 THEN
        RAISE EXCEPTION 'Duplicate complete should be 409: %', v_resp;
    END IF;

    ------------------------------------------------------------------
    -- 7) Notification failure rolls back completion
    ------------------------------------------------------------------
    PERFORM solar_app.fn_update_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs/update',
        'jwt_token_hash', v_tech1_hash,
        'action', 'ACCEPT', 'job_id', v_job2_id::TEXT
    ));
    PERFORM solar_app.fn_update_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs/update',
        'jwt_token_hash', v_tech1_hash,
        'action', 'START', 'job_id', v_job2_id::TEXT
    ));

    SELECT completed_on INTO v_before_completed FROM solar_app.job_assignment_details WHERE job_id = v_job2_id;
    SELECT COUNT(*) INTO v_before_media FROM solar_app.job_media_details WHERE job_id = v_job2_id AND active_ind;

    SELECT r.active_ind INTO v_ntf_active
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'NOTIFICATION_TYPES' AND r.data_code = 'NTF_SERVICE_REQUEST';
    UPDATE solar_app.ref_data r
       SET active_ind = FALSE
      FROM solar_app.ref_data_categories c
     WHERE c.category_id = r.category_id
       AND c.category_code = 'NOTIFICATION_TYPES'
       AND r.data_code = 'NTF_SERVICE_REQUEST';

    v_resp := solar_app.fn_update_job_assignment_details(jsonb_build_object(
        'api_endpoint', '/api/technician/jobs/update',
        'jwt_token_hash', v_tech1_hash,
        'action', 'COMPLETE',
        'job_id', v_job2_id::TEXT,
        'checklist_responses', v_checklist,
        'media', v_media,
        'signature', jsonb_build_object('signature_url', 'https://example.test/sign-rollback.png')
    ));

    UPDATE solar_app.ref_data r
       SET active_ind = COALESCE(v_ntf_active, TRUE)
      FROM solar_app.ref_data_categories c
     WHERE c.category_id = r.category_id
       AND c.category_code = 'NOTIFICATION_TYPES'
       AND r.data_code = 'NTF_SERVICE_REQUEST';

    IF COALESCE(v_resp->>'status','') <> 'ERROR' OR (v_resp->>'code')::INT <> 500 THEN
        RAISE EXCEPTION 'Notification failure should be 500: %', v_resp;
    END IF;
    SELECT completed_on INTO v_after_completed FROM solar_app.job_assignment_details WHERE job_id = v_job2_id;
    SELECT COUNT(*) INTO v_after_media FROM solar_app.job_media_details WHERE job_id = v_job2_id AND active_ind;
    SELECT status_row.data_code INTO v_job_status
      FROM solar_app.job_assignment_details job
      JOIN solar_app.ref_data status_row ON status_row.ref_data_id = job.job_status_ref_data_id
     WHERE job.job_id = v_job2_id;
    IF v_after_completed IS DISTINCT FROM v_before_completed
       OR v_after_media IS DISTINCT FROM v_before_media
       OR v_job_status <> 'JOB_IN_PROGRESS' THEN
        RAISE EXCEPTION 'Notification failure did not roll back completion';
    END IF;

    ------------------------------------------------------------------
    -- 8) Existing customer completion flow remains unchanged (function intact)
    ------------------------------------------------------------------
    IF to_regprocedure('solar_app.fn_update_site_visit_details(jsonb)') IS NOT NULL THEN
        v_customer_fn_def := pg_get_functiondef('solar_app.fn_update_site_visit_details(jsonb)'::regprocedure);
        IF position('This account cannot complete a site visit' IN v_customer_fn_def) = 0
           OR position('This service request can no longer be changed' IN v_customer_fn_def) = 0 THEN
            RAISE EXCEPTION 'Customer completion function body changed unexpectedly';
        END IF;
    END IF;

    -- Open SR without tech job remains available for customer path statuses
    INSERT INTO solar_app.service_request_details (
        service_request_no, site_id, customer_id, service_type_ref_data_id,
        status_ref_data_id, preferred_on, created_by, updated_by
    ) VALUES (
        'M7P2-SR-OPEN', v_site_id, v_customer_id, v_service_type,
        v_sr_open, CURRENT_DATE + 10, 'M7P2_IT', 'M7P2_IT'
    );
    SELECT status_row.data_code INTO v_sr_status
      FROM solar_app.service_request_details sr
      JOIN solar_app.ref_data status_row ON status_row.ref_data_id = sr.status_ref_data_id
     WHERE sr.service_request_no = 'M7P2-SR-OPEN';
    IF v_sr_status <> 'SR_OPEN' THEN
        RAISE EXCEPTION 'Unaffected open SR was modified';
    END IF;

    RAISE NOTICE 'M7 Phase 2 restore IT passed';
END $$;

BEGIN;

DELETE FROM solar_app.log_notification_delivery
 WHERE notification_id IN (
        SELECT notification_id FROM solar_app.notification_details
         WHERE created_by = 'M7P2_IT'
            OR recipient_user_id IN (
                SELECT user_id FROM solar_app.user_details
                 WHERE mobile_e164 LIKE '+91990033%' OR created_by = 'M7P2_IT'
            )
      );
DELETE FROM solar_app.notification_details
 WHERE created_by = 'M7P2_IT'
    OR recipient_user_id IN (
        SELECT user_id FROM solar_app.user_details
         WHERE mobile_e164 LIKE '+91990033%' OR created_by = 'M7P2_IT'
    );
DELETE FROM solar_app.job_signoff_details
 WHERE job_id IN (SELECT job_id FROM solar_app.job_assignment_details WHERE created_by = 'M7P2_IT');
DELETE FROM solar_app.job_media_details
 WHERE job_id IN (SELECT job_id FROM solar_app.job_assignment_details WHERE created_by = 'M7P2_IT');
DELETE FROM solar_app.job_checklist_response_details
 WHERE job_id IN (SELECT job_id FROM solar_app.job_assignment_details WHERE created_by = 'M7P2_IT');
DELETE FROM solar_app.job_assignment_details WHERE created_by = 'M7P2_IT';
DELETE FROM solar_app.site_visit_details WHERE created_by = 'M7P2_IT' OR visit_no LIKE 'M7P2-SV-%';
DELETE FROM solar_app.service_request_details WHERE created_by = 'M7P2_IT' OR service_request_no LIKE 'M7P2-SR-%';
DELETE FROM solar_app.technician_details
 WHERE created_by = 'M7P2_IT'
    OR user_id IN (SELECT user_id FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990033%' OR created_by = 'M7P2_IT');
DELETE FROM solar_app.site_details
 WHERE created_by = 'M7P2_IT'
    OR customer_id IN (SELECT customer_id FROM solar_app.customer_details WHERE customer_code LIKE 'M7P2-CUST-%');
DELETE FROM solar_app.customer_details WHERE customer_code LIKE 'M7P2-CUST-%' OR created_by = 'M7P2_IT';
DELETE FROM solar_app.log_user_sessions WHERE jwt_token_hash LIKE 'cc33dd44%' OR created_by = 'M7P2_IT';
DELETE FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990033%' OR created_by = 'M7P2_IT';

COMMIT;

SELECT 'M7_PHASE2_RESTORE_IT_COMPLETE' AS result;
