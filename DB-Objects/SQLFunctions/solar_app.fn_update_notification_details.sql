-- Marks one or all inbox rows read for the authenticated session user only.
-- Client-supplied recipient_user_id values are not trusted.
-- Do not install this file until separately approved.

CREATE OR REPLACE FUNCTION solar_app.fn_update_notification_details(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = pg_catalog, solar_app
AS $$
DECLARE
    v_started       TIMESTAMPTZ := clock_timestamp();
    v_api_endpoint  VARCHAR(255);
    v_actor         VARCHAR(50) := 'SYSTEM';
    v_status        VARCHAR(20) := 'SUCCESS';
    v_code          INTEGER := 200;
    v_message       TEXT := 'Notification updated';
    v_data          JSONB := NULL;
    v_response      JSONB;
    v_log_error     TEXT;
    v_sql_state     VARCHAR(10);
    v_token_hash    TEXT;
    v_session_count INTEGER := 0;
    v_session_id    BIGINT;
    v_user_id       BIGINT;
    v_active        BOOLEAN;
    v_account_code  VARCHAR(50);
    v_claimed       TEXT;
    v_action        TEXT;
    v_ntf_text      TEXT;
    v_ntf_id        BIGINT;
    v_updated       INTEGER := 0;
    v_unread        INTEGER := 0;
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
        v_claimed := NULLIF(btrim(p_payload->>'recipient_user_id'), '');
        IF v_claimed IS NOT NULL AND v_claimed IS DISTINCT FROM v_actor THEN
            v_status := 'ERROR';
            v_code := 401;
            v_message := 'Authentication is required';
            EXIT body;
        END IF;

        SELECT app_user.active_ind, account_row.data_code
          INTO v_active, v_account_code
          FROM solar_app.user_details AS app_user
          LEFT JOIN solar_app.ref_data AS account_row
            ON account_row.ref_data_id = app_user.account_status_ref_data_id
         WHERE app_user.user_id = v_user_id;

        IF NOT FOUND OR v_active IS NOT TRUE OR v_account_code = 'ACCT_SUSPENDED' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'This account cannot update notifications';
            EXIT body;
        END IF;

        v_action := upper(NULLIF(btrim(COALESCE(p_payload->>'action', '')), ''));
        IF v_action NOT IN ('MARK_READ', 'MARK_ALL_READ') THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose mark read or mark all read';
            EXIT body;
        END IF;

        IF v_action = 'MARK_READ' THEN
            v_ntf_text := NULLIF(btrim(COALESCE(p_payload->>'notification_id', '')), '');
            IF v_ntf_text IS NULL OR v_ntf_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Choose a notification';
                EXIT body;
            END IF;
            v_ntf_id := v_ntf_text::BIGINT;

            UPDATE solar_app.notification_details AS ntf
               SET is_read_ind = TRUE,
                   read_on = COALESCE(ntf.read_on, clock_timestamp()),
                   updated_by = v_actor,
                   updated_on = clock_timestamp()
             WHERE ntf.notification_id = v_ntf_id
               AND ntf.recipient_user_id = v_user_id
               AND ntf.active_ind IS TRUE;
            GET DIAGNOSTICS v_updated = ROW_COUNT;
            IF v_updated IS DISTINCT FROM 1 THEN
                v_status := 'ERROR';
                v_code := 404;
                v_message := 'This notification was not found';
                EXIT body;
            END IF;
            v_message := 'Notification marked read';
        ELSE
            UPDATE solar_app.notification_details AS ntf
               SET is_read_ind = TRUE,
                   read_on = COALESCE(ntf.read_on, clock_timestamp()),
                   updated_by = v_actor,
                   updated_on = clock_timestamp()
             WHERE ntf.recipient_user_id = v_user_id
               AND ntf.active_ind IS TRUE
               AND ntf.is_read_ind IS FALSE;
            GET DIAGNOSTICS v_updated = ROW_COUNT;
            v_message := 'Notifications marked read';
        END IF;

        SELECT COUNT(*)::INTEGER
          INTO v_unread
          FROM solar_app.notification_details AS ntf
         WHERE ntf.recipient_user_id = v_user_id
           AND ntf.active_ind IS TRUE
           AND ntf.is_read_ind IS FALSE;

        v_data := jsonb_build_object(
            'updated_count', v_updated,
            'unread_count', v_unread,
            'notification_id', CASE WHEN v_ntf_id IS NULL THEN NULL ELSE v_ntf_id::TEXT END
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Notification could not be updated';
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
            'fn_update_notification_details',
            v_actor,
            v_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'action', v_action,
                'notification_id', v_ntf_id
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

COMMENT ON FUNCTION solar_app.fn_update_notification_details(JSONB) IS
    'Mark one or all session-user inbox notifications as read.';
