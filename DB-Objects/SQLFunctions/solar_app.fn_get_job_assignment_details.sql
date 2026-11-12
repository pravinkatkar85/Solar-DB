-- Lists or details jobs assigned to the signed-in ROLE_TECHNICIAN.
-- Session identity comes only from jwt_token_hash → log_user_sessions.
-- Payload technician_id / ownership fields are not trusted.
-- Do not install this file until separately approved.

CREATE OR REPLACE FUNCTION solar_app.fn_get_job_assignment_details(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = pg_catalog, solar_app
AS $$
DECLARE
    v_started          TIMESTAMPTZ := clock_timestamp();
    v_api_endpoint     VARCHAR(255);
    v_actor            VARCHAR(50) := 'SYSTEM';
    v_status           VARCHAR(20) := 'SUCCESS';
    v_code             INTEGER := 200;
    v_message          TEXT := 'Jobs loaded';
    v_data             JSONB := NULL;
    v_response         JSONB;
    v_log_error        TEXT;
    v_sql_state        VARCHAR(10);
    v_token_hash       TEXT;
    v_session_count    INTEGER := 0;
    v_session_id       BIGINT;
    v_user_id          BIGINT;
    v_active           BOOLEAN;
    v_account_code     VARCHAR(50);
    v_role_code        VARCHAR(50);
    v_claimed          TEXT;
    v_technician_id    BIGINT;
    v_job_text         TEXT;
    v_job_id           BIGINT;
    v_rows             JSONB;
    v_detail           JSONB;
    v_checklist        JSONB;
    v_media            JSONB;
    v_signoff          JSONB;
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
            v_message := 'This account cannot view jobs';
            EXIT body;
        END IF;
        IF v_role_code IS DISTINCT FROM 'ROLE_TECHNICIAN' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'Only a technician can view assigned jobs';
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

        v_job_text := NULLIF(btrim(COALESCE(p_payload->>'job_id', '')), '');
        IF v_job_text IS NOT NULL AND v_job_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'job_id is not valid';
            EXIT body;
        END IF;
        IF v_job_text IS NOT NULL THEN
            v_job_id := v_job_text::BIGINT;
        END IF;

        IF v_job_id IS NULL THEN
            SELECT COALESCE(jsonb_agg(row_data ORDER BY sort_on, job_id), '[]'::jsonb)
              INTO v_rows
              FROM (
                SELECT job.job_id,
                       job.scheduled_on AS sort_on,
                       jsonb_build_object(
                           'job_id', job.job_id::TEXT,
                           'job_type', job.job_type,
                           'job_status_code', status_row.data_code,
                           'job_status_name', status_row.data_value,
                           'site_id', job.site_id::TEXT,
                           'service_request_id', CASE WHEN job.service_request_id IS NULL THEN NULL ELSE job.service_request_id::TEXT END,
                           'site_visit_id', CASE WHEN job.site_visit_id IS NULL THEN NULL ELSE job.site_visit_id::TEXT END,
                           'scheduled_on', job.scheduled_on::TEXT,
                           'sequence_no', job.sequence_no,
                           'travel_distance_km', job.travel_distance_km,
                           'started_on', job.started_on,
                           'completed_on', job.completed_on
                       ) AS row_data
                  FROM solar_app.job_assignment_details AS job
                  JOIN solar_app.ref_data AS status_row
                    ON status_row.ref_data_id = job.job_status_ref_data_id
                 WHERE job.technician_id = v_technician_id
                   AND job.active_ind IS TRUE
              ) AS listed;

            v_data := jsonb_build_object(
                'technician_id', v_technician_id::TEXT,
                'jobs', v_rows
            );
            v_message := 'Jobs loaded';
        ELSE
            SELECT jsonb_strip_nulls(jsonb_build_object(
                       'job_id', job.job_id::TEXT,
                       'job_type', job.job_type,
                       'job_status_code', status_row.data_code,
                       'job_status_name', status_row.data_value,
                       'site_id', job.site_id::TEXT,
                       'service_request_id', CASE WHEN job.service_request_id IS NULL THEN NULL ELSE job.service_request_id::TEXT END,
                       'site_visit_id', CASE WHEN job.site_visit_id IS NULL THEN NULL ELSE job.site_visit_id::TEXT END,
                       'scheduled_on', job.scheduled_on::TEXT,
                       'sequence_no', job.sequence_no,
                       'travel_distance_km', job.travel_distance_km,
                       'accept_reject_reason', job.accept_reject_reason,
                       'eta_on', job.eta_on,
                       'started_on', job.started_on,
                       'completed_on', job.completed_on
                   ))
              INTO v_detail
              FROM solar_app.job_assignment_details AS job
              JOIN solar_app.ref_data AS status_row
                ON status_row.ref_data_id = job.job_status_ref_data_id
             WHERE job.job_id = v_job_id
               AND job.technician_id = v_technician_id
               AND job.active_ind IS TRUE;
            IF v_detail IS NULL THEN
                v_status := 'ERROR';
                v_code := 404;
                v_message := 'This job was not found';
                EXIT body;
            END IF;

            SELECT COALESCE(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                       'checklist_item_id', item.checklist_item_id::TEXT,
                       'item_code', item.item_code,
                       'item_label', item.item_label,
                       'expected_value_type', item.expected_value_type,
                       'is_mandatory', item.is_mandatory,
                       'sort_order', item.sort_order,
                       'is_pass', resp.is_pass,
                       'measured_value', resp.measured_value,
                       'remarks', resp.remarks
                   )) ORDER BY item.sort_order, item.checklist_item_id), '[]'::jsonb)
              INTO v_checklist
              FROM solar_app.job_assignment_details AS job
              JOIN solar_app.ref_checklist_items AS item
                ON item.job_type = job.job_type
               AND item.active_ind IS TRUE
              LEFT JOIN solar_app.job_checklist_response_details AS resp
                ON resp.job_id = job.job_id
               AND resp.checklist_item_id = item.checklist_item_id
               AND resp.active_ind IS TRUE
             WHERE job.job_id = v_job_id;

            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                       'job_media_id', media.job_media_id::TEXT,
                       'media_purpose', media.media_purpose,
                       'file_url', media.file_url,
                       'captured_on', media.captured_on
                   ) ORDER BY media.job_media_id), '[]'::jsonb)
              INTO v_media
              FROM solar_app.job_media_details AS media
             WHERE media.job_id = v_job_id
               AND media.active_ind IS TRUE;

            SELECT jsonb_strip_nulls(jsonb_build_object(
                       'job_signoff_id', signoff.job_signoff_id::TEXT,
                       'signature_url', signoff.signature_url,
                       'signer_name', signoff.signer_name,
                       'signed_on', signoff.signed_on,
                       'otp_verified_ind', signoff.otp_verified_ind
                   ))
              INTO v_signoff
              FROM solar_app.job_signoff_details AS signoff
             WHERE signoff.job_id = v_job_id
               AND signoff.active_ind IS TRUE
             ORDER BY signoff.job_signoff_id DESC
             LIMIT 1;

            v_data := v_detail || jsonb_build_object(
                'checklist', COALESCE(v_checklist, '[]'::jsonb),
                'media', COALESCE(v_media, '[]'::jsonb),
                'signoff', v_signoff
            );
            v_message := 'Job loaded';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Jobs could not be loaded';
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
            'fn_get_job_assignment_details',
            v_actor,
            v_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
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

COMMENT ON FUNCTION solar_app.fn_get_job_assignment_details(JSONB) IS
    'ROLE_TECHNICIAN job queue list or one owned job detail with checklist template, media, and sign-off.';
