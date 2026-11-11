-- Updates Module 3.1 site KYC profile fields for one site owned by the session customer.
-- DISCOM, consumer/meter numbers, sanctioned load, address lines, GPS, and connection type.
-- Installation status, commissioning date, and order links are not changed here.
-- A payload user id is not trusted. Notification enqueue is not called.
-- Do not install this file until separately approved.

CREATE OR REPLACE FUNCTION solar_app.fn_update_site_details(p_payload JSONB)
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
    v_message            TEXT := 'Site profile updated';
    v_data               JSONB := NULL;
    v_response           JSONB;
    v_log_error          TEXT;
    v_sql_state          VARCHAR(10);
    v_token_hash         TEXT;
    v_session_count      INTEGER := 0;
    v_session_id         BIGINT;
    v_user_id            BIGINT;
    v_active             BOOLEAN;
    v_account_code       VARCHAR(50);
    v_claimed            TEXT;
    v_customer_id        BIGINT;
    v_site_text          TEXT;
    v_site_id            BIGINT;
    v_address1           TEXT;
    v_address2           TEXT;
    v_lat_text           TEXT;
    v_lon_text           TEXT;
    v_latitude           NUMERIC(10,7);
    v_longitude          NUMERIC(10,7);
    v_discom_text        TEXT;
    v_discom_id          BIGINT;
    v_consumer           TEXT;
    v_meter              TEXT;
    v_load_text          TEXT;
    v_load_kw            NUMERIC(8,3);
    v_conn_text          TEXT;
    v_conn_id            BIGINT;
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
            v_message := 'This account cannot update site profiles';
            EXIT body;
        END IF;

        SELECT customer.customer_id
          INTO v_customer_id
          FROM solar_app.customer_details AS customer
         WHERE customer.user_id = v_user_id
           AND customer.active_ind IS TRUE;
        IF v_customer_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'This account cannot update site profiles';
            EXIT body;
        END IF;

        v_site_text := NULLIF(btrim(COALESCE(p_payload->>'site_id', '')), '');
        IF v_site_text IS NULL OR v_site_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose a site';
            EXIT body;
        END IF;
        v_site_id := v_site_text::BIGINT;

        IF NOT EXISTS (
            SELECT 1
              FROM solar_app.site_details AS site
             WHERE site.site_id = v_site_id
               AND site.customer_id = v_customer_id
               AND site.active_ind IS TRUE
        ) THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This site was not found';
            EXIT body;
        END IF;

        v_address1 := NULLIF(btrim(COALESCE(p_payload->>'address_line1', '')), '');
        IF v_address1 IS NULL OR char_length(v_address1) > 255 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Enter the site address';
            EXIT body;
        END IF;
        v_address2 := NULLIF(btrim(COALESCE(p_payload->>'address_line2', '')), '');
        IF v_address2 IS NOT NULL AND char_length(v_address2) > 255 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Enter a shorter address line';
            EXIT body;
        END IF;

        v_lat_text := NULLIF(btrim(COALESCE(p_payload->>'latitude', '')), '');
        v_lon_text := NULLIF(btrim(COALESCE(p_payload->>'longitude', '')), '');
        IF (v_lat_text IS NULL) <> (v_lon_text IS NULL) THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Provide both latitude and longitude';
            EXIT body;
        END IF;
        IF v_lat_text IS NOT NULL THEN
            BEGIN
                v_latitude := v_lat_text::NUMERIC(10,7);
                v_longitude := v_lon_text::NUMERIC(10,7);
            EXCEPTION
                WHEN OTHERS THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'Enter valid GPS coordinates';
            END;
            IF v_status <> 'SUCCESS' THEN
                EXIT body;
            END IF;
            IF v_latitude < -90 OR v_latitude > 90 OR v_longitude < -180 OR v_longitude > 180 THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Enter valid GPS coordinates';
                EXIT body;
            END IF;
        END IF;

        v_discom_text := NULLIF(btrim(COALESCE(p_payload->>'discom_id', '')), '');
        IF v_discom_text IS NOT NULL THEN
            IF v_discom_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Choose an electricity provider';
                EXIT body;
            END IF;
            v_discom_id := v_discom_text::BIGINT;
            IF NOT EXISTS (
                SELECT 1
                  FROM solar_app.ref_discoms AS discom
                 WHERE discom.discom_id = v_discom_id
                   AND discom.active_ind IS TRUE
            ) THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Choose an electricity provider';
                EXIT body;
            END IF;
        END IF;

        v_consumer := NULLIF(btrim(COALESCE(p_payload->>'consumer_number', '')), '');
        IF v_consumer IS NOT NULL AND char_length(v_consumer) > 50 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Enter a shorter consumer number';
            EXIT body;
        END IF;
        v_meter := NULLIF(btrim(COALESCE(p_payload->>'meter_number', '')), '');
        IF v_meter IS NOT NULL AND char_length(v_meter) > 50 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Enter a shorter meter number';
            EXIT body;
        END IF;

        v_load_text := NULLIF(btrim(COALESCE(p_payload->>'sanctioned_load_kw', '')), '');
        IF v_load_text IS NOT NULL THEN
            BEGIN
                v_load_kw := v_load_text::NUMERIC(8,3);
            EXCEPTION
                WHEN OTHERS THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'Enter a valid sanctioned load';
            END;
            IF v_status <> 'SUCCESS' THEN
                EXIT body;
            END IF;
            IF v_load_kw < 0 THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Enter a valid sanctioned load';
                EXIT body;
            END IF;
        END IF;

        v_conn_text := NULLIF(btrim(COALESCE(p_payload->>'connection_type_ref_data_id', '')), '');
        IF v_conn_text IS NOT NULL THEN
            IF v_conn_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Choose a connection type';
                EXIT body;
            END IF;
            v_conn_id := v_conn_text::BIGINT;
            IF NOT EXISTS (
                SELECT 1
                  FROM solar_app.ref_data AS row_data
                  JOIN solar_app.ref_data_categories AS category
                    ON category.category_id = row_data.category_id
                 WHERE row_data.ref_data_id = v_conn_id
                   AND row_data.active_ind IS TRUE
                   AND category.category_code = 'CONNECTION_TYPES'
                   AND category.active_ind IS TRUE
            ) THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Choose a connection type';
                EXIT body;
            END IF;
        END IF;

        UPDATE solar_app.site_details AS site
           SET address_line1 = v_address1,
               address_line2 = v_address2,
               latitude = v_latitude,
               longitude = v_longitude,
               discom_id = v_discom_id,
               consumer_number = v_consumer,
               meter_number = v_meter,
               sanctioned_load_kw = v_load_kw,
               connection_type_ref_data_id = v_conn_id,
               updated_by = v_actor,
               updated_on = clock_timestamp()
         WHERE site.site_id = v_site_id
           AND site.customer_id = v_customer_id
           AND site.active_ind IS TRUE;
        GET DIAGNOSTICS v_updated = ROW_COUNT;
        IF v_updated IS DISTINCT FROM 1 THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This site was not found';
            EXIT body;
        END IF;

        SELECT jsonb_build_object(
            'site_id', site.site_id::TEXT,
            'site_name', site.site_name,
            'address_line1', site.address_line1,
            'address_line2', site.address_line2,
            'latitude', site.latitude,
            'longitude', site.longitude,
            'discom_id', CASE WHEN site.discom_id IS NULL THEN NULL ELSE site.discom_id::TEXT END,
            'discom_name', discom.discom_name,
            'consumer_number', site.consumer_number,
            'meter_number', site.meter_number,
            'sanctioned_load_kw', site.sanctioned_load_kw,
            'connection_type_id', CASE
                WHEN site.connection_type_ref_data_id IS NULL THEN NULL
                ELSE site.connection_type_ref_data_id::TEXT
            END,
            'connection_type_name', connection_row.data_value
        )
          INTO v_data
          FROM solar_app.site_details AS site
          LEFT JOIN solar_app.ref_discoms AS discom
            ON discom.discom_id = site.discom_id
          LEFT JOIN solar_app.ref_data AS connection_row
            ON connection_row.ref_data_id = site.connection_type_ref_data_id
         WHERE site.site_id = v_site_id;
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Site profile could not be updated';
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
            'fn_update_site_details',
            v_actor,
            v_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'site_id', v_site_id
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

COMMENT ON FUNCTION solar_app.fn_update_site_details(JSONB) IS
    'Updates address, GPS, DISCOM account, and connection fields on one site owned by the session customer.';
