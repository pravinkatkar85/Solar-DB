CREATE OR REPLACE FUNCTION solar_app.fn_get_payment_details(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'solar_app'
AS $function$
DECLARE
    v_started               TIMESTAMPTZ := clock_timestamp();
    v_api_endpoint          VARCHAR(255);
    v_actor                 VARCHAR(50) := 'SYSTEM';
    v_status                VARCHAR(20) := 'SUCCESS';
    v_code                  INTEGER := 200;
    v_message               TEXT := 'Payments retrieved';
    v_data                  JSONB := NULL;
    v_response              JSONB;
    v_log_error             TEXT;
    v_sql_state             VARCHAR(10);
    v_token_hash            TEXT;
    v_session_count         INTEGER := 0;
    v_session_id            BIGINT;
    v_session_user_id       BIGINT;
    v_active                BOOLEAN;
    v_account_code          VARCHAR(50);
    v_role_code             VARCHAR(50);
    v_claimed               TEXT;
    v_is_admin              BOOLEAN := FALSE;
    v_session_customer_id   BIGINT;
    v_payment_text          TEXT;
    v_payment_id            BIGINT;
    v_invoice_text          TEXT;
    v_invoice_id            BIGINT;
    v_customer_text         TEXT;
    v_filter_customer_id    BIGINT;
    v_status_filter         VARCHAR(50);
    v_active_filter         BOOLEAN;
    v_has_active_filter     BOOLEAN := FALSE;
    v_payments              JSONB := '[]'::jsonb;
    v_payment               JSONB;
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
          INTO v_session_id, v_session_user_id
          FROM solar_app.log_user_sessions AS session
         WHERE session.jwt_token_hash = v_token_hash
           AND session.session_status = 'ACTIVE'
           AND session.active_ind IS TRUE
           AND session.user_id IS NOT NULL;

        v_actor := v_session_user_id::TEXT;
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
         WHERE app_user.user_id = v_session_user_id;

        IF NOT FOUND OR v_active IS NOT TRUE OR v_account_code = 'ACCT_SUSPENDED' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'This account cannot view payments';
            EXIT body;
        END IF;

        v_is_admin := (v_role_code = 'ROLE_ADMIN');
        IF NOT v_is_admin THEN
            SELECT cust.customer_id
              INTO v_session_customer_id
              FROM solar_app.customer_details AS cust
             WHERE cust.user_id = v_session_user_id
               AND cust.active_ind IS TRUE;
            IF v_session_customer_id IS NULL THEN
                v_status := 'ERROR';
                v_code := 403;
                v_message := 'This account cannot view payments';
                EXIT body;
            END IF;
        END IF;

        v_payment_text := NULLIF(btrim(COALESCE(p_payload->>'payment_id', '')), '');
        IF v_payment_text IS NOT NULL THEN
            IF v_payment_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'payment_id is not valid';
                EXIT body;
            END IF;
            v_payment_id := v_payment_text::BIGINT;
        END IF;

        v_invoice_text := NULLIF(btrim(COALESCE(p_payload->>'invoice_id', '')), '');
        IF v_invoice_text IS NOT NULL THEN
            IF v_invoice_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'invoice_id is not valid';
                EXIT body;
            END IF;
            v_invoice_id := v_invoice_text::BIGINT;
        END IF;

        v_customer_text := NULLIF(btrim(COALESCE(p_payload->>'customer_id', '')), '');
        IF v_customer_text IS NOT NULL THEN
            IF v_customer_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'customer_id is not valid';
                EXIT body;
            END IF;
            v_filter_customer_id := v_customer_text::BIGINT;
            IF NOT v_is_admin AND v_filter_customer_id IS DISTINCT FROM v_session_customer_id THEN
                v_status := 'ERROR';
                v_code := 403;
                v_message := 'You can only view your own payments';
                EXIT body;
            END IF;
        ELSIF NOT v_is_admin THEN
            v_filter_customer_id := v_session_customer_id;
        END IF;

        IF p_payload ? 'payment_status_code' THEN
            v_status_filter := upper(NULLIF(btrim(COALESCE(p_payload->>'payment_status_code', '')), ''));
            IF v_status_filter IS NULL THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'payment_status_code is not valid';
                EXIT body;
            END IF;
        END IF;

        IF p_payload ? 'active_ind' THEN
            IF jsonb_typeof(p_payload->'active_ind') <> 'boolean' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'active_ind must be a boolean';
                EXIT body;
            END IF;
            v_active_filter := (p_payload->>'active_ind')::BOOLEAN;
            v_has_active_filter := TRUE;
        END IF;

        WITH filtered AS (
            SELECT pay.payment_id
              FROM solar_app.payment_details AS pay
              LEFT JOIN solar_app.ref_data AS st
                ON st.ref_data_id = pay.payment_status_ref_data_id
             WHERE (v_payment_id IS NULL OR pay.payment_id = v_payment_id)
               AND (v_invoice_id IS NULL OR pay.invoice_id = v_invoice_id)
               AND (v_filter_customer_id IS NULL OR pay.customer_id = v_filter_customer_id)
               AND (v_status_filter IS NULL OR st.data_code = v_status_filter)
               AND (NOT v_has_active_filter OR pay.active_ind IS NOT DISTINCT FROM v_active_filter)
             ORDER BY pay.paid_on DESC, pay.payment_id DESC
        ),
        rows AS (
            SELECT jsonb_strip_nulls(jsonb_build_object(
                       'payment_id', pay.payment_id::TEXT,
                       'invoice_id', pay.invoice_id::TEXT,
                       'customer_id', pay.customer_id::TEXT,
                       'amount', pay.amount,
                       'currency_code', pay.currency_code,
                       'payment_method_code', method_row.data_code,
                       'payment_status_code', status_row.data_code,
                       'is_offline_ind', pay.is_offline_ind,
                       'instrument_ref', pay.instrument_ref,
                       'paid_on', pay.paid_on::TEXT,
                       'remarks', pay.remarks,
                       'active_ind', pay.active_ind,
                       'created_on', pay.created_on,
                       'updated_on', pay.updated_on
                   )) AS payment_json
              FROM filtered AS f
              JOIN solar_app.payment_details AS pay
                ON pay.payment_id = f.payment_id
              LEFT JOIN solar_app.ref_data AS method_row
                ON method_row.ref_data_id = pay.payment_method_ref_data_id
              LEFT JOIN solar_app.ref_data AS status_row
                ON status_row.ref_data_id = pay.payment_status_ref_data_id
             ORDER BY pay.paid_on DESC, pay.payment_id DESC
        )
        SELECT COALESCE(jsonb_agg(rows.payment_json), '[]'::jsonb)
          INTO v_payments
          FROM rows;

        IF v_payment_id IS NOT NULL THEN
            IF jsonb_array_length(v_payments) = 0 THEN
                v_status := 'ERROR';
                v_code := 404;
                v_message := 'This payment was not found';
                EXIT body;
            END IF;
            v_payment := v_payments->0;
            v_data := jsonb_build_object('payment', v_payment);
            v_message := 'Payment retrieved';
        ELSE
            v_data := jsonb_build_object('payments', v_payments);
            v_message := 'Payments retrieved';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Payments could not be retrieved';
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
            COALESCE(v_api_endpoint, 'UNKNOWN'),
            'fn_get_payment_details',
            v_actor,
            v_session_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'payment_id', v_payment_id,
                'invoice_id', v_invoice_id,
                'customer_id', v_filter_customer_id,
                'is_admin', v_is_admin
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
$function$

