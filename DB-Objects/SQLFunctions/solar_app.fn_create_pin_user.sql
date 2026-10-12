-- Authored source for solar_app.fn_create_pin_user.
-- Loaded by SQLScripts/02_functions.sql. Do not duplicate this body there.
--
-- Creates one customer login in user_details. The PIN is hashed with
-- pgcrypto bcrypt and only the hash is stored. This is not the Path B
-- fn_create_user_details wizard.

CREATE OR REPLACE FUNCTION solar_app.fn_create_pin_user(p_payload JSONB)
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
    v_message        TEXT := 'Account created';
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
    v_full_name      VARCHAR(150);
    v_pin            TEXT;
    v_role_id        BIGINT;
    v_status_id      BIGINT;
    v_source_id      BIGINT;
    v_user_id        BIGINT;
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

        IF NULLIF(btrim(p_payload->>'logged_in_user_id'), '') IS NOT NULL THEN
            IF char_length(btrim(p_payload->>'logged_in_user_id')) > 50 THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'logged_in_user_id must be 50 characters or fewer';
                EXIT body;
            END IF;
            v_actor := btrim(p_payload->>'logged_in_user_id');
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

        v_full_name := NULLIF(btrim(p_payload->>'full_name'), '');
        IF v_full_name IS NULL OR char_length(v_full_name) > 150 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Enter your name';
            EXIT body;
        END IF;

        v_pin := COALESCE(p_payload->>'pin', '');
        IF v_pin !~ '^[0-9]{4}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'PIN must be 4 digits';
            EXIT body;
        END IF;

        SELECT ref_row.ref_data_id
          INTO v_role_id
          FROM solar_app.ref_data AS ref_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = ref_row.category_id
         WHERE category.category_code = 'USER_ROLES'
           AND ref_row.data_code = 'ROLE_CUSTOMER'
           AND category.active_ind IS TRUE
           AND ref_row.active_ind IS TRUE;

        SELECT ref_row.ref_data_id
          INTO v_status_id
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
           AND ref_row.data_code = 'REG_SELF_APP'
           AND category.active_ind IS TRUE
           AND ref_row.active_ind IS TRUE;

        IF v_role_id IS NULL OR v_status_id IS NULL OR v_source_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Account could not be created';
            v_log_error := 'Required reference data for PIN registration is missing';
            EXIT body;
        END IF;

        INSERT INTO solar_app.user_details (
            country_id,
            mobile_e164,
            full_name,
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
            v_role_id,
            public.crypt(v_pin, public.gen_salt('bf', 10)),
            TRUE,
            v_status_id,
            v_source_id,
            v_actor,
            v_actor
        )
        RETURNING user_id INTO v_user_id;

        v_data := jsonb_build_object(
            'user_id', v_user_id::TEXT,
            'full_name', v_full_name
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_status := 'ERROR';
            v_code := 409;
            v_message := 'An account with this mobile number already exists';
            v_data := NULL;
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Account could not be created';
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
            'logged_in_user_id', p_payload->>'logged_in_user_id',
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
            'fn_create_pin_user',
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

COMMENT ON FUNCTION solar_app.fn_create_pin_user(JSONB) IS
    'Creates one active customer login and stores a bcrypt hash of the 4-digit PIN.';
