-- Technician job lifecycle: ACCEPT, RESCHEDULE, START, COMPLETE.
-- Session identity and ROLE_TECHNICIAN come only from jwt_token_hash → log_user_sessions.
-- Owns only jobs assigned to the session technician_details row.
-- JOB_REJECTED is not implemented. Does not create site visits or service requests.
-- Does not modify fn_update_site_visit_details (customer completion).
-- Do not install this file until separately approved.

CREATE OR REPLACE FUNCTION solar_app.fn_update_job_assignment_details(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = pg_catalog, solar_app
AS $$
DECLARE
    v_started            TIMESTAMPTZ := clock_timestamp();
    v_api_endpoint       VARCHAR(255);
    v_actor              VARCHAR(50) := 'SYSTEM';
    v_status             VARCHAR(20) := 'SUCCESS';
    v_code               INTEGER := 200;
    v_message            TEXT := 'Job updated';
    v_data               JSONB := NULL;
    v_response           JSONB;
    v_log_error          TEXT;
    v_sql_state          VARCHAR(10);
    v_token_hash         TEXT;
    v_session_count      INTEGER := 0;
    v_session_id         BIGINT;
    v_user_id            BIGINT;
    v_active             BOOLEAN;
    v_account_code       VARCHAR(50);
    v_role_code          VARCHAR(50);
    v_claimed            TEXT;
    v_technician_id      BIGINT;
    v_action             TEXT;
    v_job_text           TEXT;
    v_job_id             BIGINT;
    v_job_type           VARCHAR(30);
    v_job_status_code    VARCHAR(50);
    v_service_request_id BIGINT;
    v_site_visit_id      BIGINT;
    v_customer_id        BIGINT;
    v_scheduled_on       DATE;
    v_date_text          TEXT;
    v_reason             TEXT;
    v_target_status_id   BIGINT;
    v_target_status_code VARCHAR(50);
    v_parent_status_id   BIGINT;
    v_updated            INTEGER := 0;
    v_checklist_json     JSONB;
    v_media_json         JSONB;
    v_signature_json     JSONB;
    v_item               JSONB;
    v_media_item         JSONB;
    v_idx                INTEGER;
    v_item_id_text       TEXT;
    v_item_id            BIGINT;
    v_item_type          VARCHAR(20);
    v_item_mandatory     BOOLEAN;
    v_is_pass            BOOLEAN;
    v_measured_value     TEXT;
    v_remarks            TEXT;
    v_seen_items         BIGINT[] := ARRAY[]::BIGINT[];
    v_missing_count      INTEGER;
    v_purpose            TEXT;
    v_file_url           TEXT;
    v_captured_text      TEXT;
    v_captured_on        TIMESTAMPTZ;
    v_has_before         BOOLEAN := FALSE;
    v_has_after          BOOLEAN := FALSE;
    v_signature_url      TEXT;
    v_signer_name        TEXT;
    v_signed_text        TEXT;
    v_signed_on          TIMESTAMPTZ;
    v_ntf_response       JSONB;
    v_customer_user_id   BIGINT;
    v_customer_active    BOOLEAN;
    v_customer_account   VARCHAR(50);
    v_admin_user_id      BIGINT;
    v_notification_ids   JSONB := '[]'::jsonb;
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
          INTO v_session_id, v_user_id
          FROM solar_app.log_user_sessions AS session
         WHERE session.jwt_token_hash = v_token_hash
           AND session.session_status = 'ACTIVE'
           AND session.active_ind IS TRUE
           AND session.user_id IS NOT NULL;

        v_actor := v_user_id::TEXT;
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
         WHERE app_user.user_id = v_user_id;

        IF NOT FOUND OR v_active IS NOT TRUE OR v_account_code = 'ACCT_SUSPENDED' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'This account cannot update jobs';
            EXIT body;
        END IF;
        IF v_role_code IS DISTINCT FROM 'ROLE_TECHNICIAN' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'Only a technician can update assigned jobs';
            EXIT body;
        END IF;

        SELECT tech.technician_id
          INTO v_technician_id
          FROM solar_app.technician_details AS tech
         WHERE tech.user_id = v_user_id
           AND tech.active_ind IS TRUE;
        IF v_technician_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'Technician profile was not found';
            EXIT body;
        END IF;

        v_action := upper(NULLIF(btrim(COALESCE(p_payload->>'action', '')), ''));
        IF v_action NOT IN ('ACCEPT', 'RESCHEDULE', 'START', 'COMPLETE') THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'action must be ACCEPT, RESCHEDULE, START, or COMPLETE';
            EXIT body;
        END IF;

        v_job_text := NULLIF(btrim(COALESCE(p_payload->>'job_id', '')), '');
        IF v_job_text IS NULL OR v_job_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'job_id is required';
            EXIT body;
        END IF;
        v_job_id := v_job_text::BIGINT;

        SELECT job.job_type,
               status_row.data_code,
               job.service_request_id,
               job.site_visit_id,
               job.scheduled_on
          INTO v_job_type, v_job_status_code, v_service_request_id, v_site_visit_id, v_scheduled_on
          FROM solar_app.job_assignment_details AS job
          JOIN solar_app.ref_data AS status_row
            ON status_row.ref_data_id = job.job_status_ref_data_id
         WHERE job.job_id = v_job_id
           AND job.technician_id = v_technician_id
           AND job.active_ind IS TRUE
         FOR UPDATE;
        IF v_job_type IS NULL THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This job was not found';
            EXIT body;
        END IF;

        IF v_action = 'ACCEPT' THEN
            IF v_job_status_code NOT IN ('JOB_QUEUED', 'JOB_RESCHEDULED') THEN
                v_status := 'ERROR';
                v_code := 409;
                v_message := 'This job cannot be accepted in its current status';
                EXIT body;
            END IF;
            v_target_status_code := 'JOB_ACCEPTED';
            v_message := 'Job accepted';

        ELSIF v_action = 'RESCHEDULE' THEN
            IF v_job_status_code NOT IN ('JOB_QUEUED', 'JOB_ACCEPTED', 'JOB_RESCHEDULED') THEN
                v_status := 'ERROR';
                v_code := 409;
                v_message := 'This job cannot be rescheduled in its current status';
                EXIT body;
            END IF;
            v_reason := NULLIF(btrim(COALESCE(p_payload->>'accept_reject_reason', p_payload->>'reason', '')), '');
            IF v_reason IS NULL OR char_length(v_reason) > 500 THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Enter a reschedule reason';
                EXIT body;
            END IF;
            v_date_text := NULLIF(btrim(COALESCE(p_payload->>'scheduled_on', '')), '');
            IF v_date_text IS NULL THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'scheduled_on is required to reschedule';
                EXIT body;
            END IF;
            BEGIN
                v_scheduled_on := v_date_text::DATE;
            EXCEPTION
                WHEN OTHERS THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'scheduled_on is not valid';
                    EXIT body;
            END;
            v_target_status_code := 'JOB_RESCHEDULED';
            v_message := 'Job rescheduled';

        ELSIF v_action = 'START' THEN
            IF v_job_status_code IS DISTINCT FROM 'JOB_ACCEPTED' THEN
                v_status := 'ERROR';
                v_code := 409;
                v_message := 'This job cannot be started in its current status';
                EXIT body;
            END IF;
            v_target_status_code := 'JOB_IN_PROGRESS';
            v_message := 'Job started';

        ELSE
            IF v_job_status_code IS DISTINCT FROM 'JOB_IN_PROGRESS' THEN
                IF v_job_status_code = 'JOB_COMPLETED' THEN
                    v_status := 'ERROR';
                    v_code := 409;
                    v_message := 'This job is already completed';
                ELSE
                    v_status := 'ERROR';
                    v_code := 409;
                    v_message := 'This job cannot be completed in its current status';
                END IF;
                EXIT body;
            END IF;

            IF NOT (p_payload ? 'checklist_responses')
               OR jsonb_typeof(p_payload->'checklist_responses') <> 'array' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'checklist_responses must be a JSON array';
                EXIT body;
            END IF;
            v_checklist_json := p_payload->'checklist_responses';

            IF NOT (p_payload ? 'media')
               OR jsonb_typeof(p_payload->'media') <> 'array' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'media must be a JSON array';
                EXIT body;
            END IF;
            v_media_json := p_payload->'media';

            IF NOT (p_payload ? 'signature')
               OR jsonb_typeof(p_payload->'signature') <> 'object'
               OR p_payload->'signature' IS NULL
               OR jsonb_typeof(p_payload->'signature') = 'null' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'signature is required';
                EXIT body;
            END IF;
            v_signature_json := p_payload->'signature';

            FOR v_idx IN 0 .. jsonb_array_length(v_checklist_json) - 1 LOOP
                v_item := v_checklist_json->v_idx;
                IF jsonb_typeof(v_item) <> 'object' THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'Each checklist response must be an object';
                    EXIT body;
                END IF;
                v_item_id_text := NULLIF(btrim(COALESCE(v_item->>'checklist_item_id', '')), '');
                IF v_item_id_text IS NULL OR v_item_id_text !~ '^[0-9]{1,18}$' THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'checklist_item_id is required';
                    EXIT body;
                END IF;
                v_item_id := v_item_id_text::BIGINT;
                IF v_item_id = ANY (v_seen_items) THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'Duplicate checklist_item_id in responses';
                    EXIT body;
                END IF;
                v_seen_items := array_append(v_seen_items, v_item_id);

                SELECT item.expected_value_type, item.is_mandatory
                  INTO v_item_type, v_item_mandatory
                  FROM solar_app.ref_checklist_items AS item
                 WHERE item.checklist_item_id = v_item_id
                   AND item.job_type = v_job_type
                   AND item.active_ind IS TRUE;
                IF v_item_type IS NULL THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'checklist_item_id is not valid for this job type';
                    EXIT body;
                END IF;

                v_is_pass := NULL;
                v_measured_value := NULLIF(btrim(COALESCE(v_item->>'measured_value', '')), '');
                v_remarks := NULLIF(btrim(COALESCE(v_item->>'remarks', '')), '');
                IF v_remarks IS NOT NULL AND char_length(v_remarks) > 500 THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'remarks must be 500 characters or fewer';
                    EXIT body;
                END IF;
                IF v_measured_value IS NOT NULL AND char_length(v_measured_value) > 100 THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'measured_value must be 100 characters or fewer';
                    EXIT body;
                END IF;

                IF v_item_type = 'BOOLEAN' THEN
                    IF v_item ? 'is_pass'
                       AND v_item->'is_pass' IS NOT NULL
                       AND jsonb_typeof(v_item->'is_pass') <> 'null' THEN
                        IF jsonb_typeof(v_item->'is_pass') = 'boolean' THEN
                            v_is_pass := (v_item->>'is_pass')::BOOLEAN;
                        ELSIF lower(NULLIF(btrim(v_item->>'is_pass'), '')) IN ('true', 'false') THEN
                            v_is_pass := lower(btrim(v_item->>'is_pass')) = 'true';
                        ELSE
                            v_status := 'ERROR';
                            v_code := 400;
                            v_message := 'is_pass is not valid';
                            EXIT body;
                        END IF;
                    END IF;
                    IF v_item_mandatory AND v_is_pass IS NULL THEN
                        v_status := 'ERROR';
                        v_code := 400;
                        v_message := 'Complete all mandatory checklist items';
                        EXIT body;
                    END IF;
                ELSE
                    IF v_item_mandatory AND v_measured_value IS NULL THEN
                        v_status := 'ERROR';
                        v_code := 400;
                        v_message := 'Complete all mandatory checklist items';
                        EXIT body;
                    END IF;
                END IF;
            END LOOP;

            SELECT COUNT(*)
              INTO v_missing_count
              FROM solar_app.ref_checklist_items AS item
             WHERE item.job_type = v_job_type
               AND item.active_ind IS TRUE
               AND item.is_mandatory IS TRUE
               AND NOT (item.checklist_item_id = ANY (v_seen_items));
            IF v_missing_count > 0 THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Complete all mandatory checklist items';
                EXIT body;
            END IF;

            FOR v_idx IN 0 .. jsonb_array_length(v_media_json) - 1 LOOP
                v_media_item := v_media_json->v_idx;
                IF jsonb_typeof(v_media_item) <> 'object' THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'Each media item must be an object';
                    EXIT body;
                END IF;
                v_purpose := upper(NULLIF(btrim(COALESCE(v_media_item->>'media_purpose', '')), ''));
                IF v_purpose NOT IN ('BEFORE', 'AFTER', 'INVERTER_STATUS', 'OTHER') THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'media_purpose is not valid';
                    EXIT body;
                END IF;
                v_file_url := NULLIF(btrim(COALESCE(v_media_item->>'file_url', '')), '');
                IF v_file_url IS NULL OR char_length(v_file_url) > 500 THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'file_url is required';
                    EXIT body;
                END IF;
                v_captured_on := NULL;
                v_captured_text := NULLIF(btrim(COALESCE(v_media_item->>'captured_on', '')), '');
                IF v_captured_text IS NOT NULL THEN
                    BEGIN
                        v_captured_on := v_captured_text::TIMESTAMPTZ;
                    EXCEPTION
                        WHEN OTHERS THEN
                            v_status := 'ERROR';
                            v_code := 400;
                            v_message := 'captured_on is not valid';
                            EXIT body;
                    END;
                END IF;
                IF v_purpose = 'BEFORE' THEN
                    v_has_before := TRUE;
                ELSIF v_purpose = 'AFTER' THEN
                    v_has_after := TRUE;
                END IF;
            END LOOP;
            IF NOT v_has_before OR NOT v_has_after THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Before and after photos are required';
                EXIT body;
            END IF;

            v_signature_url := NULLIF(btrim(COALESCE(v_signature_json->>'signature_url', '')), '');
            IF v_signature_url IS NULL OR char_length(v_signature_url) > 500 THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'signature_url is required';
                EXIT body;
            END IF;
            v_signer_name := NULLIF(btrim(COALESCE(v_signature_json->>'signer_name', '')), '');
            IF v_signer_name IS NOT NULL AND char_length(v_signer_name) > 150 THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'signer_name must be 150 characters or fewer';
                EXIT body;
            END IF;
            v_signed_on := clock_timestamp();
            v_signed_text := NULLIF(btrim(COALESCE(v_signature_json->>'signed_on', '')), '');
            IF v_signed_text IS NOT NULL THEN
                BEGIN
                    v_signed_on := v_signed_text::TIMESTAMPTZ;
                EXCEPTION
                    WHEN OTHERS THEN
                        v_status := 'ERROR';
                        v_code := 400;
                        v_message := 'signed_on is not valid';
                        EXIT body;
                END;
            END IF;

            v_target_status_code := 'JOB_COMPLETED';
            v_message := 'Job completed';
        END IF;

        SELECT ref_row.ref_data_id
          INTO v_target_status_id
          FROM solar_app.ref_data AS ref_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = ref_row.category_id
         WHERE category.category_code = 'JOB_STATUSES'
           AND ref_row.data_code = v_target_status_code
           AND category.active_ind IS TRUE
           AND ref_row.active_ind IS TRUE;
        IF v_target_status_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Job could not be updated';
            v_log_error := v_target_status_code || ' is not configured';
            EXIT body;
        END IF;

        UPDATE solar_app.job_assignment_details AS job
           SET job_status_ref_data_id = v_target_status_id,
               scheduled_on = CASE
                                  WHEN v_action = 'RESCHEDULE' THEN v_scheduled_on
                                  ELSE job.scheduled_on
                              END,
               accept_reject_reason = CASE
                                          WHEN v_action = 'RESCHEDULE' THEN v_reason
                                          ELSE job.accept_reject_reason
                                      END,
               started_on = CASE
                                WHEN v_action = 'START' THEN COALESCE(job.started_on, clock_timestamp())
                                ELSE job.started_on
                            END,
               completed_on = CASE
                                  WHEN v_action = 'COMPLETE' THEN clock_timestamp()
                                  ELSE job.completed_on
                              END,
               updated_by = v_actor,
               updated_on = clock_timestamp()
         WHERE job.job_id = v_job_id
           AND job.technician_id = v_technician_id
           AND job.active_ind IS TRUE;
        GET DIAGNOSTICS v_updated = ROW_COUNT;
        IF v_updated IS DISTINCT FROM 1 THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This job was not found';
            EXIT body;
        END IF;

        IF v_action = 'RESCHEDULE' AND v_site_visit_id IS NOT NULL THEN
            UPDATE solar_app.site_visit_details AS visit
               SET scheduled_on = v_scheduled_on,
                   updated_by = v_actor,
                   updated_on = clock_timestamp()
             WHERE visit.site_visit_id = v_site_visit_id
               AND visit.active_ind IS TRUE;
        END IF;

        IF v_action = 'START' THEN
            IF v_service_request_id IS NOT NULL THEN
                SELECT ref_row.ref_data_id
                  INTO v_parent_status_id
                  FROM solar_app.ref_data AS ref_row
                  JOIN solar_app.ref_data_categories AS category
                    ON category.category_id = ref_row.category_id
                 WHERE category.category_code = 'SERVICE_REQUEST_STATUSES'
                   AND ref_row.data_code = 'SR_IN_PROGRESS'
                   AND category.active_ind IS TRUE
                   AND ref_row.active_ind IS TRUE;
                IF v_parent_status_id IS NULL THEN
                    RAISE EXCEPTION 'SR_IN_PROGRESS is not configured' USING ERRCODE = 'P0001';
                END IF;
                UPDATE solar_app.service_request_details AS sr
                   SET status_ref_data_id = v_parent_status_id,
                       updated_by = v_actor,
                       updated_on = clock_timestamp()
                 WHERE sr.service_request_id = v_service_request_id
                   AND sr.active_ind IS TRUE;
            END IF;
            IF v_site_visit_id IS NOT NULL THEN
                SELECT ref_row.ref_data_id
                  INTO v_parent_status_id
                  FROM solar_app.ref_data AS ref_row
                  JOIN solar_app.ref_data_categories AS category
                    ON category.category_id = ref_row.category_id
                 WHERE category.category_code = 'SITE_VISIT_STATUSES'
                   AND ref_row.data_code = 'VISIT_IN_PROGRESS'
                   AND category.active_ind IS TRUE
                   AND ref_row.active_ind IS TRUE;
                IF v_parent_status_id IS NULL THEN
                    RAISE EXCEPTION 'VISIT_IN_PROGRESS is not configured' USING ERRCODE = 'P0001';
                END IF;
                UPDATE solar_app.site_visit_details AS visit
                   SET visit_status_ref_data_id = v_parent_status_id,
                       started_on = COALESCE(visit.started_on, clock_timestamp()),
                       updated_by = v_actor,
                       updated_on = clock_timestamp()
                 WHERE visit.site_visit_id = v_site_visit_id
                   AND visit.active_ind IS TRUE;
            END IF;
        END IF;

        IF v_action = 'COMPLETE' THEN
            UPDATE solar_app.job_checklist_response_details AS resp
               SET active_ind = FALSE,
                   updated_by = v_actor,
                   updated_on = clock_timestamp()
             WHERE resp.job_id = v_job_id
               AND resp.active_ind IS TRUE;

            FOR v_idx IN 0 .. jsonb_array_length(v_checklist_json) - 1 LOOP
                v_item := v_checklist_json->v_idx;
                v_item_id := (v_item->>'checklist_item_id')::BIGINT;
                SELECT item.expected_value_type
                  INTO v_item_type
                  FROM solar_app.ref_checklist_items AS item
                 WHERE item.checklist_item_id = v_item_id;
                v_is_pass := NULL;
                v_measured_value := NULLIF(btrim(COALESCE(v_item->>'measured_value', '')), '');
                v_remarks := NULLIF(btrim(COALESCE(v_item->>'remarks', '')), '');
                IF v_item_type = 'BOOLEAN'
                   AND v_item ? 'is_pass'
                   AND v_item->'is_pass' IS NOT NULL
                   AND jsonb_typeof(v_item->'is_pass') <> 'null' THEN
                    IF jsonb_typeof(v_item->'is_pass') = 'boolean' THEN
                        v_is_pass := (v_item->>'is_pass')::BOOLEAN;
                    ELSE
                        v_is_pass := lower(btrim(v_item->>'is_pass')) = 'true';
                    END IF;
                END IF;
                INSERT INTO solar_app.job_checklist_response_details (
                    job_id, checklist_item_id, is_pass, measured_value, remarks,
                    created_by, updated_by
                ) VALUES (
                    v_job_id, v_item_id, v_is_pass, v_measured_value, v_remarks,
                    v_actor, v_actor
                );
            END LOOP;

            UPDATE solar_app.job_media_details AS media
               SET active_ind = FALSE,
                   updated_by = v_actor,
                   updated_on = clock_timestamp()
             WHERE media.job_id = v_job_id
               AND media.active_ind IS TRUE;

            FOR v_idx IN 0 .. jsonb_array_length(v_media_json) - 1 LOOP
                v_media_item := v_media_json->v_idx;
                v_purpose := upper(btrim(v_media_item->>'media_purpose'));
                v_file_url := btrim(v_media_item->>'file_url');
                v_captured_on := NULL;
                IF NULLIF(btrim(COALESCE(v_media_item->>'captured_on', '')), '') IS NOT NULL THEN
                    v_captured_on := (v_media_item->>'captured_on')::TIMESTAMPTZ;
                END IF;
                INSERT INTO solar_app.job_media_details (
                    job_id, media_purpose, file_url, captured_on, created_by, updated_by
                ) VALUES (
                    v_job_id, v_purpose, v_file_url, v_captured_on, v_actor, v_actor
                );
            END LOOP;

            UPDATE solar_app.job_signoff_details AS signoff
               SET active_ind = FALSE,
                   updated_by = v_actor,
                   updated_on = clock_timestamp()
             WHERE signoff.job_id = v_job_id
               AND signoff.active_ind IS TRUE;

            INSERT INTO solar_app.job_signoff_details (
                job_id, signature_url, signer_name, signed_on, created_by, updated_by
            ) VALUES (
                v_job_id, v_signature_url, v_signer_name, v_signed_on, v_actor, v_actor
            );

            IF v_service_request_id IS NOT NULL THEN
                SELECT ref_row.ref_data_id
                  INTO v_parent_status_id
                  FROM solar_app.ref_data AS ref_row
                  JOIN solar_app.ref_data_categories AS category
                    ON category.category_id = ref_row.category_id
                 WHERE category.category_code = 'SERVICE_REQUEST_STATUSES'
                   AND ref_row.data_code = 'SR_COMPLETED'
                   AND category.active_ind IS TRUE
                   AND ref_row.active_ind IS TRUE;
                IF v_parent_status_id IS NULL THEN
                    RAISE EXCEPTION 'SR_COMPLETED is not configured' USING ERRCODE = 'P0001';
                END IF;
                UPDATE solar_app.service_request_details AS sr
                   SET status_ref_data_id = v_parent_status_id,
                       updated_by = v_actor,
                       updated_on = clock_timestamp()
                 WHERE sr.service_request_id = v_service_request_id
                   AND sr.active_ind IS TRUE
                RETURNING sr.customer_id INTO v_customer_id;
            END IF;

            IF v_site_visit_id IS NOT NULL THEN
                SELECT ref_row.ref_data_id
                  INTO v_parent_status_id
                  FROM solar_app.ref_data AS ref_row
                  JOIN solar_app.ref_data_categories AS category
                    ON category.category_id = ref_row.category_id
                 WHERE category.category_code = 'SITE_VISIT_STATUSES'
                   AND ref_row.data_code = 'VISIT_COMPLETED'
                   AND category.active_ind IS TRUE
                   AND ref_row.active_ind IS TRUE;
                IF v_parent_status_id IS NULL THEN
                    RAISE EXCEPTION 'VISIT_COMPLETED is not configured' USING ERRCODE = 'P0001';
                END IF;
                UPDATE solar_app.site_visit_details AS visit
                   SET visit_status_ref_data_id = v_parent_status_id,
                       completed_on = COALESCE(visit.completed_on, clock_timestamp()),
                       updated_by = v_actor,
                       updated_on = clock_timestamp()
                 WHERE visit.site_visit_id = v_site_visit_id
                   AND visit.active_ind IS TRUE
                RETURNING visit.customer_id INTO v_customer_id;
            END IF;

            IF v_service_request_id IS NOT NULL AND v_customer_id IS NOT NULL THEN
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
                            'title', 'Service request completed',
                            'body', 'Your service request was completed.',
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
                    v_notification_ids := v_notification_ids
                        || jsonb_build_array(v_ntf_response->'data'->>'notification_id');
                END IF;
            END IF;

            IF v_site_visit_id IS NOT NULL THEN
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
                                'notification_type_code', 'NTF_SITE_VISIT_DONE',
                                'title', 'Site visit completed',
                                'body', 'Your site visit was completed.',
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
                            RAISE EXCEPTION 'Notification enqueue failed (NTF_SITE_VISIT_DONE customer): %',
                                COALESCE(v_ntf_response->>'message', 'unknown error')
                                USING ERRCODE = 'P0001';
                        END IF;
                        v_notification_ids := v_notification_ids
                            || jsonb_build_array(v_ntf_response->'data'->>'notification_id');
                    END IF;
                END IF;

                FOR v_admin_user_id IN
                    SELECT app_user.user_id
                      FROM solar_app.user_details AS app_user
                      JOIN solar_app.ref_data AS role_row
                        ON role_row.ref_data_id = app_user.role_ref_data_id
                      LEFT JOIN solar_app.ref_data AS account_row
                        ON account_row.ref_data_id = app_user.account_status_ref_data_id
                     WHERE role_row.data_code = 'ROLE_ADMIN'
                       AND app_user.active_ind IS TRUE
                       AND account_row.data_code IS DISTINCT FROM 'ACCT_SUSPENDED'
                LOOP
                    v_ntf_response := solar_app.fn_create_notification_details(
                        jsonb_strip_nulls(jsonb_build_object(
                            'api_endpoint', v_api_endpoint,
                            'logged_in_user_id', v_actor,
                            'recipient_user_id', v_admin_user_id::TEXT,
                            'notification_type_code', 'NTF_SITE_VISIT_DONE',
                            'title', 'Site visit completed',
                            'body', 'A site visit was completed.',
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
                        RAISE EXCEPTION 'Notification enqueue failed (NTF_SITE_VISIT_DONE admin): %',
                            COALESCE(v_ntf_response->>'message', 'unknown error')
                            USING ERRCODE = 'P0001';
                    END IF;
                    v_notification_ids := v_notification_ids
                        || jsonb_build_array(v_ntf_response->'data'->>'notification_id');
                END LOOP;
            END IF;
        END IF;

        SELECT jsonb_strip_nulls(jsonb_build_object(
            'job_id', job.job_id::TEXT,
            'job_type', job.job_type,
            'job_status_code', status_row.data_code,
            'scheduled_on', job.scheduled_on::TEXT,
            'accept_reject_reason', job.accept_reject_reason,
            'started_on', job.started_on,
            'completed_on', job.completed_on,
            'service_request_id', CASE WHEN job.service_request_id IS NULL THEN NULL ELSE job.service_request_id::TEXT END,
            'site_visit_id', CASE WHEN job.site_visit_id IS NULL THEN NULL ELSE job.site_visit_id::TEXT END,
            'notification_ids', CASE WHEN v_action = 'COMPLETE' THEN v_notification_ids ELSE NULL END
        ))
          INTO v_data
          FROM solar_app.job_assignment_details AS job
          JOIN solar_app.ref_data AS status_row
            ON status_row.ref_data_id = job.job_status_ref_data_id
         WHERE job.job_id = v_job_id;
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Job could not be updated';
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
            'fn_update_job_assignment_details',
            v_actor,
            v_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'action', v_action,
                'job_id', v_job_id,
                'technician_id', v_technician_id
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

COMMENT ON FUNCTION solar_app.fn_update_job_assignment_details(JSONB) IS
    'ROLE_TECHNICIAN ACCEPT / RESCHEDULE / START / COMPLETE for owned jobs. JOB_REJECTED not implemented. Does not create site visits.';
