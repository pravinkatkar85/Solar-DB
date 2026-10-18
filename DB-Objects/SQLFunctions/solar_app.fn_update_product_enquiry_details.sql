-- Customer actions on one of their own product enquiries.
-- cancel sets ENQ_CLOSED while the enquiry is Open or In Progress.
-- followup creates one open phone-call task for the assigned engineer.
-- A payload user id is not trusted. Converted enquiries are left unchanged.

CREATE OR REPLACE FUNCTION solar_app.fn_update_product_enquiry_details(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = pg_catalog, solar_app
AS $$
DECLARE
    v_started        TIMESTAMPTZ := clock_timestamp();
    v_api_endpoint   VARCHAR(255);
    v_actor          VARCHAR(50) := 'SYSTEM';
    v_status         VARCHAR(20) := 'SUCCESS';
    v_code           INTEGER := 200;
    v_message        TEXT := 'Enquiry updated';
    v_data           JSONB := NULL;
    v_response       JSONB;
    v_log_error      TEXT;
    v_sql_state      VARCHAR(10);
    v_token_hash     TEXT;
    v_session_count  INTEGER := 0;
    v_session_id     BIGINT;
    v_user_id        BIGINT;
    v_active         BOOLEAN;
    v_account_code   VARCHAR(50);
    v_claimed        TEXT;
    v_action         TEXT;
    v_enquiry_text   TEXT;
    v_enquiry_id     BIGINT;
    v_enquiry_no     VARCHAR(30);
    v_status_code    VARCHAR(50);
    v_agent_id       BIGINT;
    v_note           TEXT;
    v_closed_id      BIGINT;
    v_type_id        BIGINT;
    v_open_id        BIGINT;
    v_followup_id    BIGINT;
    v_open_exists    BOOLEAN;
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

        IF v_user_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 401;
            v_message := 'Authentication is required';
            EXIT body;
        END IF;

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

        SELECT app_user.active_ind, account_row.data_code
          INTO v_active, v_account_code
          FROM solar_app.user_details AS app_user
          LEFT JOIN solar_app.ref_data AS account_row
            ON account_row.ref_data_id = app_user.account_status_ref_data_id
         WHERE app_user.user_id = v_user_id;

        IF NOT FOUND OR v_active IS NOT TRUE OR v_account_code = 'ACCT_SUSPENDED' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'This account cannot update enquiries';
            EXIT body;
        END IF;

        v_action := lower(btrim(COALESCE(p_payload->>'action', '')));
        IF v_action NOT IN ('cancel', 'followup') THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose an enquiry action';
            EXIT body;
        END IF;

        v_enquiry_text := btrim(COALESCE(p_payload->>'product_enquiry_id', ''));
        IF v_enquiry_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose an enquiry';
            EXIT body;
        END IF;
        v_enquiry_id := v_enquiry_text::BIGINT;

        v_note := NULLIF(btrim(COALESCE(p_payload->>'note', '')), '');
        IF v_note IS NOT NULL AND char_length(v_note) > 1000 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Note must be 1000 characters or fewer';
            EXIT body;
        END IF;

        SELECT enquiry.enquiry_no, status_row.data_code, enquiry.assigned_agent_user_id
          INTO v_enquiry_no, v_status_code, v_agent_id
          FROM solar_app.product_enquiry_details AS enquiry
          JOIN solar_app.ref_data AS status_row
            ON status_row.ref_data_id = enquiry.status_ref_data_id
         WHERE enquiry.product_enquiry_id = v_enquiry_id
           AND enquiry.user_id = v_user_id
           AND enquiry.active_ind IS TRUE;

        IF NOT FOUND THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This enquiry was not found';
            EXIT body;
        END IF;

        IF v_status_code = 'ENQ_CONVERTED' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'This enquiry has already moved to a lead';
            EXIT body;
        END IF;

        IF v_status_code = 'ENQ_CLOSED' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'This enquiry is already closed';
            EXIT body;
        END IF;

        IF v_status_code NOT IN ('ENQ_OPEN', 'ENQ_IN_PROGRESS') THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'This enquiry cannot be updated';
            EXIT body;
        END IF;

        IF v_action = 'cancel' THEN
            SELECT ref_row.ref_data_id
              INTO v_closed_id
              FROM solar_app.ref_data AS ref_row
              JOIN solar_app.ref_data_categories AS category
                ON category.category_id = ref_row.category_id
             WHERE category.category_code = 'PRODUCT_ENQUIRY_STATUSES'
               AND ref_row.data_code = 'ENQ_CLOSED'
               AND ref_row.active_ind IS TRUE
               AND category.active_ind IS TRUE;

            IF v_closed_id IS NULL THEN
                v_status := 'ERROR';
                v_code := 500;
                v_message := 'Enquiry could not be cancelled';
                v_log_error := 'ENQ_CLOSED is not configured';
                EXIT body;
            END IF;

            UPDATE solar_app.product_enquiry_details
               SET status_ref_data_id = v_closed_id,
                   updated_by = v_actor,
                   updated_on = CURRENT_TIMESTAMP
             WHERE product_enquiry_id = v_enquiry_id
               AND user_id = v_user_id
               AND active_ind IS TRUE;

            v_message := 'Enquiry cancelled';
            v_data := jsonb_build_object(
                'product_enquiry_id', v_enquiry_id::TEXT,
                'enquiry_no', v_enquiry_no,
                'status_code', 'ENQ_CLOSED',
                'status_name', 'Closed'
            );
            EXIT body;
        END IF;

        IF v_agent_id IS NULL OR NOT EXISTS (
            SELECT 1
              FROM solar_app.user_details AS agent
             WHERE agent.user_id = v_agent_id
               AND agent.active_ind IS TRUE
        ) THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'An engineer has not been assigned yet';
            EXIT body;
        END IF;

        SELECT EXISTS (
            SELECT 1
              FROM solar_app.followup_details AS followup
              JOIN solar_app.ref_data AS followup_status
                ON followup_status.ref_data_id = followup.status_ref_data_id
             WHERE followup.product_enquiry_id = v_enquiry_id
               AND followup.entity_type = 'ENQUIRY'
               AND followup.active_ind IS TRUE
               AND followup_status.data_code = 'FU_OPEN'
        )
          INTO v_open_exists;

        IF v_open_exists THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'A follow-up is already open for this enquiry';
            EXIT body;
        END IF;

        SELECT ref_row.ref_data_id
          INTO v_type_id
          FROM solar_app.ref_data AS ref_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = ref_row.category_id
         WHERE category.category_code = 'FOLLOWUP_TYPES'
           AND ref_row.data_code = 'FU_CALL'
           AND ref_row.active_ind IS TRUE
           AND category.active_ind IS TRUE;

        SELECT ref_row.ref_data_id
          INTO v_open_id
          FROM solar_app.ref_data AS ref_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = ref_row.category_id
         WHERE category.category_code = 'FOLLOWUP_STATUSES'
           AND ref_row.data_code = 'FU_OPEN'
           AND ref_row.active_ind IS TRUE
           AND category.active_ind IS TRUE;

        IF v_type_id IS NULL OR v_open_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Follow-up could not be requested';
            v_log_error := 'Follow-up reference data is not configured';
            EXIT body;
        END IF;

        INSERT INTO solar_app.followup_details (
            entity_type,
            product_enquiry_id,
            followup_type_ref_data_id,
            status_ref_data_id,
            assigned_to_user_id,
            due_on,
            notes,
            created_by,
            updated_by
        ) VALUES (
            'ENQUIRY',
            v_enquiry_id,
            v_type_id,
            v_open_id,
            v_agent_id,
            CURRENT_TIMESTAMP,
            COALESCE(v_note, 'Customer requested a follow-up.'),
            v_actor,
            v_actor
        )
        RETURNING followup_id INTO v_followup_id;

        v_message := 'Follow-up requested';
        v_data := jsonb_build_object(
            'product_enquiry_id', v_enquiry_id::TEXT,
            'enquiry_no', v_enquiry_no,
            'followup_id', v_followup_id::TEXT
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Enquiry could not be updated';
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
            'fn_update_product_enquiry_details',
            v_actor,
            v_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'action', v_action,
                'product_enquiry_id', v_enquiry_id
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

COMMENT ON FUNCTION solar_app.fn_update_product_enquiry_details(JSONB) IS
    'Lets the session user cancel their own open enquiry or request a follow-up from the assigned engineer.';
