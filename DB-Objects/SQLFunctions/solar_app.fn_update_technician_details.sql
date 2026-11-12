-- Admin updates one technician profile, availability, or activation.
-- Session identity and ROLE_ADMIN come only from jwt_token_hash → log_user_sessions.
-- Payload role and ownership fields are not trusted.
-- Soft-deactivation sets technician_details.active_ind and matching user_details.active_ind.
-- Do not install this file until separately approved.

CREATE OR REPLACE FUNCTION solar_app.fn_update_technician_details(p_payload JSONB)
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
    v_message            TEXT := 'Technician updated';
    v_data               JSONB := NULL;
    v_response           JSONB;
    v_log_error          TEXT;
    v_sql_state          VARCHAR(10);
    v_token_hash         TEXT;
    v_session_count      INTEGER := 0;
    v_session_id         BIGINT;
    v_admin_user_id      BIGINT;
    v_active             BOOLEAN;
    v_account_code       VARCHAR(50);
    v_role_code          VARCHAR(50);
    v_claimed            TEXT;
    v_tech_text          TEXT;
    v_technician_id      BIGINT;
    v_tech_user_id       BIGINT;
    v_full_name          TEXT;
    v_email              TEXT;
    v_employee_code      TEXT;
    v_radius_text        TEXT;
    v_service_radius_km  NUMERIC(6,2);
    v_set_radius         BOOLEAN := FALSE;
    v_is_available       BOOLEAN;
    v_set_available      BOOLEAN := FALSE;
    v_active_ind         BOOLEAN;
    v_set_active         BOOLEAN := FALSE;
    v_updated            INTEGER := 0;
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
            v_message := 'This account cannot update technicians';
            EXIT body;
        END IF;
        IF v_role_code IS DISTINCT FROM 'ROLE_ADMIN' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'Only an administrator can update technicians';
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

        SELECT tech.user_id
          INTO v_tech_user_id
          FROM solar_app.technician_details AS tech
          JOIN solar_app.user_details AS app_user
            ON app_user.user_id = tech.user_id
          JOIN solar_app.ref_data AS role_row
            ON role_row.ref_data_id = app_user.role_ref_data_id
         WHERE tech.technician_id = v_technician_id
           AND role_row.data_code = 'ROLE_TECHNICIAN';
        IF v_tech_user_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This technician was not found';
            EXIT body;
        END IF;

        IF p_payload ? 'full_name' THEN
            v_full_name := NULLIF(btrim(p_payload->>'full_name'), '');
            IF v_full_name IS NULL OR char_length(v_full_name) > 150 THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Enter the technician name';
                EXIT body;
            END IF;
        END IF;

        IF p_payload ? 'email' THEN
            v_email := NULLIF(btrim(p_payload->>'email'), '');
            IF v_email IS NOT NULL AND char_length(v_email) > 150 THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'email must be 150 characters or fewer';
                EXIT body;
            END IF;
        END IF;

        IF p_payload ? 'employee_code' THEN
            v_employee_code := NULLIF(btrim(p_payload->>'employee_code'), '');
            IF v_employee_code IS NULL OR char_length(v_employee_code) > 30 THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Enter an employee code';
                EXIT body;
            END IF;
            IF EXISTS (
                SELECT 1
                  FROM solar_app.technician_details AS tech
                 WHERE tech.employee_code = v_employee_code
                   AND tech.technician_id IS DISTINCT FROM v_technician_id
            ) THEN
                v_status := 'ERROR';
                v_code := 409;
                v_message := 'This employee code already exists';
                EXIT body;
            END IF;
        END IF;

        IF p_payload ? 'service_radius_km' THEN
            v_set_radius := TRUE;
            v_radius_text := NULLIF(btrim(COALESCE(p_payload->>'service_radius_km', '')), '');
            IF v_radius_text IS NULL
               OR jsonb_typeof(p_payload->'service_radius_km') = 'null' THEN
                v_service_radius_km := NULL;
            ELSE
                IF v_radius_text !~ '^[0-9]+(\.[0-9]{1,2})?$' THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'service_radius_km is not valid';
                    EXIT body;
                END IF;
                v_service_radius_km := v_radius_text::NUMERIC(6,2);
                IF v_service_radius_km < 0 THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'service_radius_km is not valid';
                    EXIT body;
                END IF;
            END IF;
        END IF;

        IF p_payload ? 'is_available'
           AND p_payload->'is_available' IS NOT NULL
           AND jsonb_typeof(p_payload->'is_available') <> 'null' THEN
            v_set_available := TRUE;
            IF jsonb_typeof(p_payload->'is_available') = 'boolean' THEN
                v_is_available := (p_payload->>'is_available')::BOOLEAN;
            ELSIF lower(NULLIF(btrim(p_payload->>'is_available'), '')) IN ('true', 'false') THEN
                v_is_available := lower(btrim(p_payload->>'is_available')) = 'true';
            ELSE
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'is_available is not valid';
                EXIT body;
            END IF;
        END IF;

        IF p_payload ? 'active_ind'
           AND p_payload->'active_ind' IS NOT NULL
           AND jsonb_typeof(p_payload->'active_ind') <> 'null' THEN
            v_set_active := TRUE;
            IF jsonb_typeof(p_payload->'active_ind') = 'boolean' THEN
                v_active_ind := (p_payload->>'active_ind')::BOOLEAN;
            ELSIF lower(NULLIF(btrim(p_payload->>'active_ind'), '')) IN ('true', 'false') THEN
                v_active_ind := lower(btrim(p_payload->>'active_ind')) = 'true';
            ELSE
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'active_ind is not valid';
                EXIT body;
            END IF;
        END IF;

        IF v_full_name IS NULL
           AND NOT (p_payload ? 'email')
           AND v_employee_code IS NULL
           AND NOT v_set_radius
           AND NOT v_set_available
           AND NOT v_set_active THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'No technician fields to update';
            EXIT body;
        END IF;

        UPDATE solar_app.user_details AS app_user
           SET full_name = COALESCE(v_full_name, app_user.full_name),
               email = CASE
                           WHEN p_payload ? 'email' THEN v_email
                           ELSE app_user.email
                       END,
               active_ind = CASE
                                WHEN v_set_active THEN v_active_ind
                                ELSE app_user.active_ind
                            END,
               updated_by = v_actor,
               updated_on = clock_timestamp()
         WHERE app_user.user_id = v_tech_user_id;
        GET DIAGNOSTICS v_updated = ROW_COUNT;
        IF v_updated IS DISTINCT FROM 1 THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This technician was not found';
            EXIT body;
        END IF;

        UPDATE solar_app.technician_details AS tech
           SET employee_code = COALESCE(v_employee_code, tech.employee_code),
               service_radius_km = CASE
                                       WHEN v_set_radius THEN v_service_radius_km
                                       ELSE tech.service_radius_km
                                   END,
               is_available = CASE
                                  WHEN v_set_available THEN v_is_available
                                  ELSE tech.is_available
                              END,
               active_ind = CASE
                                WHEN v_set_active THEN v_active_ind
                                ELSE tech.active_ind
                            END,
               updated_by = v_actor,
               updated_on = clock_timestamp()
         WHERE tech.technician_id = v_technician_id;
        GET DIAGNOSTICS v_updated = ROW_COUNT;
        IF v_updated IS DISTINCT FROM 1 THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This technician was not found';
            EXIT body;
        END IF;

        SELECT jsonb_build_object(
            'technician_id', tech.technician_id::TEXT,
            'user_id', tech.user_id::TEXT,
            'employee_code', tech.employee_code,
            'full_name', app_user.full_name,
            'email', app_user.email,
            'service_radius_km', tech.service_radius_km,
            'is_available', tech.is_available,
            'active_ind', tech.active_ind,
            'user_active_ind', app_user.active_ind
        )
          INTO v_data
          FROM solar_app.technician_details AS tech
          JOIN solar_app.user_details AS app_user
            ON app_user.user_id = tech.user_id
         WHERE tech.technician_id = v_technician_id;
    EXCEPTION
        WHEN unique_violation THEN
            v_status := 'ERROR';
            v_code := 409;
            v_message := 'Technician could not be updated because a unique value already exists';
            v_data := NULL;
            v_log_error := SQLERRM;
            v_sql_state := SQLSTATE;
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Technician could not be updated';
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
            'fn_update_technician_details',
            v_actor,
            v_admin_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'technician_id', v_technician_id,
                'is_available', CASE WHEN v_set_available THEN v_is_available ELSE NULL END,
                'active_ind', CASE WHEN v_set_active THEN v_active_ind ELSE NULL END
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

COMMENT ON FUNCTION solar_app.fn_update_technician_details(JSONB) IS
    'Admin updates technician profile, availability, and activation. Soft-deactivation syncs user_details.active_ind.';
