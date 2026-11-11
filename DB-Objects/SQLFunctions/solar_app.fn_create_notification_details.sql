-- Enqueues one in-app inbox row (and optional push PENDING log rows).
-- Called from other business fn_* after a successful domain change. No triggers.
-- Inactive or suspended recipients do not receive inbox rows.
-- Do not install this file until separately approved.

CREATE OR REPLACE FUNCTION solar_app.fn_create_notification_details(p_payload JSONB)
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
    v_message            TEXT := 'Notification created';
    v_data               JSONB := NULL;
    v_response           JSONB;
    v_log_error          TEXT;
    v_sql_state          VARCHAR(10);
    v_recipient_text     TEXT;
    v_recipient_id       BIGINT;
    v_recipient_active   BOOLEAN;
    v_account_code       VARCHAR(50);
    v_push_enabled       BOOLEAN;
    v_type_code          TEXT;
    v_type_id            BIGINT;
    v_type_name          TEXT;
    v_title              TEXT;
    v_body               TEXT;
    v_payload_json       JSONB;
    v_entity_type        TEXT;
    v_entity_id_text     TEXT;
    v_entity_id          BIGINT;
    v_notification_id    BIGINT;
    v_channel_push_id    BIGINT;
    v_delivery_pending   BIGINT;
    v_push_rows          INTEGER := 0;
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

        v_actor := COALESCE(NULLIF(btrim(p_payload->>'logged_in_user_id'), ''), 'SYSTEM');
        IF char_length(v_actor) > 50 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'logged_in_user_id must be 50 characters or fewer';
            EXIT body;
        END IF;

        v_recipient_text := NULLIF(btrim(COALESCE(p_payload->>'recipient_user_id', '')), '');
        IF v_recipient_text IS NULL OR v_recipient_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'recipient_user_id is required';
            EXIT body;
        END IF;
        v_recipient_id := v_recipient_text::BIGINT;

        SELECT app_user.active_ind,
               account_row.data_code,
               app_user.push_notifications_enabled
          INTO v_recipient_active, v_account_code, v_push_enabled
          FROM solar_app.user_details AS app_user
          LEFT JOIN solar_app.ref_data AS account_row
            ON account_row.ref_data_id = app_user.account_status_ref_data_id
         WHERE app_user.user_id = v_recipient_id;

        IF NOT FOUND OR v_recipient_active IS NOT TRUE OR v_account_code = 'ACCT_SUSPENDED' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'Recipient cannot receive notifications';
            EXIT body;
        END IF;

        v_type_code := upper(NULLIF(btrim(COALESCE(p_payload->>'notification_type_code', '')), ''));
        IF v_type_code IS NULL OR v_type_code !~ '^[A-Z][A-Z0-9_]{0,49}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'notification_type_code is required';
            EXIT body;
        END IF;

        SELECT type_row.ref_data_id, type_row.data_value
          INTO v_type_id, v_type_name
          FROM solar_app.ref_data AS type_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = type_row.category_id
         WHERE category.category_code = 'NOTIFICATION_TYPES'
           AND type_row.data_code = v_type_code
           AND category.active_ind IS TRUE
           AND type_row.active_ind IS TRUE;
        IF v_type_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'notification_type_code is not supported';
            EXIT body;
        END IF;

        v_title := NULLIF(btrim(COALESCE(p_payload->>'title', '')), '');
        IF v_title IS NULL THEN
            v_title := COALESCE(NULLIF(btrim(v_type_name), ''), v_type_code);
        END IF;
        IF char_length(v_title) > 200 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'title must be 200 characters or fewer';
            EXIT body;
        END IF;

        v_body := NULLIF(btrim(COALESCE(p_payload->>'body', '')), '');
        IF v_body IS NULL OR char_length(v_body) > 1000 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'body is required and must be 1000 characters or fewer';
            EXIT body;
        END IF;

        IF p_payload ? 'payload_json' AND p_payload->'payload_json' IS NOT NULL
           AND jsonb_typeof(p_payload->'payload_json') <> 'null' THEN
            IF jsonb_typeof(p_payload->'payload_json') <> 'object' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'payload_json must be a JSON object';
                EXIT body;
            END IF;
            v_payload_json := p_payload->'payload_json';
        ELSE
            v_payload_json := '{}'::jsonb;
        END IF;

        v_entity_type := upper(NULLIF(btrim(COALESCE(p_payload->>'related_entity_type', '')), ''));
        IF v_entity_type IS NOT NULL AND v_entity_type NOT IN (
            'PRODUCT', 'ENQUIRY', 'ORDER', 'SERVICE_REQUEST', 'SERVICE_MILESTONE',
            'TICKET', 'JOB', 'KYC', 'INVOICE', 'PAYMENT', 'FOLLOWUP', 'LEAD', 'AMC', 'USER', 'SITE_VISIT'
        ) THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'related_entity_type is not supported';
            EXIT body;
        END IF;

        v_entity_id_text := NULLIF(btrim(COALESCE(p_payload->>'related_entity_id', '')), '');
        IF v_entity_id_text IS NOT NULL THEN
            IF v_entity_id_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'related_entity_id is not valid';
                EXIT body;
            END IF;
            v_entity_id := v_entity_id_text::BIGINT;
        END IF;

        IF (v_entity_type IS NULL) <> (v_entity_id IS NULL) THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'related_entity_type and related_entity_id must be supplied together';
            EXIT body;
        END IF;

        IF NOT (v_payload_json ? 'entity_type') AND v_entity_type IS NOT NULL THEN
            v_payload_json := v_payload_json || jsonb_build_object(
                'entity_type', v_entity_type,
                'entity_id', v_entity_id::TEXT
            );
        END IF;

        INSERT INTO solar_app.notification_details (
            recipient_user_id,
            notification_type_ref_data_id,
            title,
            body,
            payload_json,
            related_entity_type,
            related_entity_id,
            is_read_ind,
            read_on,
            active_ind,
            created_by,
            updated_by,
            created_on,
            updated_on
        ) VALUES (
            v_recipient_id,
            v_type_id,
            v_title,
            v_body,
            v_payload_json,
            v_entity_type,
            v_entity_id,
            FALSE,
            NULL,
            TRUE,
            v_actor,
            v_actor,
            clock_timestamp(),
            clock_timestamp()
        )
        RETURNING notification_id INTO v_notification_id;

        IF v_push_enabled IS TRUE THEN
            SELECT channel_row.ref_data_id
              INTO v_channel_push_id
              FROM solar_app.ref_data AS channel_row
              JOIN solar_app.ref_data_categories AS category
                ON category.category_id = channel_row.category_id
             WHERE category.category_code = 'NOTIFICATION_CHANNELS'
               AND channel_row.data_code = 'NTF_CH_PUSH'
               AND category.active_ind IS TRUE
               AND channel_row.active_ind IS TRUE;

            SELECT status_row.ref_data_id
              INTO v_delivery_pending
              FROM solar_app.ref_data AS status_row
              JOIN solar_app.ref_data_categories AS category
                ON category.category_id = status_row.category_id
             WHERE category.category_code = 'NOTIFICATION_DELIVERY_STATUSES'
               AND status_row.data_code = 'NTF_DEL_PENDING'
               AND category.active_ind IS TRUE
               AND status_row.active_ind IS TRUE;

            IF v_channel_push_id IS NOT NULL AND v_delivery_pending IS NOT NULL THEN
                INSERT INTO solar_app.log_notification_delivery (
                    notification_id,
                    session_id,
                    channel_ref_data_id,
                    delivery_status_ref_data_id,
                    active_ind,
                    created_by,
                    updated_by,
                    created_on,
                    updated_on
                )
                SELECT
                    v_notification_id,
                    session.session_id,
                    v_channel_push_id,
                    v_delivery_pending,
                    TRUE,
                    v_actor,
                    v_actor,
                    clock_timestamp(),
                    clock_timestamp()
                  FROM solar_app.log_user_sessions AS session
                 WHERE session.user_id = v_recipient_id
                   AND session.session_status = 'ACTIVE'
                   AND session.active_ind IS TRUE
                   AND NULLIF(btrim(session.push_token), '') IS NOT NULL;
                GET DIAGNOSTICS v_push_rows = ROW_COUNT;
            END IF;
        END IF;

        v_data := jsonb_build_object(
            'notification_id', v_notification_id::TEXT,
            'recipient_user_id', v_recipient_id::TEXT,
            'notification_type_code', v_type_code,
            'push_queued', v_push_rows > 0
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Notification could not be created';
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
            'fn_create_notification_details',
            v_actor,
            CASE WHEN v_actor ~ '^[0-9]{1,18}$' THEN v_actor::BIGINT ELSE NULL END,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'recipient_user_id', v_recipient_id,
                'notification_type_code', v_type_code,
                'related_entity_type', v_entity_type,
                'related_entity_id', v_entity_id
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

COMMENT ON FUNCTION solar_app.fn_create_notification_details(JSONB) IS
    'Enqueue one in-app notification and optional push PENDING rows. Called from other fn_*; no triggers.';
