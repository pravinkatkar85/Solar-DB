-- Lists preventive service requests owned by the signed-in user's customer.
-- A payload user id is not trusted. Complaint tickets are not included.

CREATE OR REPLACE FUNCTION solar_app.fn_get_service_request_details(p_payload JSONB)
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
    v_message       TEXT := 'Service requests loaded';
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
    v_customer_id   BIGINT;
    v_request_text  TEXT;
    v_request_id    BIGINT;
    v_rows          JSONB;
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

        SELECT app_user.active_ind, account_row.data_code
          INTO v_active, v_account_code
          FROM solar_app.user_details AS app_user
          LEFT JOIN solar_app.ref_data AS account_row
            ON account_row.ref_data_id = app_user.account_status_ref_data_id
         WHERE app_user.user_id = v_user_id;

        IF NOT FOUND OR v_active IS NOT TRUE OR v_account_code = 'ACCT_SUSPENDED' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'This account cannot view service requests';
            EXIT body;
        END IF;

        v_request_text := NULLIF(btrim(COALESCE(p_payload->>'service_request_id', '')), '');
        IF v_request_text IS NOT NULL AND v_request_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose a service request';
            EXIT body;
        END IF;
        IF v_request_text IS NOT NULL THEN
            v_request_id := v_request_text::BIGINT;
        END IF;

        SELECT customer.customer_id
          INTO v_customer_id
          FROM solar_app.customer_details AS customer
         WHERE customer.user_id = v_user_id
           AND customer.active_ind IS TRUE;

        SELECT COALESCE(jsonb_agg(listed.item ORDER BY listed.created_on DESC), '[]'::jsonb)
          INTO v_rows
          FROM (
                SELECT request.created_on,
                       jsonb_build_object(
                           'service_request_id', request.service_request_id::TEXT,
                           'service_request_no', request.service_request_no,
                           'site_id', request.site_id::TEXT,
                           'site_name', site.site_name,
                           'service_type_name', type_row.data_value,
                           'slot_name', slot_row.data_value,
                           'status_code', status_row.data_code,
                           'status_name', status_row.data_value,
                           'preferred_on', to_char(request.preferred_on, 'YYYY-MM-DD'),
                           'technician_name', engineer.full_name,
                           'technician_mobile', engineer.mobile_e164,
                           'arrival_status', request.arrival_status,
                           'completion_notes', request.completion_notes,
                           'created_on', to_char(request.created_on AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                       ) AS item
                  FROM solar_app.service_request_details AS request
                  JOIN solar_app.site_details AS site
                    ON site.site_id = request.site_id
                   AND site.customer_id = request.customer_id
                  LEFT JOIN solar_app.ref_data AS type_row
                    ON type_row.ref_data_id = request.service_type_ref_data_id
                  LEFT JOIN solar_app.ref_data AS slot_row
                    ON slot_row.ref_data_id = request.slot_window_ref_data_id
                  LEFT JOIN solar_app.ref_data AS status_row
                    ON status_row.ref_data_id = request.status_ref_data_id
                  LEFT JOIN solar_app.technician_details AS technician
                    ON technician.technician_id = request.technician_id
                   AND technician.active_ind IS TRUE
                  LEFT JOIN solar_app.user_details AS engineer
                    ON engineer.user_id = technician.user_id
                   AND engineer.active_ind IS TRUE
                 WHERE request.customer_id = v_customer_id
                   AND request.active_ind IS TRUE
                   AND (v_request_id IS NULL OR request.service_request_id = v_request_id)
               ) AS listed;

        IF v_request_id IS NOT NULL AND v_rows = '[]'::jsonb THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This service request was not found';
            EXIT body;
        END IF;

        v_data := jsonb_build_object('service_requests', v_rows);
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Service requests could not be loaded';
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
            'fn_get_service_request_details',
            v_actor,
            v_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'service_request_id', v_request_id
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

COMMENT ON FUNCTION solar_app.fn_get_service_request_details(JSONB) IS
    'Returns active preventive service requests for the session customer. Complaint tickets are not included.';
