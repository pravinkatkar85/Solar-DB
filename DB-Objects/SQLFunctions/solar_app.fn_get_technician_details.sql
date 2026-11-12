-- Admin lists technician profiles (technician_details + user_details identity).
-- Session identity and ROLE_ADMIN come only from jwt_token_hash → log_user_sessions.
-- Payload role and ownership fields are not trusted.
-- Optional filters: active_ind, is_available.
-- Never returns pin_hash or other authentication secrets.
-- Do not install this file until separately approved.

CREATE OR REPLACE FUNCTION solar_app.fn_get_technician_details(p_payload JSONB)
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
    v_message       TEXT := 'Technicians loaded';
    v_data          JSONB := NULL;
    v_response      JSONB;
    v_log_error     TEXT;
    v_sql_state     VARCHAR(10);
    v_token_hash    TEXT;
    v_session_count INTEGER := 0;
    v_session_id    BIGINT;
    v_admin_user_id BIGINT;
    v_active        BOOLEAN;
    v_account_code  VARCHAR(50);
    v_role_code     VARCHAR(50);
    v_claimed       TEXT;
    v_filter_active BOOLEAN;
    v_filter_avail  BOOLEAN;
    v_active_text   TEXT;
    v_avail_text    TEXT;
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
            v_message := 'This account cannot view technicians';
            EXIT body;
        END IF;
        IF v_role_code IS DISTINCT FROM 'ROLE_ADMIN' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'Only an administrator can view technicians';
            EXIT body;
        END IF;

        v_active_text := NULLIF(btrim(COALESCE(p_payload->>'active_ind', '')), '');
        IF v_active_text IS NOT NULL THEN
            IF lower(v_active_text) NOT IN ('true', 'false')
               AND jsonb_typeof(p_payload->'active_ind') IS DISTINCT FROM 'boolean' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'active_ind is not valid';
                EXIT body;
            END IF;
            IF jsonb_typeof(p_payload->'active_ind') = 'boolean' THEN
                v_filter_active := (p_payload->>'active_ind')::BOOLEAN;
            ELSE
                v_filter_active := (lower(v_active_text) = 'true');
            END IF;
        END IF;

        v_avail_text := NULLIF(btrim(COALESCE(p_payload->>'is_available', '')), '');
        IF v_avail_text IS NOT NULL THEN
            IF lower(v_avail_text) NOT IN ('true', 'false')
               AND jsonb_typeof(p_payload->'is_available') IS DISTINCT FROM 'boolean' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'is_available is not valid';
                EXIT body;
            END IF;
            IF jsonb_typeof(p_payload->'is_available') = 'boolean' THEN
                v_filter_avail := (p_payload->>'is_available')::BOOLEAN;
            ELSE
                v_filter_avail := (lower(v_avail_text) = 'true');
            END IF;
        END IF;

        SELECT COALESCE(
            jsonb_agg(listed.item ORDER BY listed.employee_code, listed.technician_id),
            '[]'::jsonb
        )
          INTO v_rows
          FROM (
            SELECT
                tech.technician_id,
                tech.employee_code,
                jsonb_build_object(
                    'technician_id', tech.technician_id::TEXT,
                    'user_id', tech.user_id::TEXT,
                    'employee_code', tech.employee_code,
                    'full_name', COALESCE(app_user.full_name, ''),
                    'mobile_e164', app_user.mobile_e164,
                    'active_ind', tech.active_ind,
                    'is_available', tech.is_available
                ) AS item
              FROM solar_app.technician_details AS tech
              JOIN solar_app.user_details AS app_user
                ON app_user.user_id = tech.user_id
              LEFT JOIN solar_app.ref_data AS role_row
                ON role_row.ref_data_id = app_user.role_ref_data_id
             WHERE role_row.data_code IS NOT DISTINCT FROM 'ROLE_TECHNICIAN'
               AND (v_filter_active IS NULL OR tech.active_ind IS NOT DISTINCT FROM v_filter_active)
               AND (v_filter_avail IS NULL OR tech.is_available IS NOT DISTINCT FROM v_filter_avail)
          ) AS listed;

        v_data := jsonb_build_object('technicians', v_rows);
        IF jsonb_array_length(v_rows) = 0 THEN
            v_message := 'No technicians found';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Technicians could not be loaded';
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
            'fn_get_technician_details',
            v_actor,
            v_admin_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'active_ind', v_filter_active,
                'is_available', v_filter_avail
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

COMMENT ON FUNCTION solar_app.fn_get_technician_details(JSONB) IS
    'Admin lists technician_details with user identity fields. Optional active_ind and is_available filters. Never returns PIN or auth secrets.';
