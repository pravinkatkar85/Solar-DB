-- Authored source for solar_app.fn_update_user_pin.
-- Loaded by SQLScripts/02_functions.sql. Do not duplicate this body there.
--
-- Changes the PIN of the user bound to an active session. Identity comes
-- from log_user_sessions.jwt_token_hash, not from a payload user id.
-- The old PIN is checked with pgcrypto bcrypt. Only the new hash is stored.

CREATE OR REPLACE FUNCTION solar_app.fn_update_user_pin(p_payload JSONB)
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
    v_message        TEXT := 'PIN updated';
    v_data           JSONB := NULL;
    v_response       JSONB;
    v_log_error      TEXT;
    v_sql_state      VARCHAR(10);
    v_token_hash     TEXT;
    v_session_count  INTEGER := 0;
    v_session_id     BIGINT;
    v_user_id        BIGINT;
    v_pin_hash       VARCHAR(255);
    v_active         BOOLEAN;
    v_account_code   VARCHAR(50);
    v_claimed        TEXT;
    v_old_pin        TEXT;
    v_new_pin        TEXT;
    v_confirm_pin    TEXT;
    v_updated        INTEGER := 0;
    v_log_payload    JSONB;
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

        SELECT session.session_id,
               session.user_id
          INTO v_session_id,
               v_user_id
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
        IF v_claimed IS NOT NULL AND v_claimed IS DISTINCT FROM v_user_id::TEXT THEN
            v_status := 'ERROR';
            v_code := 401;
            v_message := 'Authentication is required';
            EXIT body;
        END IF;

        SELECT app_user.pin_hash,
               app_user.active_ind,
               account_row.data_code
          INTO v_pin_hash,
               v_active,
               v_account_code
          FROM solar_app.user_details AS app_user
          LEFT JOIN solar_app.ref_data AS account_row
            ON account_row.ref_data_id = app_user.account_status_ref_data_id
         WHERE app_user.user_id = v_user_id;

        IF NOT FOUND OR v_active IS NOT TRUE OR v_account_code = 'ACCT_SUSPENDED' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'This account cannot change its PIN';
            EXIT body;
        END IF;

        v_old_pin := COALESCE(p_payload->>'old_pin', '');
        v_new_pin := COALESCE(p_payload->>'new_pin', '');
        v_confirm_pin := COALESCE(p_payload->>'confirm_pin', '');
        IF v_old_pin !~ '^[0-9]{4}$'
           OR v_new_pin !~ '^[0-9]{4}$'
           OR v_confirm_pin !~ '^[0-9]{4}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'PIN must be 4 digits';
            EXIT body;
        END IF;

        IF v_new_pin IS DISTINCT FROM v_confirm_pin THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'PIN entries do not match';
            EXIT body;
        END IF;

        IF v_pin_hash IS NULL
           OR v_pin_hash IS DISTINCT FROM public.crypt(v_old_pin, v_pin_hash) THEN
            v_status := 'ERROR';
            v_code := 401;
            v_message := 'The current PIN is incorrect';
            EXIT body;
        END IF;

        UPDATE solar_app.user_details
           SET pin_hash = public.crypt(v_new_pin, public.gen_salt('bf', 10)),
               updated_by = v_actor,
               updated_on = clock_timestamp()
         WHERE user_id = v_user_id
           AND active_ind IS TRUE
           AND pin_hash = v_pin_hash;

        GET DIAGNOSTICS v_updated = ROW_COUNT;
        IF v_updated IS DISTINCT FROM 1 THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'PIN could not be updated';
            v_log_error := 'PIN row was not updated';
            EXIT body;
        END IF;

        v_data := jsonb_build_object('user_id', v_user_id::TEXT);
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'PIN could not be updated';
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

    IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
        v_log_payload := NULL;
    ELSE
        v_log_payload := jsonb_strip_nulls(jsonb_build_object(
            'api_endpoint', p_payload->>'api_endpoint',
            'session_id', v_session_id
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
            'fn_update_user_pin',
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

COMMENT ON FUNCTION solar_app.fn_update_user_pin(JSONB) IS
    'Changes the signed-in user PIN after checking the current bcrypt hash. Stores only the new hash.';
