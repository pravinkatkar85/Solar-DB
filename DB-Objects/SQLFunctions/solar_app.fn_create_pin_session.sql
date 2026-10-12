-- Authored source for solar_app.fn_create_pin_session.
-- Loaded by SQLScripts/02_functions.sql. Do not duplicate this body there.
--
-- Verifies a national mobile number and PIN. On success, stores only the
-- caller-supplied SHA-256 hash of the session token. The plaintext PIN and
-- the raw token are never written to a table or to the function log.

CREATE OR REPLACE FUNCTION solar_app.fn_create_pin_session(p_payload JSONB)
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
    v_message        TEXT := 'Signed in';
    v_data           JSONB := NULL;
    v_response       JSONB;
    v_log_error      TEXT;
    v_sql_state      VARCHAR(10);
    v_country_id     BIGINT;
    v_phone_code     VARCHAR(8);
    v_min_length     SMALLINT;
    v_max_length     SMALLINT;
    v_phone_regex    VARCHAR(255);
    v_national       TEXT;
    v_mobile         VARCHAR(16);
    v_pin            TEXT;
    v_token_hash     TEXT;
    v_user_id        BIGINT;
    v_full_name      VARCHAR(150);
    v_pin_hash       VARCHAR(255);
    v_active         BOOLEAN;
    v_lockout        TIMESTAMPTZ;
    v_account_code   VARCHAR(50);
    v_role_code      VARCHAR(50);
    v_role_name      VARCHAR(150);
    v_session_id     BIGINT;
    v_log_payload    JSONB;
    v_invalid        BOOLEAN := FALSE;
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

        IF COALESCE(p_payload->>'country_id', '') !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'country_id is not valid';
            EXIT body;
        END IF;
        v_country_id := (p_payload->>'country_id')::BIGINT;

        v_token_hash := COALESCE(p_payload->>'jwt_token_hash', '');
        IF v_token_hash !~ '^[a-f0-9]{64}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Session token is not valid';
            EXIT body;
        END IF;

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
        v_pin := COALESCE(p_payload->>'pin', '');
        IF v_national !~ '^[0-9]+$'
           OR char_length(v_national) < v_min_length
           OR char_length(v_national) > v_max_length
           OR (v_phone_regex IS NOT NULL AND v_national !~ v_phone_regex)
           OR v_pin !~ '^[0-9]{4}$' THEN
            v_invalid := TRUE;
            EXIT body;
        END IF;

        v_mobile := v_phone_code || v_national;

        SELECT app_user.user_id,
               app_user.full_name,
               app_user.pin_hash,
               app_user.active_ind,
               app_user.lockout_until,
               account_row.data_code,
               role_row.data_code,
               role_row.data_value
          INTO v_user_id,
               v_full_name,
               v_pin_hash,
               v_active,
               v_lockout,
               v_account_code,
               v_role_code,
               v_role_name
          FROM solar_app.user_details AS app_user
          JOIN solar_app.ref_data AS role_row
            ON role_row.ref_data_id = app_user.role_ref_data_id
          LEFT JOIN solar_app.ref_data AS account_row
            ON account_row.ref_data_id = app_user.account_status_ref_data_id
         WHERE app_user.mobile_e164 = v_mobile
           AND app_user.country_id = v_country_id;

        IF NOT FOUND
           OR v_active IS NOT TRUE
           OR v_pin_hash IS NULL
           OR v_account_code = 'ACCT_SUSPENDED'
           OR (v_lockout IS NOT NULL AND v_lockout > clock_timestamp())
           OR v_pin_hash IS DISTINCT FROM public.crypt(v_pin, v_pin_hash) THEN
            v_invalid := TRUE;
            EXIT body;
        END IF;

        v_actor := v_user_id::TEXT;

        INSERT INTO solar_app.log_user_sessions (
            user_id,
            mobile_e164,
            jwt_token_hash,
            session_status,
            login_on,
            last_seen_on,
            created_by,
            updated_by
        ) VALUES (
            v_user_id,
            v_mobile,
            v_token_hash,
            'ACTIVE',
            clock_timestamp(),
            clock_timestamp(),
            v_actor,
            v_actor
        )
        RETURNING session_id INTO v_session_id;

        UPDATE solar_app.user_details
           SET last_login_on = clock_timestamp(),
               updated_by = v_actor,
               updated_on = clock_timestamp()
         WHERE user_id = v_user_id;

        v_data := jsonb_build_object(
            'user_id', v_user_id::TEXT,
            'full_name', COALESCE(v_full_name, ''),
            'role_code', v_role_code,
            'role_name', v_role_name,
            'session_id', v_session_id::TEXT
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Sign-in could not be completed';
            v_data := NULL;
            v_invalid := FALSE;
            v_log_error := SQLERRM;
            v_sql_state := SQLSTATE;
    END;

    IF v_invalid THEN
        v_status := 'ERROR';
        v_code := 401;
        v_message := 'The mobile number or PIN is incorrect';
        v_data := NULL;
        v_user_id := NULL;
    END IF;

    v_response := jsonb_build_object(
        'status', v_status,
        'code', v_code,
        'message', v_message,
        'data', v_data
    );

    IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
        v_log_payload := NULL;
    ELSE
        v_log_payload := jsonb_strip_nulls(jsonb_build_object(
            'api_endpoint', p_payload->>'api_endpoint',
            'country_id', p_payload->>'country_id'
        ));
    END IF;

    BEGIN
        INSERT INTO solar_app.log_sql_functions (
            api_endpoint,
            function_name,
            logged_in_user_id,
            user_id,
            request_payload,
            execution_status,
            error_message,
            sql_state,
            execution_time_ms,
            created_by,
            updated_by
        ) VALUES (
            v_api_endpoint,
            'fn_create_pin_session',
            v_actor,
            v_user_id,
            v_log_payload,
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

COMMENT ON FUNCTION solar_app.fn_create_pin_session(JSONB) IS
    'Verifies a 4-digit PIN with pgcrypto and records an active session hash.';
