-- Lists or returns offline invoices with active lines and tax snapshots.
-- Session identity comes only from jwt_token_hash → log_user_sessions.
-- ROLE_ADMIN may view all; customers may view only their own invoices (read-only).
-- Customer listing/detail excludes INV_DRAFT, INV_CANCELLED, and inactive invoices by default.
-- Do not install until separately approved.

CREATE OR REPLACE FUNCTION solar_app.fn_get_invoice_details(p_payload JSONB)
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
    v_message               TEXT := 'Invoices retrieved';
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
    v_invoice_text          TEXT;
    v_invoice_id            BIGINT;
    v_customer_text         TEXT;
    v_filter_customer_id    BIGINT;
    v_active_filter         BOOLEAN;
    v_has_active_filter     BOOLEAN := FALSE;
    v_invoices              JSONB := '[]'::jsonb;
    v_invoice               JSONB;
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
            v_message := 'This account cannot view invoices';
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
                v_message := 'This account cannot view invoices';
                EXIT body;
            END IF;
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
            IF NOT v_is_admin THEN
                IF v_filter_customer_id IS DISTINCT FROM v_session_customer_id THEN
                    v_status := 'ERROR';
                    v_code := 403;
                    v_message := 'You can only view your own invoices';
                    EXIT body;
                END IF;
            END IF;
        ELSIF NOT v_is_admin THEN
            v_filter_customer_id := v_session_customer_id;
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
            SELECT inv.invoice_id
              FROM solar_app.invoice_details AS inv
              LEFT JOIN solar_app.ref_data AS status_filter
                ON status_filter.ref_data_id = inv.invoice_status_ref_data_id
             WHERE (v_invoice_id IS NULL OR inv.invoice_id = v_invoice_id)
               AND (v_filter_customer_id IS NULL OR inv.customer_id = v_filter_customer_id)
               AND (
                    v_is_admin
                    OR (
                        inv.active_ind IS TRUE
                        AND COALESCE(status_filter.data_code, '') NOT IN ('INV_DRAFT', 'INV_CANCELLED')
                    )
               )
               AND (
                    NOT v_is_admin
                    OR NOT v_has_active_filter
                    OR inv.active_ind IS NOT DISTINCT FROM v_active_filter
               )
             ORDER BY inv.invoice_date DESC, inv.invoice_id DESC
        ),
        header AS (
            SELECT jsonb_build_object(
                       'invoice_id', inv.invoice_id::TEXT,
                       'invoice_no', inv.invoice_no,
                       'customer_id', inv.customer_id::TEXT,
                       'site_id', CASE WHEN inv.site_id IS NULL THEN NULL ELSE inv.site_id::TEXT END,
                       'related_order_id', CASE WHEN inv.related_order_id IS NULL THEN NULL ELSE inv.related_order_id::TEXT END,
                       'related_amc_contract_id', CASE WHEN inv.related_amc_contract_id IS NULL THEN NULL ELSE inv.related_amc_contract_id::TEXT END,
                       'related_service_request_id', CASE WHEN inv.related_service_request_id IS NULL THEN NULL ELSE inv.related_service_request_id::TEXT END,
                       'related_spare_part_request_id', CASE WHEN inv.related_spare_part_request_id IS NULL THEN NULL ELSE inv.related_spare_part_request_id::TEXT END,
                       'invoice_category_code', cat_row.data_code,
                       'invoice_status_code', status_row.data_code,
                       'invoice_date', inv.invoice_date::TEXT,
                       'currency_code', inv.currency_code,
                       'taxable_amount', inv.taxable_amount,
                       'tax_amount', inv.tax_amount,
                       'total_amount', inv.total_amount,
                       'paid_amount', inv.paid_amount,
                       'balance_amount', inv.balance_amount,
                       'remarks', inv.remarks,
                       'active_ind', inv.active_ind,
                       'created_on', inv.created_on,
                       'updated_on', inv.updated_on,
                       'lines', COALESCE((
                           SELECT jsonb_agg(
                                      jsonb_strip_nulls(jsonb_build_object(
                                          'invoice_line_id', line.invoice_line_id::TEXT,
                                          'line_no', line.line_no,
                                          'line_desc', line.line_desc,
                                          'tax_classification_code', line.tax_classification_code,
                                          'quantity', line.quantity,
                                          'unit_rate', line.unit_rate,
                                          'line_amount', line.line_amount
                                      ))
                                      ORDER BY line.line_no
                                  )
                             FROM solar_app.invoice_line_details AS line
                            WHERE line.invoice_id = inv.invoice_id
                              AND line.active_ind IS TRUE
                       ), '[]'::jsonb),
                       'tax_snapshots', COALESCE((
                           SELECT jsonb_agg(
                                      jsonb_strip_nulls(jsonb_build_object(
                                          'invoice_tax_id', tax.invoice_tax_id::TEXT,
                                          'invoice_line_id', CASE WHEN tax.invoice_line_id IS NULL THEN NULL ELSE tax.invoice_line_id::TEXT END,
                                          'line_no', line.line_no,
                                          'tax_group_code', tax.tax_group_code,
                                          'tax_component_code', tax.tax_component_code,
                                          'tax_display_name', tax.tax_display_name,
                                          'calculation_method', tax.calculation_method,
                                          'rate_percent', tax.rate_percent,
                                          'configured_rate_amount', tax.configured_rate_amount,
                                          'taxable_amount', tax.taxable_amount,
                                          'tax_amount', tax.tax_amount,
                                          'jurisdiction_json', tax.jurisdiction_json
                                      ))
                                      ORDER BY tax.invoice_tax_id
                                  )
                             FROM solar_app.invoice_tax_details AS tax
                             LEFT JOIN solar_app.invoice_line_details AS line
                               ON line.invoice_line_id = tax.invoice_line_id
                              AND line.invoice_id = tax.invoice_id
                            WHERE tax.invoice_id = inv.invoice_id
                              AND tax.active_ind IS TRUE
                       ), '[]'::jsonb)
                   ) AS invoice_json
              FROM filtered AS f
              JOIN solar_app.invoice_details AS inv
                ON inv.invoice_id = f.invoice_id
              LEFT JOIN solar_app.ref_data AS cat_row
                ON cat_row.ref_data_id = inv.invoice_category_ref_data_id
              LEFT JOIN solar_app.ref_data AS status_row
                ON status_row.ref_data_id = inv.invoice_status_ref_data_id
             ORDER BY inv.invoice_date DESC, inv.invoice_id DESC
        )
        SELECT COALESCE(jsonb_agg(header.invoice_json), '[]'::jsonb)
          INTO v_invoices
          FROM header;

        IF v_invoice_id IS NOT NULL THEN
            IF jsonb_array_length(v_invoices) = 0 THEN
                v_status := 'ERROR';
                v_code := 404;
                v_message := 'This invoice was not found';
                EXIT body;
            END IF;
            v_invoice := v_invoices->0;
            v_data := jsonb_build_object('invoice', v_invoice);
            v_message := 'Invoice retrieved';
        ELSE
            v_data := jsonb_build_object('invoices', v_invoices);
            v_message := 'Invoices retrieved';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Invoices could not be retrieved';
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
            'fn_get_invoice_details',
            v_actor,
            v_session_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'invoice_id', v_invoice_id,
                'customer_id', v_filter_customer_id,
                'active_ind', CASE WHEN v_has_active_filter THEN to_jsonb(v_active_filter) ELSE NULL END,
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
$$;

COMMENT ON FUNCTION solar_app.fn_get_invoice_details(JSONB) IS
'Admin/customer offline invoice list or detail with active lines and tax snapshots.';
