-- Admin records one offline payment and recalculates invoice paid/balance/status.
-- Session identity and ROLE_ADMIN come only from jwt_token_hash → log_user_sessions.
-- is_offline_ind is always TRUE. Overpayment is rejected (balance_amount must stay >= 0).
-- Rejects payments against INV_DRAFT, INV_CANCELLED, or inactive invoices.
-- Recalculates invoice paid/balance/status (UNPAID/PARTIAL/PAID) from active PAY_RECORDED rows.
-- On success enqueues NTF_BILLING_UPDATE. Do not install until separately approved.

CREATE OR REPLACE FUNCTION solar_app.fn_create_payment_details(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = pg_catalog, solar_app
AS $$
DECLARE
    v_started               TIMESTAMPTZ := clock_timestamp();
    v_api_endpoint          VARCHAR(255);
    v_actor                 VARCHAR(50) := 'SYSTEM';
    v_status                VARCHAR(20) := 'SUCCESS';
    v_code                  INTEGER := 200;
    v_message               TEXT := 'Payment recorded';
    v_data                  JSONB := NULL;
    v_response              JSONB;
    v_log_error             TEXT;
    v_sql_state             VARCHAR(10);
    v_token_hash            TEXT;
    v_session_count         INTEGER := 0;
    v_session_id            BIGINT;
    v_admin_user_id         BIGINT;
    v_active                BOOLEAN;
    v_account_code          VARCHAR(50);
    v_role_code             VARCHAR(50);
    v_claimed               TEXT;
    v_invoice_text          TEXT;
    v_invoice_id            BIGINT;
    v_invoice_customer_id   BIGINT;
    v_invoice_currency      CHAR(3);
    v_invoice_total         NUMERIC(14,2);
    v_invoice_active        BOOLEAN;
    v_invoice_status_code   VARCHAR(50);
    v_customer_user_id      BIGINT;
    v_amount                NUMERIC(14,2);
    v_method_code           VARCHAR(50);
    v_method_id             BIGINT;
    v_status_code           VARCHAR(50);
    v_status_id             BIGINT;
    v_currency_code         CHAR(3);
    v_customer_text         TEXT;
    v_paid_on_text          TEXT;
    v_paid_on               DATE;
    v_instrument_ref        VARCHAR(100);
    v_remarks               VARCHAR(500);
    v_payment_id            BIGINT;
    v_paid_sum              NUMERIC(14,2);
    v_balance_amount        NUMERIC(14,2);
    v_new_inv_status_code   VARCHAR(50);
    v_new_inv_status_id     BIGINT;
    v_ntf_response          JSONB;
    v_notification_id       TEXT;
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
            v_message := 'This account cannot record payments';
            EXIT body;
        END IF;
        IF v_role_code IS DISTINCT FROM 'ROLE_ADMIN' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'Only an administrator can record payments';
            EXIT body;
        END IF;

        v_invoice_text := NULLIF(btrim(COALESCE(p_payload->>'invoice_id', '')), '');
        IF v_invoice_text IS NULL OR v_invoice_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'invoice_id is required';
            EXIT body;
        END IF;
        v_invoice_id := v_invoice_text::BIGINT;

        SELECT inv.customer_id,
               inv.currency_code,
               inv.total_amount,
               inv.active_ind,
               status_row.data_code
          INTO v_invoice_customer_id,
               v_invoice_currency,
               v_invoice_total,
               v_invoice_active,
               v_invoice_status_code
          FROM solar_app.invoice_details AS inv
          LEFT JOIN solar_app.ref_data AS status_row
            ON status_row.ref_data_id = inv.invoice_status_ref_data_id
         WHERE inv.invoice_id = v_invoice_id
         FOR UPDATE OF inv;

        IF v_invoice_customer_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This invoice was not found';
            EXIT body;
        END IF;
        IF v_invoice_active IS NOT TRUE THEN
            v_status := 'ERROR';
            v_code := 409;
            v_message := 'Payments cannot be recorded against an inactive invoice';
            EXIT body;
        END IF;
        IF v_invoice_status_code = 'INV_DRAFT' THEN
            v_status := 'ERROR';
            v_code := 409;
            v_message := 'Payments cannot be recorded against a draft invoice';
            EXIT body;
        END IF;
        IF v_invoice_status_code = 'INV_CANCELLED' THEN
            v_status := 'ERROR';
            v_code := 409;
            v_message := 'Payments cannot be recorded against a cancelled invoice';
            EXIT body;
        END IF;

        SELECT cust.user_id
          INTO v_customer_user_id
          FROM solar_app.customer_details AS cust
         WHERE cust.customer_id = v_invoice_customer_id
           AND cust.active_ind IS TRUE;
        IF v_customer_user_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This customer was not found';
            EXIT body;
        END IF;

        v_customer_text := NULLIF(btrim(COALESCE(p_payload->>'customer_id', '')), '');
        IF v_customer_text IS NOT NULL THEN
            IF v_customer_text !~ '^[0-9]{1,18}$'
               OR v_customer_text::BIGINT IS DISTINCT FROM v_invoice_customer_id THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'customer_id must match the invoice customer';
                EXIT body;
            END IF;
        END IF;

        BEGIN
            IF NULLIF(btrim(COALESCE(p_payload->>'amount', '')), '') IS NULL THEN
                RAISE EXCEPTION 'amount is required' USING ERRCODE = 'P0001';
            END IF;
            v_amount := (btrim(p_payload->>'amount'))::NUMERIC;
        EXCEPTION
            WHEN SQLSTATE 'P0001' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := SQLERRM;
                EXIT body;
            WHEN OTHERS THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'amount must be numeric';
                EXIT body;
        END;
        IF v_amount <= 0 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'amount must be greater than zero';
            EXIT body;
        END IF;

        v_method_code := upper(NULLIF(btrim(COALESCE(p_payload->>'payment_method_code', '')), ''));
        IF v_method_code IS NULL
           OR v_method_code NOT IN ('PAY_CASH', 'PAY_CHEQUE', 'PAY_NEFT', 'PAY_UPI_OFFLINE', 'PAY_OTHER') THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'payment_method_code is not valid';
            EXIT body;
        END IF;
        SELECT rd.ref_data_id
          INTO v_method_id
          FROM solar_app.ref_data AS rd
          JOIN solar_app.ref_data_categories AS cat
            ON cat.category_id = rd.category_id
         WHERE cat.category_code = 'PAYMENT_METHODS'
           AND cat.active_ind IS TRUE
           AND rd.data_code = v_method_code
           AND rd.active_ind IS TRUE;
        IF v_method_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'payment_method_code is not valid';
            EXIT body;
        END IF;

        v_status_code := upper(NULLIF(btrim(COALESCE(p_payload->>'payment_status_code', 'PAY_RECORDED')), ''));
        IF v_status_code IS DISTINCT FROM 'PAY_RECORDED' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'payment_status_code must be PAY_RECORDED on create';
            EXIT body;
        END IF;
        SELECT rd.ref_data_id
          INTO v_status_id
          FROM solar_app.ref_data AS rd
          JOIN solar_app.ref_data_categories AS cat
            ON cat.category_id = rd.category_id
         WHERE cat.category_code = 'PAYMENT_STATUSES'
           AND cat.active_ind IS TRUE
           AND rd.data_code = 'PAY_RECORDED'
           AND rd.active_ind IS TRUE;
        IF v_status_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Payment could not be recorded';
            EXIT body;
        END IF;

        v_currency_code := v_invoice_currency;
        IF p_payload ? 'currency_code' THEN
            v_currency_code := upper(NULLIF(btrim(COALESCE(p_payload->>'currency_code', '')), ''));
            IF v_currency_code IS NULL OR char_length(v_currency_code) <> 3
               OR v_currency_code IS DISTINCT FROM v_invoice_currency THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'currency_code must match the invoice currency';
                EXIT body;
            END IF;
        END IF;

        v_paid_on_text := NULLIF(btrim(COALESCE(p_payload->>'paid_on', '')), '');
        IF v_paid_on_text IS NULL THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'paid_on is required';
            EXIT body;
        END IF;
        BEGIN
            v_paid_on := v_paid_on_text::DATE;
        EXCEPTION
            WHEN OTHERS THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'paid_on must be a valid date';
                EXIT body;
        END;

        v_instrument_ref := NULLIF(btrim(COALESCE(p_payload->>'instrument_ref', '')), '');
        IF v_instrument_ref IS NOT NULL AND char_length(v_instrument_ref) > 100 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'instrument_ref must be 100 characters or fewer';
            EXIT body;
        END IF;

        v_remarks := NULLIF(btrim(COALESCE(p_payload->>'remarks', '')), '');
        IF v_remarks IS NOT NULL AND char_length(v_remarks) > 500 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'remarks must be 500 characters or fewer';
            EXIT body;
        END IF;

        SELECT COALESCE(SUM(pay.amount), 0)
          INTO v_paid_sum
          FROM solar_app.payment_details AS pay
          JOIN solar_app.ref_data AS st
            ON st.ref_data_id = pay.payment_status_ref_data_id
         WHERE pay.invoice_id = v_invoice_id
           AND pay.active_ind IS TRUE
           AND st.data_code = 'PAY_RECORDED';

        IF (v_paid_sum + v_amount) > v_invoice_total THEN
            v_status := 'ERROR';
            v_code := 409;
            v_message := 'Payment would exceed the invoice balance';
            EXIT body;
        END IF;

        INSERT INTO solar_app.payment_details (
            invoice_id,
            customer_id,
            amount,
            currency_code,
            payment_method_ref_data_id,
            payment_status_ref_data_id,
            is_offline_ind,
            instrument_ref,
            paid_on,
            remarks,
            active_ind,
            created_by,
            updated_by
        ) VALUES (
            v_invoice_id,
            v_invoice_customer_id,
            v_amount,
            v_currency_code,
            v_method_id,
            v_status_id,
            TRUE,
            v_instrument_ref,
            v_paid_on,
            v_remarks,
            TRUE,
            v_actor,
            v_actor
        )
        RETURNING payment_id INTO v_payment_id;

        v_paid_sum := v_paid_sum + v_amount;
        v_balance_amount := v_invoice_total - v_paid_sum;
        IF v_paid_sum = 0 THEN
            v_new_inv_status_code := 'INV_UNPAID';
        ELSIF v_paid_sum < v_invoice_total THEN
            v_new_inv_status_code := 'INV_PARTIAL';
        ELSE
            v_new_inv_status_code := 'INV_PAID';
        END IF;

        SELECT rd.ref_data_id
          INTO v_new_inv_status_id
          FROM solar_app.ref_data AS rd
          JOIN solar_app.ref_data_categories AS cat
            ON cat.category_id = rd.category_id
         WHERE cat.category_code = 'INVOICE_STATUSES'
           AND cat.active_ind IS TRUE
           AND rd.data_code = v_new_inv_status_code
           AND rd.active_ind IS TRUE;
        IF v_new_inv_status_id IS NULL THEN
            RAISE EXCEPTION 'Invoice status reference missing for %', v_new_inv_status_code
                USING ERRCODE = 'P0001';
        END IF;

        UPDATE solar_app.invoice_details AS inv
           SET paid_amount = v_paid_sum,
               balance_amount = v_balance_amount,
               invoice_status_ref_data_id = v_new_inv_status_id,
               updated_by = v_actor,
               updated_on = CURRENT_TIMESTAMP
         WHERE inv.invoice_id = v_invoice_id;

        v_ntf_response := solar_app.fn_create_notification_details(
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'logged_in_user_id', v_actor,
                'recipient_user_id', v_customer_user_id::TEXT,
                'notification_type_code', 'NTF_BILLING_UPDATE',
                'title', 'Payment recorded',
                'body', format('A payment of %s was recorded against your bill.', v_amount::TEXT),
                'related_entity_type', 'PAYMENT',
                'related_entity_id', v_payment_id::TEXT,
                'payload_json', jsonb_build_object(
                    'entity_type', 'PAYMENT',
                    'entity_id', v_payment_id::TEXT,
                    'invoice_id', v_invoice_id::TEXT,
                    'customer_id', v_invoice_customer_id::TEXT
                )
            ))
        );
        IF COALESCE(v_ntf_response->>'status', 'ERROR') IS DISTINCT FROM 'SUCCESS' THEN
            RAISE EXCEPTION 'Notification enqueue failed (NTF_BILLING_UPDATE): %',
                COALESCE(v_ntf_response->>'message', 'unknown error')
                USING ERRCODE = 'P0001';
        END IF;
        v_notification_id := v_ntf_response->'data'->>'notification_id';

        v_data := jsonb_strip_nulls(jsonb_build_object(
            'payment_id', v_payment_id::TEXT,
            'invoice_id', v_invoice_id::TEXT,
            'customer_id', v_invoice_customer_id::TEXT,
            'amount', v_amount,
            'currency_code', v_currency_code,
            'payment_method_code', v_method_code,
            'payment_status_code', 'PAY_RECORDED',
            'is_offline_ind', TRUE,
            'paid_on', v_paid_on::TEXT,
            'instrument_ref', v_instrument_ref,
            'invoice_paid_amount', v_paid_sum,
            'invoice_balance_amount', v_balance_amount,
            'invoice_status_code', v_new_inv_status_code,
            'notification_id', v_notification_id
        ));
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            IF SQLSTATE = 'P0001' AND SQLERRM LIKE 'Notification enqueue failed%' THEN
                v_message := 'Payment could not be recorded';
            ELSIF SQLSTATE = 'P0001' THEN
                v_code := 400;
                v_message := SQLERRM;
            ELSE
                v_message := 'Payment could not be recorded';
            END IF;
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
            'fn_create_payment_details',
            v_actor,
            v_admin_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'invoice_id', v_invoice_id,
                'payment_id', v_payment_id,
                'amount', v_amount,
                'payment_method_code', v_method_code
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

COMMENT ON FUNCTION solar_app.fn_create_payment_details(JSONB) IS
'Admin offline payment create; recalculates invoice paid/balance/status; enqueues NTF_BILLING_UPDATE.';
