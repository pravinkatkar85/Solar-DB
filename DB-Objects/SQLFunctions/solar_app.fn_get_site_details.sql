-- Lists installation sites owned by the signed-in user's customer record.
-- A payload user id is not trusted. Family or operator site access is not included.

CREATE OR REPLACE FUNCTION solar_app.fn_get_site_details(p_payload JSONB)
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
    v_message       TEXT := 'Installations loaded';
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
    v_site_text     TEXT;
    v_site_id       BIGINT;
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
            v_message := 'This account cannot view installations';
            EXIT body;
        END IF;

        v_site_text := NULLIF(btrim(COALESCE(p_payload->>'site_id', '')), '');
        IF v_site_text IS NOT NULL AND v_site_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose an installation';
            EXIT body;
        END IF;
        IF v_site_text IS NOT NULL THEN
            v_site_id := v_site_text::BIGINT;
        END IF;

        SELECT customer.customer_id
          INTO v_customer_id
          FROM solar_app.customer_details AS customer
         WHERE customer.user_id = v_user_id
           AND customer.active_ind IS TRUE;

        SELECT COALESCE(jsonb_agg(listed.item ORDER BY listed.site_name), '[]'::jsonb)
          INTO v_rows
          FROM (
                SELECT site.site_name,
                       jsonb_build_object(
                           'site_id', site.site_id::TEXT,
                           'site_name', site.site_name,
                           'address_line1', site.address_line1,
                           'address_line2', site.address_line2,
                           'city_name', city.city_name,
                           'state_name', state.state_name,
                           'pincode', pincode.pincode,
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
                           'connection_type_name', connection_row.data_value,
                           'status_name', status_row.data_value,
                           'commissioning_on', to_char(site.commissioning_on, 'YYYY-MM-DD'),
                           'equipment', (
                               SELECT COALESCE(jsonb_agg(jsonb_build_object(
                                   'equipment_id', equipment.equipment_id::TEXT,
                                   'type_name', type_row.data_value,
                                   'model_name', equipment.model_name,
                                   'product_name', product.product_name,
                                   'quantity', equipment.quantity,
                                   'panel_wattage', equipment.panel_wattage,
                                   'inverter_capacity_kw', equipment.inverter_capacity_kw,
                                   'battery_capacity_ah', equipment.battery_capacity_ah
                               ) ORDER BY equipment.equipment_id), '[]'::jsonb)
                                 FROM solar_app.equipment_details AS equipment
                                 LEFT JOIN solar_app.ref_data AS type_row
                                   ON type_row.ref_data_id = equipment.equipment_type_ref_data_id
                                 LEFT JOIN solar_app.product_details AS product
                                   ON product.product_id = equipment.product_id
                                WHERE equipment.site_id = site.site_id
                                  AND equipment.active_ind IS TRUE
                           )
                       ) AS item
                  FROM solar_app.site_details AS site
                  LEFT JOIN solar_app.ref_cities AS city
                    ON city.city_id = site.city_id
                  LEFT JOIN solar_app.ref_states AS state
                    ON state.state_id = site.state_id
                  LEFT JOIN solar_app.ref_pincodes AS pincode
                    ON pincode.pincode_id = site.pincode_id
                  LEFT JOIN solar_app.ref_data AS status_row
                    ON status_row.ref_data_id = site.installation_status_ref_data_id
                  LEFT JOIN solar_app.ref_discoms AS discom
                    ON discom.discom_id = site.discom_id
                   AND discom.active_ind IS TRUE
                  LEFT JOIN solar_app.ref_data AS connection_row
                    ON connection_row.ref_data_id = site.connection_type_ref_data_id
                 WHERE site.customer_id = v_customer_id
                   AND site.active_ind IS TRUE
                   AND (v_site_id IS NULL OR site.site_id = v_site_id)
               ) AS listed;

        IF v_site_id IS NOT NULL AND v_rows = '[]'::jsonb THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This installation was not found';
            EXIT body;
        END IF;

        v_data := jsonb_build_object('installations', v_rows);
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Installations could not be loaded';
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
            'fn_get_site_details',
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

COMMENT ON FUNCTION solar_app.fn_get_site_details(JSONB) IS
    'Returns active sites owned by the session user customer, with address, DISCOM/KYC account fields, GPS, installation status, commissioning date, and active equipment.';
