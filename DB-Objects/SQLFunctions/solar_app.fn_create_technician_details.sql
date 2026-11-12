-- Admin creates one technician login (user_details) and 1:1 technician_details.
-- Session identity and ROLE_ADMIN come only from jwt_token_hash → log_user_sessions.
-- Payload role, technician_id, and ownership fields are not trusted.
-- Fixed server values: ROLE_TECHNICIAN, ACCT_ACTIVE, admin_registered = TRUE,
-- REG_ADMIN_POST_INSTALL, pin_hash = NULL.
-- Do not install this file until separately approved.

CREATE OR REPLACE FUNCTION solar_app.fn_create_technician_details(p_payload JSONB)
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
    v_message            TEXT := 'Technician created';
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
    v_country_id         BIGINT;
    v_phone_code         TEXT;
    v_min_length         INTEGER;
    v_max_length         INTEGER;
    v_phone_regex        TEXT;
    v_national           TEXT;
    v_mobile             TEXT;
    v_full_name          TEXT;
    v_email              TEXT;
    v_employee_code      TEXT;
    v_radius_text        TEXT;
    v_service_radius_km  NUMERIC(6,2);
    v_is_available       BOOLEAN := TRUE;
    v_role_id            BIGINT;
    v_acct_status_id     BIGINT;
    v_source_id          BIGINT;
    v_new_user_id        BIGINT;
    v_technician_id      BIGINT;
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

        IF NULLIF(btrim(COALESCE(p_payload->>'pin', '')), '') IS NOT NULL
           OR NULLIF(btrim(COALESCE(p_payload->>'pin_hash', '')), '') IS NOT NULL THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'PIN is not accepted for technician registration';
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
            v_message := 'This account cannot create technicians';
            EXIT body;
        END IF;
        IF v_role_code IS DISTINCT FROM 'ROLE_ADMIN' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'Only an administrator can create technicians';
            EXIT body;
        END IF;

        IF COALESCE(p_payload->>'country_id', '') !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'country_id is not valid';
            EXIT body;
        END IF;
        v_country_id := (p_payload->>'country_id')::BIGINT;

        SELECT country.phone_code,
               country.national_phone_min_length,
               country.national_phone_max_length,
               NULLIF(btrim(country.national_phone_regex), '')
          INTO v_phone_code, v_min_length, v_max_length, v_phone_regex
          FROM solar_app.ref_countries AS country
         WHERE country.country_id = v_country_id
           AND country.active_ind IS TRUE;
        IF NOT FOUND THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'country_id is not valid';
            EXIT body;
        END IF;

        v_national := regexp_replace(COALESCE(p_payload->>'national_number', ''), '\s', '', 'g');
        IF v_national !~ '^[0-9]+$'
           OR char_length(v_national) < v_min_length
           OR char_length(v_national) > v_max_length
           OR (v_phone_regex IS NOT NULL AND v_national !~ v_phone_regex) THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Enter a valid mobile number';
            EXIT body;
        END IF;
        v_mobile := v_phone_code || v_national;
        IF v_mobile !~ '^\+[1-9][0-9]{3,14}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Enter a valid mobile number';
            EXIT body;
        END IF;

        IF EXISTS (
            SELECT 1
              FROM solar_app.user_details AS app_user
             WHERE app_user.mobile_e164 = v_mobile
               AND app_user.active_ind IS TRUE
        ) THEN
            v_status := 'ERROR';
            v_code := 409;
            v_message := 'An account with this mobile number already exists';
            EXIT body;
        END IF;

        v_full_name := NULLIF(btrim(p_payload->>'full_name'), '');
        IF v_full_name IS NULL OR char_length(v_full_name) > 150 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Enter the technician name';
            EXIT body;
        END IF;

        v_email := NULLIF(btrim(p_payload->>'email'), '');
        IF v_email IS NOT NULL AND char_length(v_email) > 150 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'email must be 150 characters or fewer';
            EXIT body;
        END IF;

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
        ) THEN
            v_status := 'ERROR';
            v_code := 409;
            v_message := 'This employee code already exists';
            EXIT body;
        END IF;

        v_radius_text := NULLIF(btrim(COALESCE(p_payload->>'service_radius_km', '')), '');
        IF v_radius_text IS NOT NULL THEN
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

        IF p_payload ? 'is_available'
           AND p_payload->'is_available' IS NOT NULL
           AND jsonb_typeof(p_payload->'is_available') <> 'null' THEN
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

        SELECT ref_row.ref_data_id
          INTO v_role_id
          FROM solar_app.ref_data AS ref_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = ref_row.category_id
         WHERE category.category_code = 'USER_ROLES'
           AND ref_row.data_code = 'ROLE_TECHNICIAN'
           AND category.active_ind IS TRUE
           AND ref_row.active_ind IS TRUE;

        SELECT ref_row.ref_data_id
          INTO v_acct_status_id
          FROM solar_app.ref_data AS ref_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = ref_row.category_id
         WHERE category.category_code = 'USER_ACCOUNT_STATUSES'
           AND ref_row.data_code = 'ACCT_ACTIVE'
           AND category.active_ind IS TRUE
           AND ref_row.active_ind IS TRUE;

        SELECT ref_row.ref_data_id
          INTO v_source_id
          FROM solar_app.ref_data AS ref_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = ref_row.category_id
         WHERE category.category_code = 'REGISTRATION_SOURCES'
           AND ref_row.data_code = 'REG_ADMIN_POST_INSTALL'
           AND category.active_ind IS TRUE
           AND ref_row.active_ind IS TRUE;

        IF v_role_id IS NULL OR v_acct_status_id IS NULL OR v_source_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Technician could not be created';
            v_log_error := 'Required technician reference data is missing';
            EXIT body;
        END IF;

        INSERT INTO solar_app.user_details (
            country_id,
            mobile_e164,
            full_name,
            email,
            role_ref_data_id,
            pin_hash,
            admin_registered,
            account_status_ref_data_id,
            registration_source_ref_data_id,
            created_by,
            updated_by
        ) VALUES (
            v_country_id,
            v_mobile,
            v_full_name,
            v_email,
            v_role_id,
            NULL,
            TRUE,
            v_acct_status_id,
            v_source_id,
            v_actor,
            v_actor
        )
        RETURNING user_id INTO v_new_user_id;

        INSERT INTO solar_app.technician_details (
            user_id,
            employee_code,
            service_radius_km,
            is_available,
            created_by,
            updated_by
        ) VALUES (
            v_new_user_id,
            v_employee_code,
            v_service_radius_km,
            v_is_available,
            v_actor,
            v_actor
        )
        RETURNING technician_id INTO v_technician_id;

        v_data := jsonb_build_object(
            'technician_id', v_technician_id::TEXT,
            'user_id', v_new_user_id::TEXT,
            'employee_code', v_employee_code,
            'mobile_e164', v_mobile,
            'full_name', v_full_name,
            'is_available', v_is_available,
            'admin_registered', TRUE,
            'role_code', 'ROLE_TECHNICIAN'
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_status := 'ERROR';
            v_code := 409;
            v_message := 'Technician could not be created because a unique value already exists';
            v_data := NULL;
            v_log_error := SQLERRM;
            v_sql_state := SQLSTATE;
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Technician could not be created';
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
            'fn_create_technician_details',
            v_actor,
            v_admin_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'employee_code', v_employee_code,
                'country_id', v_country_id
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

COMMENT ON FUNCTION solar_app.fn_create_technician_details(JSONB) IS
    'Admin creates ROLE_TECHNICIAN user_details and 1:1 technician_details. admin_registered TRUE, pin_hash NULL, REG_ADMIN_POST_INSTALL.';
