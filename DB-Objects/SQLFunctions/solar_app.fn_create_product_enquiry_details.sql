-- Creates one product enquiry for the user bound to an active session.
-- A payload user id is not trusted. The enquiry number is ENQ- plus the
-- new product_enquiry_id. Notification enqueue is not called here because
-- fn_create_notification_details is not implemented.

CREATE OR REPLACE FUNCTION solar_app.fn_create_product_enquiry_details(p_payload JSONB)
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
    v_message        TEXT := 'Enquiry submitted';
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
    v_product_text   TEXT;
    v_product_id     BIGINT;
    v_message_text   TEXT;
    v_window         TEXT;
    v_pincode_text   TEXT;
    v_pincode_id     BIGINT;
    v_customer_id    BIGINT;
    v_status_id      BIGINT;
    v_enquiry_id     BIGINT;
    v_enquiry_no     VARCHAR(30);
    v_published      BOOLEAN;
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
            v_message := 'This account cannot send an enquiry';
            EXIT body;
        END IF;

        v_product_text := NULLIF(btrim(p_payload->>'product_id'), '');
        IF v_product_text IS NULL OR v_product_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose a product';
            EXIT body;
        END IF;
        v_product_id := v_product_text::BIGINT;

        SELECT product.is_published
          INTO v_published
          FROM solar_app.product_details AS product
         WHERE product.product_id = v_product_id
           AND product.active_ind IS TRUE
           AND product.is_published IS TRUE;
        IF NOT FOUND OR v_published IS NOT TRUE THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This product is not available';
            EXIT body;
        END IF;

        v_message_text := NULLIF(btrim(p_payload->>'message_text'), '');
        IF v_message_text IS NULL OR char_length(v_message_text) > 2000 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Enter a requirement of 2000 characters or fewer';
            EXIT body;
        END IF;

        v_window := NULLIF(btrim(p_payload->>'preferred_contact_window'), '');
        IF v_window IS NOT NULL AND char_length(v_window) > 50 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Preferred contact window must be 50 characters or fewer';
            EXIT body;
        END IF;

        v_pincode_text := NULLIF(btrim(p_payload->>'pincode_id'), '');
        IF v_pincode_text IS NOT NULL THEN
            IF v_pincode_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Choose a valid pincode';
                EXIT body;
            END IF;
            v_pincode_id := v_pincode_text::BIGINT;
            PERFORM 1
               FROM solar_app.ref_pincodes AS pincode
              WHERE pincode.pincode_id = v_pincode_id
                AND pincode.active_ind IS TRUE;
            IF NOT FOUND THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Choose a valid pincode';
                EXIT body;
            END IF;
        END IF;

        SELECT customer.customer_id
          INTO v_customer_id
          FROM solar_app.customer_details AS customer
         WHERE customer.user_id = v_user_id
           AND customer.active_ind IS TRUE;

        SELECT ref_row.ref_data_id
          INTO v_status_id
          FROM solar_app.ref_data AS ref_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = ref_row.category_id
         WHERE category.category_code = 'PRODUCT_ENQUIRY_STATUSES'
           AND ref_row.data_code = 'ENQ_OPEN'
           AND category.active_ind IS TRUE
           AND ref_row.active_ind IS TRUE;
        IF v_status_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Enquiry could not be submitted';
            v_log_error := 'ENQ_OPEN is not configured';
            EXIT body;
        END IF;

        v_enquiry_id := nextval(pg_get_serial_sequence(
            'solar_app.product_enquiry_details',
            'product_enquiry_id'
        ));
        v_enquiry_no := 'ENQ-' || lpad(v_enquiry_id::TEXT, 8, '0');

        INSERT INTO solar_app.product_enquiry_details (
            product_enquiry_id,
            enquiry_no,
            product_id,
            user_id,
            customer_id,
            pincode_id,
            message_text,
            preferred_contact_window,
            status_ref_data_id,
            created_by,
            updated_by
        ) OVERRIDING SYSTEM VALUE VALUES (
            v_enquiry_id,
            v_enquiry_no,
            v_product_id,
            v_user_id,
            v_customer_id,
            v_pincode_id,
            v_message_text,
            v_window,
            v_status_id,
            v_actor,
            v_actor
        );

        v_data := jsonb_build_object(
            'product_enquiry_id', v_enquiry_id::TEXT,
            'enquiry_no', v_enquiry_no,
            'product_id', v_product_id::TEXT
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Enquiry could not be submitted';
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
            'fn_create_product_enquiry_details',
            v_actor,
            v_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'product_id', v_product_id
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

COMMENT ON FUNCTION solar_app.fn_create_product_enquiry_details(JSONB) IS
    'Creates an Open enquiry for a published product. The user comes from the active session hash.';
