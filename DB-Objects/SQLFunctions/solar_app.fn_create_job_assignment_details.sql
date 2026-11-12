-- Admin assigns an active SERVICE_REQUEST or SITE_VISIT to an active available technician.
-- Creates job_assignment_details in JOB_QUEUED and enqueues NTF_JOB_ASSIGNED.
-- SERVICE_REQUEST also notifies via NTF_SERVICE_REQUEST; SITE_VISIT via NTF_SITE_VISIT_ASSIGNED.
-- Session identity and ROLE_ADMIN come only from jwt_token_hash → log_user_sessions.
-- Payload role, assigned user id, and ownership fields are not trusted.
-- Does not modify customer booking or customer visit-completion functions.
-- Do not install this file until separately approved.

CREATE OR REPLACE FUNCTION solar_app.fn_create_job_assignment_details(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = pg_catalog, solar_app
AS $$
DECLARE
    v_started               TIMESTAMPTZ := clock_timestamp();
    v_api_endpoint          VARCHAR(255);
    v_actor                 VARCHAR(50) := 'SYSTEM';
    v_status                VARCHAR(20) := 'SUCCESS';
    v_code                  INTEGER := 200;
    v_message               TEXT := 'Job assigned';
    v_data                  JSONB := NULL;
    v_response              JSONB;
    v_log_error             TEXT;
    v_sql_state             VARCHAR(10);
    v_token_hash            TEXT;
    v_session_count         INTEGER := 0;
    v_session_id            BIGINT;
    v_admin_user_id         BIGINT;
    v_active                BOOLEAN;
    v_account_code          VARCHAR(50);
    v_role_code             VARCHAR(50);
    v_claimed               TEXT;
    v_job_type              TEXT;
    v_tech_text             TEXT;
    v_technician_id         BIGINT;
    v_tech_user_id          BIGINT;
    v_tech_active           BOOLEAN;
    v_tech_available        BOOLEAN;
    v_tech_user_active      BOOLEAN;
    v_tech_account_code     VARCHAR(50);
    v_parent_text           TEXT;
    v_service_request_id    BIGINT;
    v_site_visit_id         BIGINT;
    v_site_id               BIGINT;
    v_customer_id           BIGINT;
    v_parent_status_code    VARCHAR(50);
    v_scheduled_on          DATE;
    v_date_text             TEXT;
    v_sequence_text         TEXT;
    v_sequence_no           INTEGER;
    v_job_status_id         BIGINT;
    v_sr_assigned_id        BIGINT;
    v_visit_assigned_id     BIGINT;
    v_job_id                BIGINT;
    v_updated               INTEGER := 0;
    v_dup_count             INTEGER := 0;
    v_customer_user_id      BIGINT;
    v_customer_active       BOOLEAN;
    v_customer_account      VARCHAR(50);
    v_ntf_response          JSONB;
    v_job_notification_id   TEXT;
    v_extra_notification_ids JSONB := '[]'::jsonb;
    v_visit_found           BOOLEAN := FALSE;
BEGIN
    <<body>>
    BEGIN
        IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Payload must be a JSON object';
            EXIT body;
        END IF;

        v_api_endpoint := NULLIF(btrim(p_payload->>'api_endpoint'), '');
        IF v_api_endpoint IS NULL OR char_length(v_api_endpoint) > 255 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'api_endpoint is required and must be 255 characters or fewer';
            EXIT body;
        END IF;

        v_token_hash := COALESCE(p_payload->>'jwt_token_hash', '');
        IF v_token_hash !~ '^[a-f0-9]{64}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Session token is not valid';
            EXIT body;
        END IF;

        SELECT COUNT(*)
          INTO v_session_count
          FROM solar_app.log_user_sessions AS session
         WHERE session.jwt_token_hash = v_token_hash
           AND session.session_status = 'ACTIVE'
           AND session.active_ind IS TRUE
           AND session.user_id IS NOT NULL;

        IF v_session_count IS DISTINCT FROM 1 THEN
            v_status := 'ERROR';
            v_code := 401;
            v_message := 'Authentication is required';
            EXIT body;
        END IF;

        SELECT session.session_id, session.user_id
          INTO v_session_id, v_admin_user_id
          FROM solar_app.log_user_sessions AS session
         WHERE session.jwt_token_hash = v_token_hash
           AND session.session_status = 'ACTIVE'
           AND session.active_ind IS TRUE
           AND session.user_id IS NOT NULL;

        v_actor := v_admin_user_id::TEXT;
        v_claimed := NULLIF(btrim(p_payload->>'logged_in_user_id'), '');
        IF v_claimed IS NOT NULL AND v_claimed IS DISTINCT FROM v_actor THEN
            v_status := 'ERROR';
            v_code := 401;
            v_message := 'Authentication is required';
            EXIT body;
        END IF;
        v_claimed := NULLIF(btrim(p_payload->>'user_id'), '');
        IF v_claimed IS NOT NULL AND v_claimed IS DISTINCT FROM v_actor THEN
            v_status := 'ERROR';
            v_code := 401;
            v_message := 'Authentication is required';
            EXIT body;
        END IF;

        SELECT app_user.active_ind, account_row.data_code, role_row.data_code
          INTO v_active, v_account_code, v_role_code
          FROM solar_app.user_details AS app_user
          LEFT JOIN solar_app.ref_data AS account_row
            ON account_row.ref_data_id = app_user.account_status_ref_data_id
          LEFT JOIN solar_app.ref_data AS role_row
            ON role_row.ref_data_id = app_user.role_ref_data_id
         WHERE app_user.user_id = v_admin_user_id;

        IF NOT FOUND OR v_active IS NOT TRUE OR v_account_code = 'ACCT_SUSPENDED' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'This account cannot assign jobs';
            EXIT body;
        END IF;
        IF v_role_code IS DISTINCT FROM 'ROLE_ADMIN' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'Only an administrator can assign jobs';
            EXIT body;
        END IF;

        v_job_type := upper(NULLIF(btrim(COALESCE(p_payload->>'job_type', '')), ''));
        IF v_job_type NOT IN ('SERVICE_REQUEST', 'SITE_VISIT') THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'job_type must be SERVICE_REQUEST or SITE_VISIT';
            EXIT body;
        END IF;

        v_tech_text := NULLIF(btrim(COALESCE(p_payload->>'technician_id', '')), '');
        IF v_tech_text IS NULL OR v_tech_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'technician_id is required';
            EXIT body;
        END IF;
        v_technician_id := v_tech_text::BIGINT;

        SELECT tech.user_id,
               tech.active_ind,
               tech.is_available,
               app_user.active_ind,
               account_row.data_code
          INTO v_tech_user_id,
               v_tech_active,
               v_tech_available,
               v_tech_user_active,
               v_tech_account_code
          FROM solar_app.technician_details AS tech
          JOIN solar_app.user_details AS app_user
            ON app_user.user_id = tech.user_id
          JOIN solar_app.ref_data AS role_row
            ON role_row.ref_data_id = app_user.role_ref_data_id
          LEFT JOIN solar_app.ref_data AS account_row
            ON account_row.ref_data_id = app_user.account_status_ref_data_id
         WHERE tech.technician_id = v_technician_id
           AND role_row.data_code = 'ROLE_TECHNICIAN';

        IF v_tech_user_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This technician was not found';
            EXIT body;
        END IF;
        IF v_tech_active IS NOT TRUE
           OR v_tech_user_active IS NOT TRUE
           OR v_tech_account_code = 'ACCT_SUSPENDED'
           OR v_tech_available IS NOT TRUE THEN
            v_status := 'ERROR';
            v_code := 409;
            v_message := 'This technician is not available for assignment';
            EXIT body;
        END IF;

        v_date_text := NULLIF(btrim(COALESCE(p_payload->>'scheduled_on', '')), '');
        IF v_date_text IS NOT NULL THEN
            BEGIN
                v_scheduled_on := v_date_text::DATE;
            EXCEPTION
                WHEN OTHERS THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'scheduled_on is not valid';
                    EXIT body;
            END;
        END IF;

        v_sequence_text := NULLIF(btrim(COALESCE(p_payload->>'sequence_no', '')), '');
        IF v_sequence_text IS NOT NULL THEN
            IF v_sequence_text !~ '^[0-9]{1,9}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'sequence_no is not valid';
                EXIT body;
            END IF;
            v_sequence_no := v_sequence_text::INTEGER;
        END IF;

        SELECT ref_row.ref_data_id
          INTO v_job_status_id
          FROM solar_app.ref_data AS ref_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = ref_row.category_id
         WHERE category.category_code = 'JOB_STATUSES'
           AND ref_row.data_code = 'JOB_QUEUED'
           AND category.active_ind IS TRUE
           AND ref_row.active_ind IS TRUE;
        IF v_job_status_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Job could not be assigned';
            v_log_error := 'JOB_QUEUED is not configured';
            EXIT body;
        END IF;

        IF v_job_type = 'SERVICE_REQUEST' THEN
            SELECT ref_row.ref_data_id
              INTO v_sr_assigned_id
              FROM solar_app.ref_data AS ref_row
              JOIN solar_app.ref_data_categories AS category
                ON category.category_id = ref_row.category_id
             WHERE category.category_code = 'SERVICE_REQUEST_STATUSES'
               AND ref_row.data_code = 'SR_ASSIGNED'
               AND category.active_ind IS TRUE
               AND ref_row.active_ind IS TRUE;
            IF v_sr_assigned_id IS NULL THEN
                v_status := 'ERROR';
                v_code := 500;
                v_message := 'Job could not be assigned';
                v_log_error := 'SR_ASSIGNED is not configured';
                EXIT body;
            END IF;

            v_parent_text := NULLIF(btrim(COALESCE(p_payload->>'service_request_id', '')), '');
            IF v_parent_text IS NULL OR v_parent_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'service_request_id is required';
                EXIT body;
            END IF;
            v_service_request_id := v_parent_text::BIGINT;

            SELECT sr.site_id,
                   sr.customer_id,
                   status_row.data_code,
                   COALESCE(v_scheduled_on, sr.preferred_on)
              INTO v_site_id, v_customer_id, v_parent_status_code, v_scheduled_on
              FROM solar_app.service_request_details AS sr
              JOIN solar_app.ref_data AS status_row
                ON status_row.ref_data_id = sr.status_ref_data_id
             WHERE sr.service_request_id = v_service_request_id
               AND sr.active_ind IS TRUE;
            IF v_site_id IS NULL THEN
                v_status := 'ERROR';
                v_code := 404;
                v_message := 'This service request was not found';
                EXIT body;
            END IF;
            IF v_parent_status_code NOT IN ('SR_OPEN', 'SR_ASSIGNED') THEN
                v_status := 'ERROR';
                v_code := 409;
                v_message := 'This service request cannot be assigned in its current status';
                EXIT body;
            END IF;
            IF v_scheduled_on IS NULL THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'scheduled_on is required when the service request has no preferred date';
                EXIT body;
            END IF;

            SELECT COUNT(*)
              INTO v_dup_count
              FROM solar_app.job_assignment_details AS job
              JOIN solar_app.ref_data AS status_row
                ON status_row.ref_data_id = job.job_status_ref_data_id
             WHERE job.active_ind IS TRUE
               AND job.service_request_id = v_service_request_id
               AND status_row.data_code IN (
                   'JOB_QUEUED', 'JOB_ACCEPTED', 'JOB_RESCHEDULED', 'JOB_IN_PROGRESS'
               );
            IF v_dup_count > 0 THEN
                v_status := 'ERROR';
                v_code := 409;
                v_message := 'An active job already exists for this service request';
                EXIT body;
            END IF;

            UPDATE solar_app.service_request_details AS sr
               SET technician_id = v_technician_id,
                   status_ref_data_id = v_sr_assigned_id,
                   updated_by = v_actor,
                   updated_on = clock_timestamp()
             WHERE sr.service_request_id = v_service_request_id
               AND sr.active_ind IS TRUE;
            GET DIAGNOSTICS v_updated = ROW_COUNT;
            IF v_updated IS DISTINCT FROM 1 THEN
                v_status := 'ERROR';
                v_code := 404;
                v_message := 'This service request was not found';
                EXIT body;
            END IF;
        ELSE
            SELECT ref_row.ref_data_id
              INTO v_visit_assigned_id
              FROM solar_app.ref_data AS ref_row
              JOIN solar_app.ref_data_categories AS category
                ON category.category_id = ref_row.category_id
             WHERE category.category_code = 'SITE_VISIT_STATUSES'
               AND ref_row.data_code = 'VISIT_ASSIGNED'
               AND category.active_ind IS TRUE
               AND ref_row.active_ind IS TRUE;
            IF v_visit_assigned_id IS NULL THEN
                v_status := 'ERROR';
                v_code := 500;
                v_message := 'Job could not be assigned';
                v_log_error := 'VISIT_ASSIGNED is not configured';
                EXIT body;
            END IF;

            v_parent_text := NULLIF(btrim(COALESCE(p_payload->>'site_visit_id', '')), '');
            IF v_parent_text IS NULL OR v_parent_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'site_visit_id is required';
                EXIT body;
            END IF;
            v_site_visit_id := v_parent_text::BIGINT;

            SELECT visit.site_id,
                   visit.customer_id,
                   status_row.data_code,
                   COALESCE(v_scheduled_on, visit.scheduled_on),
                   TRUE
              INTO v_site_id, v_customer_id, v_parent_status_code, v_scheduled_on, v_visit_found
              FROM solar_app.site_visit_details AS visit
              JOIN solar_app.ref_data AS status_row
                ON status_row.ref_data_id = visit.visit_status_ref_data_id
             WHERE visit.site_visit_id = v_site_visit_id
               AND visit.active_ind IS TRUE;
            IF v_visit_found IS NOT TRUE THEN
                v_status := 'ERROR';
                v_code := 404;
                v_message := 'This site visit was not found';
                EXIT body;
            END IF;
            IF v_site_id IS NULL THEN
                v_status := 'ERROR';
                v_code := 409;
                v_message := 'This site visit has no site and cannot create a technician job';
                EXIT body;
            END IF;
            IF v_parent_status_code NOT IN ('VISIT_SCHEDULED', 'VISIT_ASSIGNED') THEN
                v_status := 'ERROR';
                v_code := 409;
                v_message := 'This site visit cannot be assigned in its current status';
                EXIT body;
            END IF;

            SELECT COUNT(*)
              INTO v_dup_count
              FROM solar_app.job_assignment_details AS job
              JOIN solar_app.ref_data AS status_row
                ON status_row.ref_data_id = job.job_status_ref_data_id
             WHERE job.active_ind IS TRUE
               AND job.site_visit_id = v_site_visit_id
               AND status_row.data_code IN (
                   'JOB_QUEUED', 'JOB_ACCEPTED', 'JOB_RESCHEDULED', 'JOB_IN_PROGRESS'
               );
            IF v_dup_count > 0 THEN
                v_status := 'ERROR';
                v_code := 409;
                v_message := 'An active job already exists for this site visit';
                EXIT body;
            END IF;

            UPDATE solar_app.site_visit_details AS visit
               SET assigned_to_user_id = v_tech_user_id,
                   visit_status_ref_data_id = v_visit_assigned_id,
                   updated_by = v_actor,
                   updated_on = clock_timestamp()
             WHERE visit.site_visit_id = v_site_visit_id
               AND visit.active_ind IS TRUE;
            GET DIAGNOSTICS v_updated = ROW_COUNT;
            IF v_updated IS DISTINCT FROM 1 THEN
                v_status := 'ERROR';
                v_code := 404;
                v_message := 'This site visit was not found';
                EXIT body;
            END IF;
        END IF;

        INSERT INTO solar_app.job_assignment_details (
            job_type,
            site_id,
            technician_id,
            service_request_id,
            site_visit_id,
            job_status_ref_data_id,
            scheduled_on,
            sequence_no,
            created_by,
            updated_by
        ) VALUES (
            v_job_type,
            v_site_id,
            v_technician_id,
            v_service_request_id,
            v_site_visit_id,
            v_job_status_id,
            v_scheduled_on,
            v_sequence_no,
            v_actor,
            v_actor
        )
        RETURNING job_id INTO v_job_id;

        v_ntf_response := solar_app.fn_create_notification_details(
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'logged_in_user_id', v_actor,
                'recipient_user_id', v_tech_user_id::TEXT,
                'notification_type_code', 'NTF_JOB_ASSIGNED',
                'title', 'Job assigned',
                'body', 'A new field job was assigned to you.',
                'related_entity_type', 'JOB',
                'related_entity_id', v_job_id::TEXT,
                'payload_json', jsonb_build_object(
                    'entity_type', 'JOB',
                    'entity_id', v_job_id::TEXT,
                    'job_type', v_job_type,
                    'technician_id', v_technician_id::TEXT
                )
            ))
        );
        IF COALESCE(v_ntf_response->>'status', 'ERROR') IS DISTINCT FROM 'SUCCESS' THEN
            RAISE EXCEPTION 'Notification enqueue failed (NTF_JOB_ASSIGNED): %',
                COALESCE(v_ntf_response->>'message', 'unknown error')
                USING ERRCODE = 'P0001';
        END IF;
        v_job_notification_id := v_ntf_response->'data'->>'notification_id';

        IF v_job_type = 'SERVICE_REQUEST' THEN
            v_ntf_response := solar_app.fn_create_notification_details(
                jsonb_strip_nulls(jsonb_build_object(
                    'api_endpoint', v_api_endpoint,
                    'logged_in_user_id', v_actor,
                    'recipient_user_id', v_tech_user_id::TEXT,
                    'notification_type_code', 'NTF_SERVICE_REQUEST',
                    'title', 'Service request assigned',
                    'body', 'A service request was assigned to you.',
                    'related_entity_type', 'SERVICE_REQUEST',
                    'related_entity_id', v_service_request_id::TEXT,
                    'payload_json', jsonb_build_object(
                        'entity_type', 'SERVICE_REQUEST',
                        'entity_id', v_service_request_id::TEXT,
                        'job_id', v_job_id::TEXT
                    )
                ))
            );
            IF COALESCE(v_ntf_response->>'status', 'ERROR') IS DISTINCT FROM 'SUCCESS' THEN
                RAISE EXCEPTION 'Notification enqueue failed (NTF_SERVICE_REQUEST): %',
                    COALESCE(v_ntf_response->>'message', 'unknown error')
                    USING ERRCODE = 'P0001';
            END IF;
            v_extra_notification_ids := v_extra_notification_ids
                || jsonb_build_array(v_ntf_response->'data'->>'notification_id');

            IF v_customer_id IS NOT NULL THEN
                SELECT customer.user_id, app_user.active_ind, account_row.data_code
                  INTO v_customer_user_id, v_customer_active, v_customer_account
                  FROM solar_app.customer_details AS customer
                  JOIN solar_app.user_details AS app_user
                    ON app_user.user_id = customer.user_id
                  LEFT JOIN solar_app.ref_data AS account_row
                    ON account_row.ref_data_id = app_user.account_status_ref_data_id
                 WHERE customer.customer_id = v_customer_id
                   AND customer.active_ind IS TRUE;
                IF v_customer_user_id IS NOT NULL
                   AND v_customer_active IS TRUE
                   AND v_customer_account IS DISTINCT FROM 'ACCT_SUSPENDED' THEN
                    v_ntf_response := solar_app.fn_create_notification_details(
                        jsonb_strip_nulls(jsonb_build_object(
                            'api_endpoint', v_api_endpoint,
                            'logged_in_user_id', v_actor,
                            'recipient_user_id', v_customer_user_id::TEXT,
                            'notification_type_code', 'NTF_SERVICE_REQUEST',
                            'title', 'Service request assigned',
                            'body', 'A technician was assigned to your service request.',
                            'related_entity_type', 'SERVICE_REQUEST',
                            'related_entity_id', v_service_request_id::TEXT,
                            'payload_json', jsonb_build_object(
                                'entity_type', 'SERVICE_REQUEST',
                                'entity_id', v_service_request_id::TEXT,
                                'job_id', v_job_id::TEXT
                            )
                        ))
                    );
                    IF COALESCE(v_ntf_response->>'status', 'ERROR') IS DISTINCT FROM 'SUCCESS' THEN
                        RAISE EXCEPTION 'Notification enqueue failed (NTF_SERVICE_REQUEST customer): %',
                            COALESCE(v_ntf_response->>'message', 'unknown error')
                            USING ERRCODE = 'P0001';
                    END IF;
                    v_extra_notification_ids := v_extra_notification_ids
                        || jsonb_build_array(v_ntf_response->'data'->>'notification_id');
                END IF;
            END IF;
        ELSE
            v_ntf_response := solar_app.fn_create_notification_details(
                jsonb_strip_nulls(jsonb_build_object(
                    'api_endpoint', v_api_endpoint,
                    'logged_in_user_id', v_actor,
                    'recipient_user_id', v_tech_user_id::TEXT,
                    'notification_type_code', 'NTF_SITE_VISIT_ASSIGNED',
                    'title', 'Site visit assigned',
                    'body', 'A site visit was assigned to you.',
                    'related_entity_type', 'SITE_VISIT',
                    'related_entity_id', v_site_visit_id::TEXT,
                    'payload_json', jsonb_build_object(
                        'entity_type', 'SITE_VISIT',
                        'entity_id', v_site_visit_id::TEXT,
                        'job_id', v_job_id::TEXT
                    )
                ))
            );
            IF COALESCE(v_ntf_response->>'status', 'ERROR') IS DISTINCT FROM 'SUCCESS' THEN
                RAISE EXCEPTION 'Notification enqueue failed (NTF_SITE_VISIT_ASSIGNED): %',
                    COALESCE(v_ntf_response->>'message', 'unknown error')
                    USING ERRCODE = 'P0001';
            END IF;
            v_extra_notification_ids := v_extra_notification_ids
                || jsonb_build_array(v_ntf_response->'data'->>'notification_id');

            IF v_customer_id IS NOT NULL THEN
                SELECT customer.user_id, app_user.active_ind, account_row.data_code
                  INTO v_customer_user_id, v_customer_active, v_customer_account
                  FROM solar_app.customer_details AS customer
                  JOIN solar_app.user_details AS app_user
                    ON app_user.user_id = customer.user_id
                  LEFT JOIN solar_app.ref_data AS account_row
                    ON account_row.ref_data_id = app_user.account_status_ref_data_id
                 WHERE customer.customer_id = v_customer_id
                   AND customer.active_ind IS TRUE;
                IF v_customer_user_id IS NOT NULL
                   AND v_customer_active IS TRUE
                   AND v_customer_account IS DISTINCT FROM 'ACCT_SUSPENDED' THEN
                    v_ntf_response := solar_app.fn_create_notification_details(
                        jsonb_strip_nulls(jsonb_build_object(
                            'api_endpoint', v_api_endpoint,
                            'logged_in_user_id', v_actor,
                            'recipient_user_id', v_customer_user_id::TEXT,
                            'notification_type_code', 'NTF_SITE_VISIT_ASSIGNED',
                            'title', 'Site visit assigned',
                            'body', 'A technician was assigned to your site visit.',
                            'related_entity_type', 'SITE_VISIT',
                            'related_entity_id', v_site_visit_id::TEXT,
                            'payload_json', jsonb_build_object(
                                'entity_type', 'SITE_VISIT',
                                'entity_id', v_site_visit_id::TEXT,
                                'job_id', v_job_id::TEXT
                            )
                        ))
                    );
                    IF COALESCE(v_ntf_response->>'status', 'ERROR') IS DISTINCT FROM 'SUCCESS' THEN
                        RAISE EXCEPTION 'Notification enqueue failed (NTF_SITE_VISIT_ASSIGNED customer): %',
                            COALESCE(v_ntf_response->>'message', 'unknown error')
                            USING ERRCODE = 'P0001';
                    END IF;
                    v_extra_notification_ids := v_extra_notification_ids
                        || jsonb_build_array(v_ntf_response->'data'->>'notification_id');
                END IF;
            END IF;
        END IF;

        v_data := jsonb_strip_nulls(jsonb_build_object(
            'job_id', v_job_id::TEXT,
            'job_type', v_job_type,
            'job_status_code', 'JOB_QUEUED',
            'technician_id', v_technician_id::TEXT,
            'technician_user_id', v_tech_user_id::TEXT,
            'site_id', v_site_id::TEXT,
            'service_request_id', CASE WHEN v_service_request_id IS NULL THEN NULL ELSE v_service_request_id::TEXT END,
            'site_visit_id', CASE WHEN v_site_visit_id IS NULL THEN NULL ELSE v_site_visit_id::TEXT END,
            'scheduled_on', v_scheduled_on::TEXT,
            'sequence_no', v_sequence_no,
            'notification_id', v_job_notification_id,
            'related_notification_ids', v_extra_notification_ids
        ));
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Job could not be assigned';
            v_data := NULL;
            v_log_error := SQLERRM;
            v_sql_state := SQLSTATE;
    END;

    v_response := jsonb_build_object(
        'status', v_status,
        'code', v_code,
        'message', v_message,
        'data', v_data
    );

    BEGIN
        INSERT INTO solar_app.log_sql_functions (
            api_endpoint, function_name, logged_in_user_id, user_id,
            request_payload, execution_status, error_message, sql_state,
            execution_time_ms, created_by, updated_by
        ) VALUES (
            v_api_endpoint,
            'fn_create_job_assignment_details',
            v_actor,
            v_admin_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'job_type', v_job_type,
                'technician_id', v_technician_id,
                'service_request_id', v_service_request_id,
                'site_visit_id', v_site_visit_id,
                'job_id', v_job_id
            )),
            CASE WHEN v_status = 'SUCCESS' THEN 'SUCCESS' ELSE 'ERROR' END,
            v_log_error,
            v_sql_state,
            GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (clock_timestamp() - v_started)) * 1000))::INTEGER,
            v_actor,
            v_actor
        );
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END;

    RETURN v_response;
END;
$$;

COMMENT ON FUNCTION solar_app.fn_create_job_assignment_details(JSONB) IS
    'Admin assigns SERVICE_REQUEST or SITE_VISIT to an active available technician, creates JOB_QUEUED, and enqueues assignment notifications.';
