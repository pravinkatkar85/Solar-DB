-- Development tests for solar_app.fn_update_user_pin.
--
-- Safety:
--   * Runs in one transaction and ends with ROLLBACK.
--   * Creates a temporary user and session through the PIN functions, then
--     rolls both back. It does not keep users, hashes, or audit rows.
--   * Notices report pass or a code only. They do not print a PIN or hash.
--   * Run only against a development database that already has 01_schema.sql,
--     02_functions.sql, and 03_seed_data.sql applied, and only with approval.
--
--   psql -d SolarDB -v ON_ERROR_STOP=1 -f SQLScripts/06_test_fn_update_user_pin.sql

BEGIN;

DO $test$
DECLARE
    v_result       JSONB;
    v_country_id   BIGINT;
    v_user_id      BIGINT;
    v_status_id    BIGINT;
    v_suspended_id BIGINT;
    v_national     TEXT;
    v_hash         TEXT;
    v_other_hash   TEXT;
    v_old_pin      CONSTANT TEXT := '1357';
    v_new_pin      CONSTANT TEXT := '2468';
    v_endpoint     CONSTANT TEXT := '/api/auth/change-pin';
    v_attempt      INTEGER := 0;
    v_hash_ok      BOOLEAN;
BEGIN
    IF to_regprocedure('solar_app.fn_update_user_pin(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'Install SQLScripts/02_functions.sql before running this test';
    END IF;

    SELECT country_id
      INTO v_country_id
      FROM solar_app.ref_countries
     WHERE country_code = 'IN'
       AND active_ind IS TRUE;

    IF v_country_id IS NULL THEN
        RAISE EXCEPTION 'Canonical seed must include active country IN';
    END IF;

    LOOP
        v_attempt := v_attempt + 1;
        IF v_attempt > 5 THEN
            RAISE EXCEPTION 'test account was not created';
        END IF;

        v_national := '9' || lpad((floor(random() * 1000000000))::BIGINT::TEXT, 9, '0');
        v_result := solar_app.fn_create_pin_user(jsonb_build_object(
            'api_endpoint', '/api/auth/register',
            'country_id', v_country_id::TEXT,
            'national_number', v_national,
            'full_name', 'PIN Change Test',
            'pin', v_old_pin
        ));
        EXIT WHEN (v_result->>'code')::INTEGER = 200;
        IF (v_result->>'code')::INTEGER IS DISTINCT FROM 409 THEN
            RAISE EXCEPTION 'test account was not created, code %', v_result->>'code';
        END IF;
    END LOOP;

    v_user_id := (v_result #>> '{data,user_id}')::BIGINT;
    v_hash := encode(public.digest('pin-change-test-' || v_user_id::TEXT || clock_timestamp()::TEXT, 'sha256'), 'hex');
    v_other_hash := encode(public.digest('missing-session-' || clock_timestamp()::TEXT, 'sha256'), 'hex');

    v_result := solar_app.fn_create_pin_session(jsonb_build_object(
        'api_endpoint', '/api/auth/login',
        'country_id', v_country_id::TEXT,
        'national_number', v_national,
        'pin', v_old_pin,
        'jwt_token_hash', v_hash
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 200 THEN
        RAISE EXCEPTION 'test session was not created, code %', v_result->>'code';
    END IF;

    v_result := solar_app.fn_update_user_pin(NULL);
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 400 THEN
        RAISE EXCEPTION 'null payload code %', v_result->>'code';
    END IF;

    v_result := solar_app.fn_update_user_pin(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'old_pin', v_old_pin,
        'new_pin', v_new_pin,
        'confirm_pin', v_new_pin
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 400 THEN
        RAISE EXCEPTION 'missing session hash code %', v_result->>'code';
    END IF;

    v_result := solar_app.fn_update_user_pin(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'jwt_token_hash', v_other_hash,
        'old_pin', v_old_pin,
        'new_pin', v_new_pin,
        'confirm_pin', v_new_pin
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 401
       OR v_result->>'message' IS DISTINCT FROM 'Authentication is required' THEN
        RAISE EXCEPTION 'unknown session code %', v_result->>'code';
    END IF;

    v_result := solar_app.fn_update_user_pin(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'jwt_token_hash', v_hash,
        'user_id', v_user_id::TEXT || '0',
        'old_pin', v_old_pin,
        'new_pin', v_new_pin,
        'confirm_pin', v_new_pin
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 401 THEN
        RAISE EXCEPTION 'payload user id was trusted, code %', v_result->>'code';
    END IF;

    v_result := solar_app.fn_update_user_pin(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'jwt_token_hash', v_hash,
        'logged_in_user_id', v_user_id::TEXT || '0',
        'old_pin', v_old_pin,
        'new_pin', v_new_pin,
        'confirm_pin', v_new_pin
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 401 THEN
        RAISE EXCEPTION 'payload logged_in_user_id was trusted, code %', v_result->>'code';
    END IF;

    v_result := solar_app.fn_update_user_pin(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'jwt_token_hash', v_hash,
        'old_pin', '12',
        'new_pin', v_new_pin,
        'confirm_pin', v_new_pin
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 400
       OR v_result->>'message' IS DISTINCT FROM 'PIN must be 4 digits' THEN
        RAISE EXCEPTION 'invalid PIN code %', v_result->>'code';
    END IF;

    v_result := solar_app.fn_update_user_pin(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'jwt_token_hash', v_hash,
        'old_pin', v_old_pin,
        'new_pin', v_new_pin,
        'confirm_pin', '2469'
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 400
       OR v_result->>'message' IS DISTINCT FROM 'PIN entries do not match' THEN
        RAISE EXCEPTION 'mismatched confirmation code %', v_result->>'code';
    END IF;

    v_result := solar_app.fn_update_user_pin(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'jwt_token_hash', v_hash,
        'old_pin', '9999',
        'new_pin', v_new_pin,
        'confirm_pin', v_new_pin
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 401
       OR v_result->>'message' IS DISTINCT FROM 'The current PIN is incorrect' THEN
        RAISE EXCEPTION 'wrong current PIN code %', v_result->>'code';
    END IF;

    SELECT pin_hash IS NOT DISTINCT FROM public.crypt(v_old_pin, pin_hash)
      INTO v_hash_ok
      FROM solar_app.user_details
     WHERE user_id = v_user_id;
    IF v_hash_ok IS NOT TRUE THEN
        RAISE EXCEPTION 'rejected changes replaced the stored PIN hash';
    END IF;

    UPDATE solar_app.log_user_sessions
       SET session_status = 'LOGGED_OUT',
           updated_on = clock_timestamp()
     WHERE jwt_token_hash = v_hash;

    v_result := solar_app.fn_update_user_pin(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'jwt_token_hash', v_hash,
        'old_pin', v_old_pin,
        'new_pin', v_new_pin,
        'confirm_pin', v_new_pin
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 401 THEN
        RAISE EXCEPTION 'logged-out session code %', v_result->>'code';
    END IF;

    UPDATE solar_app.log_user_sessions
       SET session_status = 'ACTIVE',
           updated_on = clock_timestamp()
     WHERE jwt_token_hash = v_hash;

    UPDATE solar_app.user_details
       SET active_ind = FALSE,
           updated_on = clock_timestamp()
     WHERE user_id = v_user_id;

    v_result := solar_app.fn_update_user_pin(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'jwt_token_hash', v_hash,
        'old_pin', v_old_pin,
        'new_pin', v_new_pin,
        'confirm_pin', v_new_pin
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 403 THEN
        RAISE EXCEPTION 'inactive account code %', v_result->>'code';
    END IF;

    UPDATE solar_app.user_details
       SET active_ind = TRUE,
           updated_on = clock_timestamp()
     WHERE user_id = v_user_id;

    SELECT account_status_ref_data_id
      INTO v_status_id
      FROM solar_app.user_details
     WHERE user_id = v_user_id;

    SELECT ref_row.ref_data_id
      INTO v_suspended_id
      FROM solar_app.ref_data AS ref_row
      JOIN solar_app.ref_data_categories AS category
        ON category.category_id = ref_row.category_id
     WHERE category.category_code = 'USER_ACCOUNT_STATUSES'
       AND ref_row.data_code = 'ACCT_SUSPENDED'
       AND category.active_ind IS TRUE
       AND ref_row.active_ind IS TRUE;

    IF v_suspended_id IS NULL THEN
        RAISE EXCEPTION 'Canonical seed must include ACCT_SUSPENDED';
    END IF;

    UPDATE solar_app.user_details
       SET account_status_ref_data_id = v_suspended_id,
           updated_on = clock_timestamp()
     WHERE user_id = v_user_id;

    v_result := solar_app.fn_update_user_pin(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'jwt_token_hash', v_hash,
        'old_pin', v_old_pin,
        'new_pin', v_new_pin,
        'confirm_pin', v_new_pin
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 403 THEN
        RAISE EXCEPTION 'suspended account code %', v_result->>'code';
    END IF;

    UPDATE solar_app.user_details
       SET account_status_ref_data_id = v_status_id,
           updated_on = clock_timestamp()
     WHERE user_id = v_user_id;

    v_result := solar_app.fn_update_user_pin(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'jwt_token_hash', v_hash,
        'logged_in_user_id', v_user_id::TEXT,
        'old_pin', v_old_pin,
        'new_pin', v_new_pin,
        'confirm_pin', v_new_pin
    ));
    IF v_result->>'status' IS DISTINCT FROM 'SUCCESS'
       OR (v_result->>'code')::INTEGER IS DISTINCT FROM 200
       OR v_result->>'message' IS DISTINCT FROM 'PIN updated'
       OR v_result #>> '{data,user_id}' IS DISTINCT FROM v_user_id::TEXT
       OR (v_result->'data') ? 'pin'
       OR (v_result->'data') ? 'pin_hash'
       OR (SELECT COUNT(*) FROM jsonb_object_keys(v_result->'data')) IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'valid PIN change code %', v_result->>'code';
    END IF;

    SELECT pin_hash IS NOT DISTINCT FROM public.crypt(v_new_pin, pin_hash)
       AND pin_hash IS DISTINCT FROM public.crypt(v_old_pin, pin_hash)
      INTO v_hash_ok
      FROM solar_app.user_details
     WHERE user_id = v_user_id;
    IF v_hash_ok IS NOT TRUE THEN
        RAISE EXCEPTION 'stored PIN hash did not match the new PIN';
    END IF;

    v_result := solar_app.fn_create_pin_session(jsonb_build_object(
        'api_endpoint', '/api/auth/login',
        'country_id', v_country_id::TEXT,
        'national_number', v_national,
        'pin', v_old_pin,
        'jwt_token_hash', v_other_hash
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 401 THEN
        RAISE EXCEPTION 'old PIN still signed in, code %', v_result->>'code';
    END IF;

    v_result := solar_app.fn_create_pin_session(jsonb_build_object(
        'api_endpoint', '/api/auth/login',
        'country_id', v_country_id::TEXT,
        'national_number', v_national,
        'pin', v_new_pin,
        'jwt_token_hash', encode(public.digest('pin-change-login-' || v_user_id::TEXT, 'sha256'), 'hex')
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 200 THEN
        RAISE EXCEPTION 'new PIN did not sign in, code %', v_result->>'code';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM solar_app.log_sql_functions
         WHERE function_name = 'fn_update_user_pin'
           AND (
                COALESCE(request_payload::TEXT, '') LIKE '%' || v_old_pin || '%'
             OR COALESCE(request_payload::TEXT, '') LIKE '%' || v_new_pin || '%'
             OR COALESCE(request_payload::TEXT, '') LIKE '%9999%'
             OR COALESCE(request_payload::TEXT, '') LIKE '%2469%'
             OR COALESCE(request_payload::TEXT, '') LIKE '%' || v_hash || '%'
             OR COALESCE(error_message, '') LIKE '%' || v_old_pin || '%'
             OR COALESCE(error_message, '') LIKE '%' || v_new_pin || '%'
             OR COALESCE(error_message, '') LIKE '%9999%'
             OR COALESCE(error_message, '') LIKE '%2469%'
           )
    ) THEN
        RAISE EXCEPTION 'function log stored a PIN or session hash';
    END IF;

    RAISE NOTICE 'fn_update_user_pin tests passed';
END
$test$;

ROLLBACK;
