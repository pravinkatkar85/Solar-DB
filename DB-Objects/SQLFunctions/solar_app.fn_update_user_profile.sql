-- Updates the signed-in user's email and secondary mobile.
-- A secondary number is the national number for the user's country.
-- Name, login mobile, role, emergency contact, language, push, and PIN stay unchanged.

CREATE OR REPLACE FUNCTION solar_app.fn_update_user_profile(p_payload JSONB)
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
    v_message        TEXT := 'Account updated';
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
    v_email          VARCHAR(150);
    v_secondary      VARCHAR(16);
    v_phone_code     VARCHAR(8);
    v_min_length     INTEGER;
    v_max_length     INTEGER;
    v_phone_regex    TEXT;
    v_national       TEXT;
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
            v_message := 'This account cannot be updated';
            EXIT body;
        END IF;

        v_email := NULLIF(btrim(COALESCE(p_payload->>'email', '')), '');
        IF v_email IS NOT NULL AND (
            char_length(v_email) > 150
            OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
        ) THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Enter a valid email address';
            EXIT body;
        END IF;

        v_national := regexp_replace(
            COALESCE(p_payload->>'secondary_national_number', ''),
            '\s',
            '',
            'g'
        );
        IF v_national <> '' THEN
            SELECT country.phone_code,
                   country.national_phone_min_length,
                   country.national_phone_max_length,
                   NULLIF(btrim(country.national_phone_regex), '')
              INTO v_phone_code, v_min_length, v_max_length, v_phone_regex
              FROM solar_app.user_details AS app_user
              JOIN solar_app.ref_countries AS country
                ON country.country_id = app_user.country_id
               AND country.active_ind IS TRUE
             WHERE app_user.user_id = v_user_id;

            IF v_phone_code IS NULL
               OR v_national !~ '^[0-9]+$'
               OR char_length(v_national) < v_min_length
               OR char_length(v_national) > v_max_length
               OR (v_phone_regex IS NOT NULL AND v_national !~ v_phone_regex) THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Enter a valid mobile number';
                EXIT body;
            END IF;

            v_secondary := v_phone_code || v_national;
            IF v_secondary !~ '^\+[1-9][0-9]{3,14}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Enter a valid mobile number';
                EXIT body;
            END IF;
        END IF;

        UPDATE solar_app.user_details
           SET email = v_email,
               secondary_mobile_e164 = v_secondary,
               updated_by = v_actor,
               updated_on = clock_timestamp()
         WHERE user_id = v_user_id
           AND active_ind IS TRUE;

        SELECT jsonb_build_object(
            'full_name', COALESCE(app_user.full_name, ''),
            'mobile_e164', app_user.mobile_e164,
            'email', app_user.email,
            'secondary_mobile_e164', app_user.secondary_mobile_e164,
            'emergency_contact_name', app_user.emergency_contact_name,
            'emergency_contact_mobile_e164', app_user.emergency_contact_mobile_e164,
            'role_name', COALESCE(role_row.data_value, ''),
            'preferred_language_id', language_row.ref_data_id::TEXT,
            'preferred_language_name', language_row.data_value,
            'push_notifications_enabled', app_user.push_notifications_enabled,
            'customer_code', customer.customer_code,
            'billing_name', customer.billing_name,
            'phone_code', country.phone_code,
            'national_phone_min_length', country.national_phone_min_length,
            'national_phone_max_length', country.national_phone_max_length,
            'national_phone_regex', NULLIF(btrim(country.national_phone_regex), ''),
            'secondary_national_number', CASE
                WHEN app_user.secondary_mobile_e164 IS NOT NULL
                 AND country.phone_code IS NOT NULL
                 AND starts_with(app_user.secondary_mobile_e164, country.phone_code)
                THEN substr(
                    app_user.secondary_mobile_e164,
                    char_length(country.phone_code) + 1
                )
                ELSE NULL
            END
        )
          INTO v_data
          FROM solar_app.user_details AS app_user
          LEFT JOIN solar_app.ref_data AS role_row
            ON role_row.ref_data_id = app_user.role_ref_data_id
          LEFT JOIN solar_app.ref_data AS language_row
            ON language_row.ref_data_id = app_user.preferred_language_ref_data_id
          LEFT JOIN solar_app.ref_countries AS country
            ON country.country_id = app_user.country_id
           AND country.active_ind IS TRUE
          LEFT JOIN solar_app.customer_details AS customer
            ON customer.user_id = app_user.user_id
           AND customer.active_ind IS TRUE
         WHERE app_user.user_id = v_user_id;
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Account could not be updated';
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
            'fn_update_user_profile',
            v_actor,
            v_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id
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

COMMENT ON FUNCTION solar_app.fn_update_user_profile(JSONB) IS
    'Updates the signed-in user email, second mobile, emergency contact, language, and push toggle. Name, login mobile, role, and PIN stay unchanged.';
