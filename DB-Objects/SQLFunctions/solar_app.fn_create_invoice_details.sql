-- Admin creates one offline invoice header with optional lines and transcribed tax snapshots.
-- Session identity and ROLE_ADMIN come only from jwt_token_hash → log_user_sessions.
-- paid_amount / balance_amount / INV_PARTIAL / INV_PAID from the client are ignored.
-- Initial status is INV_DRAFT or INV_UNPAID only; paid starts at 0 and balance equals total.
-- Tax is transcription-only; source_tax_rule_id is always NULL. No payment / milestone work.
-- On success enqueues NTF_BILLING_UPDATE. Do not install until separately approved.

CREATE OR REPLACE FUNCTION solar_app.fn_create_invoice_details(p_payload JSONB)
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
    v_message               TEXT := 'Invoice recorded';
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
    v_invoice_no            VARCHAR(40);
    v_customer_text         TEXT;
    v_customer_id           BIGINT;
    v_customer_user_id      BIGINT;
    v_customer_active       BOOLEAN;
    v_cust_user_active      BOOLEAN;
    v_cust_account_code     VARCHAR(50);
    v_invoice_date_text     TEXT;
    v_invoice_date          DATE;
    v_currency_code         CHAR(3);
    v_currency_active       BOOLEAN;
    v_category_code         VARCHAR(50);
    v_category_id           BIGINT;
    v_status_code           VARCHAR(50);
    v_status_id             BIGINT;
    v_taxable_amount        NUMERIC(14,2);
    v_tax_amount            NUMERIC(14,2);
    v_total_amount          NUMERIC(14,2);
    v_site_text             TEXT;
    v_site_id               BIGINT;
    v_order_text            TEXT;
    v_order_id              BIGINT;
    v_amc_text              TEXT;
    v_amc_id                BIGINT;
    v_sr_text               TEXT;
    v_sr_id                 BIGINT;
    v_spr_text              TEXT;
    v_spr_id                BIGINT;
    v_remarks               VARCHAR(500);
    v_lines                 JSONB;
    v_tax_snapshots         JSONB;
    v_line                  JSONB;
    v_tax                   JSONB;
    v_line_no               INTEGER;
    v_line_desc             VARCHAR(255);
    v_quantity              NUMERIC(12,3);
    v_unit_rate             NUMERIC(12,2);
    v_line_amount           NUMERIC(14,2);
    v_tax_class             VARCHAR(30);
    v_invoice_line_id       BIGINT;
    v_line_map              JSONB := '{}'::jsonb;
    v_tax_group             VARCHAR(50);
    v_tax_component         VARCHAR(50);
    v_tax_display           VARCHAR(150);
    v_calc_method           VARCHAR(20);
    v_rate_percent          NUMERIC(7,4);
    v_configured_rate       NUMERIC(14,2);
    v_tax_taxable           NUMERIC(14,2);
    v_tax_amt               NUMERIC(14,2);
    v_jurisdiction          JSONB;
    v_tax_line_no           INTEGER;
    v_tax_line_id           BIGINT;
    v_tax_sum               NUMERIC(14,2) := 0;
    v_invoice_id            BIGINT;
    v_ntf_response          JSONB;
    v_notification_id       TEXT;
    v_i                     INTEGER;
    v_seen_line_nos         INTEGER[] := ARRAY[]::INTEGER[];
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
            v_message := 'This account cannot record invoices';
            EXIT body;
        END IF;
        IF v_role_code IS DISTINCT FROM 'ROLE_ADMIN' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'Only an administrator can record invoices';
            EXIT body;
        END IF;

        v_invoice_no := NULLIF(btrim(COALESCE(p_payload->>'invoice_no', '')), '');
        IF v_invoice_no IS NULL OR char_length(v_invoice_no) > 40 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'invoice_no is required and must be 40 characters or fewer';
            EXIT body;
        END IF;

        v_customer_text := NULLIF(btrim(COALESCE(p_payload->>'customer_id', '')), '');
        IF v_customer_text IS NULL OR v_customer_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'customer_id is required';
            EXIT body;
        END IF;
        v_customer_id := v_customer_text::BIGINT;

        SELECT cust.user_id,
               cust.active_ind,
               app_user.active_ind,
               account_row.data_code
          INTO v_customer_user_id,
               v_customer_active,
               v_cust_user_active,
               v_cust_account_code
          FROM solar_app.customer_details AS cust
          JOIN solar_app.user_details AS app_user
            ON app_user.user_id = cust.user_id
          LEFT JOIN solar_app.ref_data AS account_row
            ON account_row.ref_data_id = app_user.account_status_ref_data_id
         WHERE cust.customer_id = v_customer_id;

        IF v_customer_user_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This customer was not found';
            EXIT body;
        END IF;
        IF v_customer_active IS NOT TRUE
           OR v_cust_user_active IS NOT TRUE
           OR v_cust_account_code = 'ACCT_SUSPENDED' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'This customer is not active';
            EXIT body;
        END IF;

        v_invoice_date_text := NULLIF(btrim(COALESCE(p_payload->>'invoice_date', '')), '');
        IF v_invoice_date_text IS NULL THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'invoice_date is required';
            EXIT body;
        END IF;
        BEGIN
            v_invoice_date := v_invoice_date_text::DATE;
        EXCEPTION
            WHEN OTHERS THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'invoice_date must be a valid date';
                EXIT body;
        END;

        v_currency_code := upper(NULLIF(btrim(COALESCE(p_payload->>'currency_code', '')), ''));
        IF v_currency_code IS NULL OR char_length(v_currency_code) <> 3 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'currency_code is required';
            EXIT body;
        END IF;
        SELECT curr.active_ind
          INTO v_currency_active
          FROM solar_app.ref_currencies AS curr
         WHERE curr.currency_code = v_currency_code;
        IF NOT FOUND OR v_currency_active IS NOT TRUE THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'currency_code is not valid';
            EXIT body;
        END IF;

        v_category_code := upper(NULLIF(btrim(COALESCE(p_payload->>'invoice_category_code', '')), ''));
        IF v_category_code IS NULL THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'invoice_category_code is required';
            EXIT body;
        END IF;
        SELECT rd.ref_data_id
          INTO v_category_id
          FROM solar_app.ref_data AS rd
          JOIN solar_app.ref_data_categories AS cat
            ON cat.category_id = rd.category_id
         WHERE cat.category_code = 'INVOICE_CATEGORIES'
           AND cat.active_ind IS TRUE
           AND rd.data_code = v_category_code
           AND rd.active_ind IS TRUE;
        IF v_category_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'invoice_category_code is not valid';
            EXIT body;
        END IF;

        v_status_code := upper(NULLIF(btrim(COALESCE(p_payload->>'invoice_status_code', 'INV_UNPAID')), ''));
        IF v_status_code IS NULL THEN
            v_status_code := 'INV_UNPAID';
        END IF;
        IF v_status_code NOT IN ('INV_DRAFT', 'INV_UNPAID') THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'invoice_status_code must be INV_DRAFT or INV_UNPAID on create';
            EXIT body;
        END IF;
        SELECT rd.ref_data_id
          INTO v_status_id
          FROM solar_app.ref_data AS rd
          JOIN solar_app.ref_data_categories AS cat
            ON cat.category_id = rd.category_id
         WHERE cat.category_code = 'INVOICE_STATUSES'
           AND cat.active_ind IS TRUE
           AND rd.data_code = v_status_code
           AND rd.active_ind IS TRUE;
        IF v_status_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'invoice_status_code is not valid';
            EXIT body;
        END IF;

        BEGIN
            v_taxable_amount := COALESCE((NULLIF(btrim(COALESCE(p_payload->>'taxable_amount', '')), ''))::NUMERIC, 0);
            v_tax_amount := COALESCE((NULLIF(btrim(COALESCE(p_payload->>'tax_amount', '')), ''))::NUMERIC, 0);
            IF NULLIF(btrim(COALESCE(p_payload->>'total_amount', '')), '') IS NULL THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'total_amount is required';
                EXIT body;
            END IF;
            v_total_amount := (btrim(p_payload->>'total_amount'))::NUMERIC;
        EXCEPTION
            WHEN OTHERS THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Invoice amounts must be numeric';
                EXIT body;
        END;
        IF v_taxable_amount < 0 OR v_tax_amount < 0 OR v_total_amount < 0 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Invoice amounts must be zero or greater';
            EXIT body;
        END IF;

        v_site_text := NULLIF(btrim(COALESCE(p_payload->>'site_id', '')), '');
        IF v_site_text IS NOT NULL THEN
            IF v_site_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'site_id is not valid';
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
                v_message := 'This site was not found for the customer';
                EXIT body;
            END IF;
        END IF;

        v_order_text := NULLIF(btrim(COALESCE(p_payload->>'related_order_id', '')), '');
        IF v_order_text IS NOT NULL THEN
            IF v_order_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'related_order_id is not valid';
                EXIT body;
            END IF;
            v_order_id := v_order_text::BIGINT;
            IF NOT EXISTS (
                SELECT 1
                  FROM solar_app.order_details AS ord
                 WHERE ord.order_id = v_order_id
                   AND ord.customer_id = v_customer_id
                   AND ord.active_ind IS TRUE
            ) THEN
                v_status := 'ERROR';
                v_code := 404;
                v_message := 'This order was not found for the customer';
                EXIT body;
            END IF;
        END IF;

        v_amc_text := NULLIF(btrim(COALESCE(p_payload->>'related_amc_contract_id', '')), '');
        IF v_amc_text IS NOT NULL THEN
            IF v_amc_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'related_amc_contract_id is not valid';
                EXIT body;
            END IF;
            v_amc_id := v_amc_text::BIGINT;
            IF NOT EXISTS (
                SELECT 1
                  FROM solar_app.amc_contract_details AS amc
                  JOIN solar_app.site_details AS site
                    ON site.site_id = amc.site_id
                 WHERE amc.amc_contract_id = v_amc_id
                   AND amc.active_ind IS TRUE
                   AND site.customer_id = v_customer_id
                   AND site.active_ind IS TRUE
            ) THEN
                v_status := 'ERROR';
                v_code := 404;
                v_message := 'This AMC contract was not found for the customer';
                EXIT body;
            END IF;
        END IF;

        v_sr_text := NULLIF(btrim(COALESCE(p_payload->>'related_service_request_id', '')), '');
        IF v_sr_text IS NOT NULL THEN
            IF v_sr_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'related_service_request_id is not valid';
                EXIT body;
            END IF;
            v_sr_id := v_sr_text::BIGINT;
            IF NOT EXISTS (
                SELECT 1
                  FROM solar_app.service_request_details AS sr
                 WHERE sr.service_request_id = v_sr_id
                   AND sr.customer_id = v_customer_id
                   AND sr.active_ind IS TRUE
            ) THEN
                v_status := 'ERROR';
                v_code := 404;
                v_message := 'This service request was not found for the customer';
                EXIT body;
            END IF;
        END IF;

        v_spr_text := NULLIF(btrim(COALESCE(p_payload->>'related_spare_part_request_id', '')), '');
        IF v_spr_text IS NOT NULL THEN
            IF v_spr_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'related_spare_part_request_id is not valid';
                EXIT body;
            END IF;
            v_spr_id := v_spr_text::BIGINT;
            IF NOT EXISTS (
                SELECT 1
                  FROM solar_app.spare_part_request_details AS spr
                  JOIN solar_app.job_assignment_details AS job
                    ON job.job_id = spr.job_id
                  JOIN solar_app.site_details AS site
                    ON site.site_id = job.site_id
                 WHERE spr.spare_part_request_id = v_spr_id
                   AND spr.active_ind IS TRUE
                   AND site.customer_id = v_customer_id
                   AND site.active_ind IS TRUE
            ) THEN
                v_status := 'ERROR';
                v_code := 404;
                v_message := 'This spare-part request was not found for the customer';
                EXIT body;
            END IF;
        END IF;

        v_remarks := NULLIF(btrim(COALESCE(p_payload->>'remarks', '')), '');
        IF v_remarks IS NOT NULL AND char_length(v_remarks) > 500 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'remarks must be 500 characters or fewer';
            EXIT body;
        END IF;

        IF p_payload ? 'lines' AND p_payload->'lines' IS NOT NULL AND jsonb_typeof(p_payload->'lines') <> 'array' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'lines must be a JSON array';
            EXIT body;
        END IF;
        v_lines := COALESCE(p_payload->'lines', '[]'::jsonb);

        IF p_payload ? 'tax_snapshots' AND p_payload->'tax_snapshots' IS NOT NULL
           AND jsonb_typeof(p_payload->'tax_snapshots') <> 'array' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'tax_snapshots must be a JSON array';
            EXIT body;
        END IF;
        v_tax_snapshots := COALESCE(p_payload->'tax_snapshots', '[]'::jsonb);

        BEGIN
            INSERT INTO solar_app.invoice_details (
                invoice_no,
                customer_id,
                site_id,
                related_order_id,
                invoice_category_ref_data_id,
                invoice_status_ref_data_id,
                invoice_date,
                currency_code,
                taxable_amount,
                tax_amount,
                total_amount,
                paid_amount,
                balance_amount,
                related_amc_contract_id,
                related_service_request_id,
                related_spare_part_request_id,
                remarks,
                active_ind,
                created_by,
                updated_by
            ) VALUES (
                v_invoice_no,
                v_customer_id,
                v_site_id,
                v_order_id,
                v_category_id,
                v_status_id,
                v_invoice_date,
                v_currency_code,
                v_taxable_amount,
                v_tax_amount,
                v_total_amount,
                0,
                v_total_amount,
                v_amc_id,
                v_sr_id,
                v_spr_id,
                v_remarks,
                TRUE,
                v_actor,
                v_actor
            )
            RETURNING invoice_id INTO v_invoice_id;
        EXCEPTION
            WHEN unique_violation THEN
                v_status := 'ERROR';
                v_code := 409;
                v_message := 'This invoice number is already recorded';
                EXIT body;
        END;

        FOR v_i IN 0 .. GREATEST(jsonb_array_length(v_lines) - 1, -1) LOOP
            v_line := v_lines->v_i;
            IF jsonb_typeof(v_line) <> 'object' THEN
                RAISE EXCEPTION 'Invoice line % must be an object', v_i + 1 USING ERRCODE = 'P0001';
            END IF;

            BEGIN
                v_line_no := (NULLIF(btrim(COALESCE(v_line->>'line_no', '')), ''))::INTEGER;
            EXCEPTION
                WHEN OTHERS THEN
                    RAISE EXCEPTION 'line_no is required for each invoice line' USING ERRCODE = 'P0001';
            END;
            IF v_line_no IS NULL OR v_line_no < 1 THEN
                RAISE EXCEPTION 'line_no must be a positive integer' USING ERRCODE = 'P0001';
            END IF;
            IF v_line_no = ANY (v_seen_line_nos) THEN
                RAISE EXCEPTION 'Duplicate line_no % in payload', v_line_no USING ERRCODE = 'P0001';
            END IF;
            v_seen_line_nos := array_append(v_seen_line_nos, v_line_no);

            v_line_desc := NULLIF(btrim(COALESCE(v_line->>'line_desc', '')), '');
            IF v_line_desc IS NULL OR char_length(v_line_desc) > 255 THEN
                RAISE EXCEPTION 'line_desc is required and must be 255 characters or fewer' USING ERRCODE = 'P0001';
            END IF;

            BEGIN
                v_quantity := COALESCE((NULLIF(btrim(COALESCE(v_line->>'quantity', '')), ''))::NUMERIC, 1);
                v_unit_rate := COALESCE((NULLIF(btrim(COALESCE(v_line->>'unit_rate', '')), ''))::NUMERIC, 0);
                IF NULLIF(btrim(COALESCE(v_line->>'line_amount', '')), '') IS NULL THEN
                    RAISE EXCEPTION 'line_amount is required' USING ERRCODE = 'P0001';
                END IF;
                v_line_amount := (btrim(v_line->>'line_amount'))::NUMERIC;
            EXCEPTION
                WHEN SQLSTATE 'P0001' THEN
                    RAISE;
                WHEN OTHERS THEN
                    RAISE EXCEPTION 'Invoice line amounts must be numeric' USING ERRCODE = 'P0001';
            END;
            IF v_quantity <= 0 THEN
                RAISE EXCEPTION 'quantity must be greater than zero' USING ERRCODE = 'P0001';
            END IF;

            v_tax_class := NULLIF(btrim(COALESCE(v_line->>'tax_classification_code', '')), '');
            IF v_tax_class IS NOT NULL AND char_length(v_tax_class) > 30 THEN
                RAISE EXCEPTION 'tax_classification_code must be 30 characters or fewer' USING ERRCODE = 'P0001';
            END IF;

            INSERT INTO solar_app.invoice_line_details (
                invoice_id,
                line_no,
                line_desc,
                tax_classification_code,
                quantity,
                unit_rate,
                line_amount,
                active_ind,
                created_by,
                updated_by
            ) VALUES (
                v_invoice_id,
                v_line_no,
                v_line_desc,
                v_tax_class,
                v_quantity,
                v_unit_rate,
                v_line_amount,
                TRUE,
                v_actor,
                v_actor
            )
            RETURNING invoice_line_id INTO v_invoice_line_id;

            v_line_map := v_line_map || jsonb_build_object(v_line_no::TEXT, to_jsonb(v_invoice_line_id));
        END LOOP;

        FOR v_i IN 0 .. GREATEST(jsonb_array_length(v_tax_snapshots) - 1, -1) LOOP
            v_tax := v_tax_snapshots->v_i;
            IF jsonb_typeof(v_tax) <> 'object' THEN
                RAISE EXCEPTION 'Tax snapshot % must be an object', v_i + 1 USING ERRCODE = 'P0001';
            END IF;

            v_tax_group := NULLIF(btrim(COALESCE(v_tax->>'tax_group_code', '')), '');
            v_tax_component := NULLIF(btrim(COALESCE(v_tax->>'tax_component_code', '')), '');
            v_tax_display := NULLIF(btrim(COALESCE(v_tax->>'tax_display_name', '')), '');
            v_calc_method := upper(NULLIF(btrim(COALESCE(v_tax->>'calculation_method', '')), ''));
            IF v_tax_group IS NULL OR char_length(v_tax_group) > 50
               OR v_tax_component IS NULL OR char_length(v_tax_component) > 50
               OR v_tax_display IS NULL OR char_length(v_tax_display) > 150 THEN
                RAISE EXCEPTION 'tax_group_code, tax_component_code, and tax_display_name are required' USING ERRCODE = 'P0001';
            END IF;
            IF v_calc_method NOT IN ('PERCENTAGE', 'FIXED_AMOUNT') THEN
                RAISE EXCEPTION 'calculation_method must be PERCENTAGE or FIXED_AMOUNT' USING ERRCODE = 'P0001';
            END IF;

            v_rate_percent := NULL;
            v_configured_rate := NULL;
            BEGIN
                IF v_calc_method = 'PERCENTAGE' THEN
                    IF NULLIF(btrim(COALESCE(v_tax->>'rate_percent', '')), '') IS NULL THEN
                        RAISE EXCEPTION 'rate_percent is required for PERCENTAGE tax snapshots' USING ERRCODE = 'P0001';
                    END IF;
                    IF NULLIF(btrim(COALESCE(v_tax->>'configured_rate_amount', '')), '') IS NOT NULL THEN
                        RAISE EXCEPTION 'configured_rate_amount is not allowed for PERCENTAGE tax snapshots' USING ERRCODE = 'P0001';
                    END IF;
                    v_rate_percent := (btrim(v_tax->>'rate_percent'))::NUMERIC;
                ELSE
                    IF NULLIF(btrim(COALESCE(v_tax->>'configured_rate_amount', '')), '') IS NULL THEN
                        RAISE EXCEPTION 'configured_rate_amount is required for FIXED_AMOUNT tax snapshots' USING ERRCODE = 'P0001';
                    END IF;
                    IF NULLIF(btrim(COALESCE(v_tax->>'rate_percent', '')), '') IS NOT NULL THEN
                        RAISE EXCEPTION 'rate_percent is not allowed for FIXED_AMOUNT tax snapshots' USING ERRCODE = 'P0001';
                    END IF;
                    v_configured_rate := (btrim(v_tax->>'configured_rate_amount'))::NUMERIC;
                END IF;
                IF NULLIF(btrim(COALESCE(v_tax->>'taxable_amount', '')), '') IS NULL
                   OR NULLIF(btrim(COALESCE(v_tax->>'tax_amount', '')), '') IS NULL THEN
                    RAISE EXCEPTION 'taxable_amount and tax_amount are required on tax snapshots' USING ERRCODE = 'P0001';
                END IF;
                v_tax_taxable := (btrim(v_tax->>'taxable_amount'))::NUMERIC;
                v_tax_amt := (btrim(v_tax->>'tax_amount'))::NUMERIC;
            EXCEPTION
                WHEN SQLSTATE 'P0001' THEN
                    RAISE;
                WHEN OTHERS THEN
                    RAISE EXCEPTION 'Tax snapshot amounts must be numeric' USING ERRCODE = 'P0001';
            END;
            IF v_tax_taxable < 0 OR v_tax_amt < 0 THEN
                RAISE EXCEPTION 'Tax snapshot amounts must be zero or greater' USING ERRCODE = 'P0001';
            END IF;
            IF v_calc_method = 'PERCENTAGE' AND (v_rate_percent < 0 OR v_rate_percent > 100) THEN
                RAISE EXCEPTION 'rate_percent must be between 0 and 100' USING ERRCODE = 'P0001';
            END IF;
            IF v_calc_method = 'FIXED_AMOUNT' AND v_configured_rate < 0 THEN
                RAISE EXCEPTION 'configured_rate_amount must be zero or greater' USING ERRCODE = 'P0001';
            END IF;

            IF v_tax ? 'jurisdiction_json' AND v_tax->'jurisdiction_json' IS NOT NULL THEN
                IF jsonb_typeof(v_tax->'jurisdiction_json') <> 'object' THEN
                    RAISE EXCEPTION 'jurisdiction_json must be a JSON object' USING ERRCODE = 'P0001';
                END IF;
                v_jurisdiction := v_tax->'jurisdiction_json';
            ELSE
                v_jurisdiction := '{}'::jsonb;
            END IF;

            v_tax_line_id := NULL;
            IF NULLIF(btrim(COALESCE(v_tax->>'line_no', '')), '') IS NOT NULL THEN
                BEGIN
                    v_tax_line_no := (btrim(v_tax->>'line_no'))::INTEGER;
                EXCEPTION
                    WHEN OTHERS THEN
                        RAISE EXCEPTION 'Tax snapshot line_no must be an integer' USING ERRCODE = 'P0001';
                END;
                IF NOT (v_line_map ? v_tax_line_no::TEXT) THEN
                    RAISE EXCEPTION 'Tax snapshot line_no % does not match a line in this invoice', v_tax_line_no
                        USING ERRCODE = 'P0001';
                END IF;
                v_tax_line_id := (v_line_map->>v_tax_line_no::TEXT)::BIGINT;
            END IF;

            INSERT INTO solar_app.invoice_tax_details (
                invoice_id,
                invoice_line_id,
                source_tax_rule_id,
                tax_group_code,
                tax_component_code,
                tax_display_name,
                calculation_method,
                rate_percent,
                configured_rate_amount,
                taxable_amount,
                tax_amount,
                jurisdiction_json,
                active_ind,
                created_by,
                updated_by
            ) VALUES (
                v_invoice_id,
                v_tax_line_id,
                NULL,
                v_tax_group,
                v_tax_component,
                v_tax_display,
                v_calc_method,
                v_rate_percent,
                v_configured_rate,
                v_tax_taxable,
                v_tax_amt,
                v_jurisdiction,
                TRUE,
                v_actor,
                v_actor
            );

            v_tax_sum := v_tax_sum + v_tax_amt;
        END LOOP;

        IF jsonb_array_length(v_tax_snapshots) > 0 AND v_tax_sum IS DISTINCT FROM v_tax_amount THEN
            RAISE EXCEPTION 'Sum of tax snapshot amounts must equal invoice tax_amount' USING ERRCODE = 'P0001';
        END IF;

        v_ntf_response := solar_app.fn_create_notification_details(
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'logged_in_user_id', v_actor,
                'recipient_user_id', v_customer_user_id::TEXT,
                'notification_type_code', 'NTF_BILLING_UPDATE',
                'title', 'Bill recorded',
                'body', format('Invoice %s was recorded for your account.', v_invoice_no),
                'related_entity_type', 'INVOICE',
                'related_entity_id', v_invoice_id::TEXT,
                'payload_json', jsonb_build_object(
                    'entity_type', 'INVOICE',
                    'entity_id', v_invoice_id::TEXT,
                    'invoice_no', v_invoice_no,
                    'customer_id', v_customer_id::TEXT
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
            'invoice_id', v_invoice_id::TEXT,
            'invoice_no', v_invoice_no,
            'customer_id', v_customer_id::TEXT,
            'invoice_status_code', v_status_code,
            'currency_code', v_currency_code,
            'taxable_amount', v_taxable_amount,
            'tax_amount', v_tax_amount,
            'total_amount', v_total_amount,
            'paid_amount', 0,
            'balance_amount', v_total_amount,
            'notification_id', v_notification_id
        ));
    EXCEPTION
        WHEN unique_violation THEN
            v_status := 'ERROR';
            v_code := 409;
            v_message := 'This invoice number is already recorded';
            v_data := NULL;
            v_log_error := SQLERRM;
            v_sql_state := SQLSTATE;
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            IF SQLSTATE = 'P0001' AND SQLERRM LIKE 'Notification enqueue failed%' THEN
                v_message := 'Invoice could not be recorded';
            ELSIF SQLSTATE = 'P0001' THEN
                v_code := 400;
                v_message := SQLERRM;
            ELSE
                v_message := 'Invoice could not be recorded';
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
            'fn_create_invoice_details',
            v_actor,
            v_admin_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'invoice_no', v_invoice_no,
                'customer_id', v_customer_id,
                'invoice_id', v_invoice_id,
                'currency_code', v_currency_code,
                'invoice_category_code', v_category_code,
                'has_lines', CASE WHEN v_lines IS NULL THEN NULL ELSE jsonb_array_length(v_lines) > 0 END,
                'has_tax_snapshots', CASE WHEN v_tax_snapshots IS NULL THEN NULL ELSE jsonb_array_length(v_tax_snapshots) > 0 END
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

COMMENT ON FUNCTION solar_app.fn_create_invoice_details(JSONB) IS
'Admin offline invoice create with optional lines/tax snapshots; enqueues NTF_BILLING_UPDATE.';
