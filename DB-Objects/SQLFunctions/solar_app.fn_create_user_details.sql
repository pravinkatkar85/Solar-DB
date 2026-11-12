-- Authored source for solar_app.fn_create_user_details.
-- Path B admin registration: user + customer + sites + equipment + MANUAL
-- commissioned/installed order + site access + NTF_ACCOUNT_READY.
-- Loaded by SQLScripts/02_functions.sql. Do not install until approved.
-- This is not fn_create_pin_user.

CREATE OR REPLACE FUNCTION solar_app.fn_create_user_details(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = pg_catalog, solar_app
AS $$
DECLARE
    v_started              TIMESTAMPTZ := clock_timestamp();
    v_api_endpoint         VARCHAR(255);
    v_actor                VARCHAR(50) := 'SYSTEM';
    v_status               VARCHAR(20) := 'SUCCESS';
    v_code                 INTEGER := 200;
    v_message              TEXT := 'Customer registered';
    v_data                 JSONB := NULL;
    v_response             JSONB;
    v_log_error            TEXT;
    v_sql_state            VARCHAR(10);
    v_log_payload          JSONB;
    v_token_hash           TEXT;
    v_session_count        INTEGER;
    v_admin_user_id        BIGINT;
    v_claimed              TEXT;
    v_active               BOOLEAN;
    v_account_code         VARCHAR(50);
    v_role_code            VARCHAR(50);
    v_country_id           BIGINT;
    v_phone_code           VARCHAR(8);
    v_min_length           SMALLINT;
    v_max_length           SMALLINT;
    v_phone_regex          VARCHAR(255);
    v_national             TEXT;
    v_mobile               VARCHAR(16);
    v_full_name            VARCHAR(150);
    v_customer_code        VARCHAR(30);
    v_billing_name         VARCHAR(150);
    v_tax_no               VARCHAR(50);
    v_bill_addr1           VARCHAR(255);
    v_bill_addr2           VARCHAR(255);
    v_bill_pincode_id      BIGINT;
    v_bill_pincode_text    TEXT;
    v_order_no             VARCHAR(30);
    v_order_status_code    TEXT;
    v_order_status_id      BIGINT;
    v_currency_code        CHAR(3);
    v_gross_amount         NUMERIC(14,2);
    v_remarks              VARCHAR(500);
    v_role_id              BIGINT;
    v_acct_status_id       BIGINT;
    v_source_id            BIGINT;
    v_access_owner_id      BIGINT;
    v_new_user_id          BIGINT;
    v_customer_id          BIGINT;
    v_order_id             BIGINT;
    v_sites                JSONB;
    v_site                 JSONB;
    v_site_idx             INTEGER;
    v_default_count        INTEGER := 0;
    v_default_site_id      BIGINT;
    v_first_site_id        BIGINT;
    v_site_id              BIGINT;
    v_site_name            VARCHAR(150);
    v_address1             VARCHAR(255);
    v_address2             VARCHAR(255);
    v_pincode_id           BIGINT;
    v_city_id              BIGINT;
    v_district_id          BIGINT;
    v_state_id             BIGINT;
    v_lat                  NUMERIC(10,7);
    v_lon                  NUMERIC(10,7);
    v_discom_id            BIGINT;
    v_consumer_no          VARCHAR(50);
    v_meter_no             VARCHAR(50);
    v_load_kw              NUMERIC(8,3);
    v_conn_type_id         BIGINT;
    v_inst_status_code     TEXT;
    v_inst_status_id       BIGINT;
    v_commissioning_on     DATE;
    v_is_default           BOOLEAN;
    v_equipment_arr        JSONB;
    v_equipment            JSONB;
    v_eq_idx               INTEGER;
    v_eq_type_code         TEXT;
    v_eq_type_id           BIGINT;
    v_eq_product_id        BIGINT;
    v_eq_brand_id          BIGINT;
    v_eq_model             VARCHAR(150);
    v_eq_serial            VARCHAR(80);
    v_eq_barcode           VARCHAR(80);
    v_eq_qty               NUMERIC(12,3);
    v_eq_panel_w           NUMERIC(10,3);
    v_eq_inv_kw            NUMERIC(8,3);
    v_eq_phase_id          BIGINT;
    v_eq_dongle            VARCHAR(80);
    v_eq_structure_id      BIGINT;
    v_eq_battery_ah        NUMERIC(10,2);
    v_eq_commissioned_on   DATE;
    v_eq_id                BIGINT;
    v_site_ids             JSONB := '[]'::jsonb;
    v_equipment_ids        JSONB := '[]'::jsonb;
    v_lines                JSONB;
    v_line                 JSONB;
    v_line_idx             INTEGER;
    v_line_no              INTEGER;
    v_line_desc            VARCHAR(255);
    v_line_product_id      BIGINT;
    v_line_qty             NUMERIC(12,3);
    v_line_rate            NUMERIC(12,2);
    v_line_amount          NUMERIC(14,2);
    v_line_tax             VARCHAR(30);
    v_tmp_text             TEXT;
    v_ntf_response         JSONB;
    v_notification_id      TEXT;
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

        IF NULLIF(btrim(COALESCE(p_payload->>'pin', '')), '') IS NOT NULL
           OR NULLIF(btrim(COALESCE(p_payload->>'pin_hash', '')), '') IS NOT NULL THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'PIN must not be set for Path B registration';
            EXIT body;
        END IF;

        v_token_hash := lower(NULLIF(btrim(COALESCE(p_payload->>'jwt_token_hash', '')), ''));
        IF v_token_hash IS NULL OR v_token_hash !~ '^[0-9a-f]{64}$' THEN
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

        SELECT session.user_id
          INTO v_admin_user_id
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
            v_message := 'This account cannot register customers';
            EXIT body;
        END IF;
        IF v_role_code IS DISTINCT FROM 'ROLE_ADMIN' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'Only an administrator can register Path B customers';
            EXIT body;
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

        IF EXISTS (
            SELECT 1
              FROM solar_app.user_details AS app_user
             WHERE app_user.mobile_e164 = v_mobile
               AND app_user.active_ind IS TRUE
        ) THEN
            v_status := 'ERROR';
            v_code := 409;
            v_message := 'An account with this mobile number already exists';
            EXIT body;
        END IF;

        v_full_name := NULLIF(btrim(p_payload->>'full_name'), '');
        IF v_full_name IS NULL OR char_length(v_full_name) > 150 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Enter the customer name';
            EXIT body;
        END IF;

        v_customer_code := NULLIF(btrim(p_payload->>'customer_code'), '');
        IF v_customer_code IS NULL OR char_length(v_customer_code) > 30 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Enter a customer code';
            EXIT body;
        END IF;
        IF EXISTS (
            SELECT 1
              FROM solar_app.customer_details AS customer
             WHERE customer.customer_code = v_customer_code
        ) THEN
            v_status := 'ERROR';
            v_code := 409;
            v_message := 'This customer code already exists';
            EXIT body;
        END IF;

        v_billing_name := COALESCE(
            NULLIF(btrim(p_payload->>'billing_name'), ''),
            v_full_name
        );
        IF char_length(v_billing_name) > 150 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'billing_name must be 150 characters or fewer';
            EXIT body;
        END IF;

        v_tax_no := NULLIF(btrim(p_payload->>'tax_registration_no'), '');
        IF v_tax_no IS NOT NULL AND char_length(v_tax_no) > 50 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'tax_registration_no must be 50 characters or fewer';
            EXIT body;
        END IF;

        v_bill_addr1 := NULLIF(btrim(p_payload->>'billing_address_line1'), '');
        IF v_bill_addr1 IS NOT NULL AND char_length(v_bill_addr1) > 255 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'billing_address_line1 must be 255 characters or fewer';
            EXIT body;
        END IF;
        v_bill_addr2 := NULLIF(btrim(p_payload->>'billing_address_line2'), '');
        IF v_bill_addr2 IS NOT NULL AND char_length(v_bill_addr2) > 255 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'billing_address_line2 must be 255 characters or fewer';
            EXIT body;
        END IF;

        v_bill_pincode_text := NULLIF(btrim(COALESCE(p_payload->>'billing_pincode_id', '')), '');
        IF v_bill_pincode_text IS NOT NULL THEN
            IF v_bill_pincode_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'billing_pincode_id is not valid';
                EXIT body;
            END IF;
            v_bill_pincode_id := v_bill_pincode_text::BIGINT;
            IF NOT EXISTS (
                SELECT 1
                  FROM solar_app.ref_pincodes AS pincode
                 WHERE pincode.pincode_id = v_bill_pincode_id
                   AND pincode.active_ind IS TRUE
            ) THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'billing_pincode_id is not valid';
                EXIT body;
            END IF;
        END IF;

        v_order_no := NULLIF(btrim(p_payload->>'order_no'), '');
        IF v_order_no IS NULL OR char_length(v_order_no) > 30 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Enter an order number';
            EXIT body;
        END IF;
        IF EXISTS (
            SELECT 1
              FROM solar_app.order_details AS ord
             WHERE ord.order_no = v_order_no
        ) THEN
            v_status := 'ERROR';
            v_code := 409;
            v_message := 'This order number already exists';
            EXIT body;
        END IF;

        v_order_status_code := upper(NULLIF(btrim(COALESCE(p_payload->>'order_status_code', '')), ''));
        IF v_order_status_code IS DISTINCT FROM 'ORD_INSTALLED'
           AND v_order_status_code IS DISTINCT FROM 'ORD_COMMISSIONED' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'order_status_code must be ORD_INSTALLED or ORD_COMMISSIONED';
            EXIT body;
        END IF;

        SELECT status_row.ref_data_id
          INTO v_order_status_id
          FROM solar_app.ref_data AS status_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = status_row.category_id
         WHERE category.category_code = 'ORDER_STATUSES'
           AND status_row.data_code = v_order_status_code
           AND category.active_ind IS TRUE
           AND status_row.active_ind IS TRUE;
        IF v_order_status_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Customer could not be registered';
            v_log_error := v_order_status_code || ' is not configured';
            EXIT body;
        END IF;

        v_currency_code := upper(NULLIF(btrim(COALESCE(p_payload->>'currency_code', '')), ''));
        IF v_currency_code IS NULL OR v_currency_code !~ '^[A-Z]{3}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'currency_code is required';
            EXIT body;
        END IF;
        IF NOT EXISTS (
            SELECT 1
              FROM solar_app.ref_currencies AS currency
             WHERE currency.currency_code = v_currency_code
               AND currency.active_ind IS TRUE
        ) THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'currency_code is not valid';
            EXIT body;
        END IF;

        v_tmp_text := NULLIF(btrim(COALESCE(p_payload->>'gross_amount', '')), '');
        IF v_tmp_text IS NULL THEN
            v_gross_amount := 0;
        ELSIF v_tmp_text !~ '^[0-9]+(\.[0-9]+)?$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'gross_amount is not valid';
            EXIT body;
        ELSE
            v_gross_amount := v_tmp_text::NUMERIC(14,2);
            IF v_gross_amount < 0 THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'gross_amount is not valid';
                EXIT body;
            END IF;
        END IF;

        v_remarks := NULLIF(btrim(p_payload->>'remarks'), '');
        IF v_remarks IS NOT NULL AND char_length(v_remarks) > 500 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'remarks must be 500 characters or fewer';
            EXIT body;
        END IF;

        IF p_payload ? 'sites' AND p_payload->'sites' IS NOT NULL
           AND jsonb_typeof(p_payload->'sites') <> 'null' THEN
            IF jsonb_typeof(p_payload->'sites') <> 'array' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'sites must be a JSON array';
                EXIT body;
            END IF;
            v_sites := p_payload->'sites';
        ELSE
            v_sites := NULL;
        END IF;
        IF v_sites IS NULL OR jsonb_array_length(v_sites) < 1 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Add at least one site';
            EXIT body;
        END IF;

        SELECT COUNT(*)
          INTO v_default_count
          FROM jsonb_array_elements(v_sites) AS site_row(value)
         WHERE lower(COALESCE(site_row.value->>'is_default', 'false')) IN ('true', 't', '1', 'yes');
        IF v_default_count > 1 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Only one site may be marked as default';
            EXIT body;
        END IF;

        IF p_payload ? 'order_lines' AND p_payload->'order_lines' IS NOT NULL
           AND jsonb_typeof(p_payload->'order_lines') <> 'null' THEN
            IF jsonb_typeof(p_payload->'order_lines') <> 'array' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'order_lines must be a JSON array';
                EXIT body;
            END IF;
            v_lines := p_payload->'order_lines';
        ELSE
            v_lines := '[]'::jsonb;
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
          INTO v_acct_status_id
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
           AND ref_row.data_code = 'REG_ADMIN_POST_INSTALL'
           AND category.active_ind IS TRUE
           AND ref_row.active_ind IS TRUE;

        SELECT ref_row.ref_data_id
          INTO v_access_owner_id
          FROM solar_app.ref_data AS ref_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = ref_row.category_id
         WHERE category.category_code = 'SITE_ACCESS_ROLES'
           AND ref_row.data_code = 'ACCESS_OWNER'
           AND category.active_ind IS TRUE
           AND ref_row.active_ind IS TRUE;

        IF v_role_id IS NULL
           OR v_acct_status_id IS NULL
           OR v_source_id IS NULL
           OR v_access_owner_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Customer could not be registered';
            v_log_error := 'Required Path B reference data is missing';
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
            NULL,
            TRUE,
            v_acct_status_id,
            v_source_id,
            v_actor,
            v_actor
        )
        RETURNING user_id INTO v_new_user_id;

        INSERT INTO solar_app.customer_details (
            user_id,
            customer_code,
            billing_name,
            tax_registration_no,
            billing_address_line1,
            billing_address_line2,
            billing_pincode_id,
            created_by,
            updated_by
        ) VALUES (
            v_new_user_id,
            v_customer_code,
            v_billing_name,
            v_tax_no,
            v_bill_addr1,
            v_bill_addr2,
            v_bill_pincode_id,
            v_actor,
            v_actor
        )
        RETURNING customer_id INTO v_customer_id;

        FOR v_site_idx IN 0 .. jsonb_array_length(v_sites) - 1 LOOP
            v_site := v_sites->v_site_idx;

            v_site_name := NULLIF(btrim(v_site->>'site_name'), '');
            IF v_site_name IS NULL OR char_length(v_site_name) > 150 THEN
                RAISE EXCEPTION 'Invalid site_name at sites[%]', v_site_idx
                    USING ERRCODE = 'P0001';
            END IF;

            v_address1 := NULLIF(btrim(v_site->>'address_line1'), '');
            IF v_address1 IS NULL OR char_length(v_address1) > 255 THEN
                RAISE EXCEPTION 'Enter the site address for sites[%]', v_site_idx
                    USING ERRCODE = 'P0001';
            END IF;
            v_address2 := NULLIF(btrim(v_site->>'address_line2'), '');
            IF v_address2 IS NOT NULL AND char_length(v_address2) > 255 THEN
                RAISE EXCEPTION 'address_line2 is too long for sites[%]', v_site_idx
                    USING ERRCODE = 'P0001';
            END IF;

            v_pincode_id := NULL;
            v_tmp_text := NULLIF(btrim(COALESCE(v_site->>'pincode_id', '')), '');
            IF v_tmp_text IS NOT NULL THEN
                IF v_tmp_text !~ '^[0-9]{1,18}$' THEN
                    RAISE EXCEPTION 'pincode_id is not valid for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
                v_pincode_id := v_tmp_text::BIGINT;
                IF NOT EXISTS (
                    SELECT 1 FROM solar_app.ref_pincodes AS pincode
                     WHERE pincode.pincode_id = v_pincode_id AND pincode.active_ind IS TRUE
                ) THEN
                    RAISE EXCEPTION 'pincode_id is not valid for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
            END IF;

            v_city_id := NULL;
            v_tmp_text := NULLIF(btrim(COALESCE(v_site->>'city_id', '')), '');
            IF v_tmp_text IS NOT NULL THEN
                IF v_tmp_text !~ '^[0-9]{1,18}$' THEN
                    RAISE EXCEPTION 'city_id is not valid for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
                v_city_id := v_tmp_text::BIGINT;
                IF NOT EXISTS (
                    SELECT 1 FROM solar_app.ref_cities AS city
                     WHERE city.city_id = v_city_id AND city.active_ind IS TRUE
                ) THEN
                    RAISE EXCEPTION 'city_id is not valid for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
            END IF;

            v_district_id := NULL;
            v_tmp_text := NULLIF(btrim(COALESCE(v_site->>'district_id', '')), '');
            IF v_tmp_text IS NOT NULL THEN
                IF v_tmp_text !~ '^[0-9]{1,18}$' THEN
                    RAISE EXCEPTION 'district_id is not valid for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
                v_district_id := v_tmp_text::BIGINT;
                IF NOT EXISTS (
                    SELECT 1 FROM solar_app.ref_districts AS district
                     WHERE district.district_id = v_district_id AND district.active_ind IS TRUE
                ) THEN
                    RAISE EXCEPTION 'district_id is not valid for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
            END IF;

            v_state_id := NULL;
            v_tmp_text := NULLIF(btrim(COALESCE(v_site->>'state_id', '')), '');
            IF v_tmp_text IS NOT NULL THEN
                IF v_tmp_text !~ '^[0-9]{1,18}$' THEN
                    RAISE EXCEPTION 'state_id is not valid for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
                v_state_id := v_tmp_text::BIGINT;
                IF NOT EXISTS (
                    SELECT 1 FROM solar_app.ref_states AS state_row
                     WHERE state_row.state_id = v_state_id AND state_row.active_ind IS TRUE
                ) THEN
                    RAISE EXCEPTION 'state_id is not valid for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
            END IF;

            v_lat := NULL;
            v_lon := NULL;
            IF NULLIF(btrim(COALESCE(v_site->>'latitude', '')), '') IS NOT NULL
               OR NULLIF(btrim(COALESCE(v_site->>'longitude', '')), '') IS NOT NULL THEN
                IF COALESCE(v_site->>'latitude', '') !~ '^-?[0-9]+(\.[0-9]+)?$'
                   OR COALESCE(v_site->>'longitude', '') !~ '^-?[0-9]+(\.[0-9]+)?$' THEN
                    RAISE EXCEPTION 'Enter valid GPS coordinates for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
                v_lat := (v_site->>'latitude')::NUMERIC(10,7);
                v_lon := (v_site->>'longitude')::NUMERIC(10,7);
                IF v_lat < -90 OR v_lat > 90 OR v_lon < -180 OR v_lon > 180 THEN
                    RAISE EXCEPTION 'Enter valid GPS coordinates for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
            END IF;

            v_discom_id := NULL;
            v_tmp_text := NULLIF(btrim(COALESCE(v_site->>'discom_id', '')), '');
            IF v_tmp_text IS NOT NULL THEN
                IF v_tmp_text !~ '^[0-9]{1,18}$' THEN
                    RAISE EXCEPTION 'discom_id is not valid for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
                v_discom_id := v_tmp_text::BIGINT;
                IF NOT EXISTS (
                    SELECT 1 FROM solar_app.ref_discoms AS discom
                     WHERE discom.discom_id = v_discom_id AND discom.active_ind IS TRUE
                ) THEN
                    RAISE EXCEPTION 'discom_id is not valid for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
            END IF;

            v_consumer_no := NULLIF(btrim(v_site->>'consumer_number'), '');
            IF v_consumer_no IS NOT NULL AND char_length(v_consumer_no) > 50 THEN
                RAISE EXCEPTION 'consumer_number is too long for sites[%]', v_site_idx
                    USING ERRCODE = 'P0001';
            END IF;
            v_meter_no := NULLIF(btrim(v_site->>'meter_number'), '');
            IF v_meter_no IS NOT NULL AND char_length(v_meter_no) > 50 THEN
                RAISE EXCEPTION 'meter_number is too long for sites[%]', v_site_idx
                    USING ERRCODE = 'P0001';
            END IF;

            v_load_kw := NULL;
            v_tmp_text := NULLIF(btrim(COALESCE(v_site->>'sanctioned_load_kw', '')), '');
            IF v_tmp_text IS NOT NULL THEN
                IF v_tmp_text !~ '^[0-9]+(\.[0-9]+)?$' THEN
                    RAISE EXCEPTION 'sanctioned_load_kw is not valid for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
                v_load_kw := v_tmp_text::NUMERIC(8,3);
                IF v_load_kw < 0 THEN
                    RAISE EXCEPTION 'sanctioned_load_kw is not valid for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
            END IF;

            v_conn_type_id := NULL;
            v_tmp_text := NULLIF(btrim(COALESCE(v_site->>'connection_type_ref_data_id', '')), '');
            IF v_tmp_text IS NOT NULL THEN
                IF v_tmp_text !~ '^[0-9]{1,18}$' THEN
                    RAISE EXCEPTION 'connection_type_ref_data_id is not valid for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
                v_conn_type_id := v_tmp_text::BIGINT;
                IF NOT EXISTS (
                    SELECT 1
                      FROM solar_app.ref_data AS ref_row
                      JOIN solar_app.ref_data_categories AS category
                        ON category.category_id = ref_row.category_id
                     WHERE ref_row.ref_data_id = v_conn_type_id
                       AND category.category_code = 'CONNECTION_TYPES'
                       AND category.active_ind IS TRUE
                       AND ref_row.active_ind IS TRUE
                ) THEN
                    RAISE EXCEPTION 'connection_type_ref_data_id is not valid for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
            END IF;

            v_inst_status_code := upper(NULLIF(btrim(COALESCE(v_site->>'installation_status_code', '')), ''));
            IF v_inst_status_code IS DISTINCT FROM 'INST_INSTALLED'
               AND v_inst_status_code IS DISTINCT FROM 'INST_COMMISSIONED' THEN
                RAISE EXCEPTION 'installation_status_code must be INST_INSTALLED or INST_COMMISSIONED for sites[%]', v_site_idx
                    USING ERRCODE = 'P0001';
            END IF;
            SELECT status_row.ref_data_id
              INTO v_inst_status_id
              FROM solar_app.ref_data AS status_row
              JOIN solar_app.ref_data_categories AS category
                ON category.category_id = status_row.category_id
             WHERE category.category_code = 'INSTALLATION_STATUSES'
               AND status_row.data_code = v_inst_status_code
               AND category.active_ind IS TRUE
               AND status_row.active_ind IS TRUE;
            IF v_inst_status_id IS NULL THEN
                RAISE EXCEPTION '% is not configured', v_inst_status_code
                    USING ERRCODE = 'P0001';
            END IF;

            v_tmp_text := NULLIF(btrim(COALESCE(v_site->>'commissioning_on', '')), '');
            IF v_tmp_text IS NULL OR v_tmp_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
                RAISE EXCEPTION 'commissioning_on is required for sites[%]', v_site_idx
                    USING ERRCODE = 'P0001';
            END IF;
            v_commissioning_on := v_tmp_text::DATE;

            v_is_default := lower(COALESCE(v_site->>'is_default', 'false'))
                IN ('true', 't', '1', 'yes');
            IF v_default_count = 0 AND v_site_idx = 0 THEN
                v_is_default := TRUE;
            END IF;

            IF v_site ? 'equipment' AND v_site->'equipment' IS NOT NULL
               AND jsonb_typeof(v_site->'equipment') <> 'null' THEN
                IF jsonb_typeof(v_site->'equipment') <> 'array' THEN
                    RAISE EXCEPTION 'equipment must be a JSON array for sites[%]', v_site_idx
                        USING ERRCODE = 'P0001';
                END IF;
                v_equipment_arr := v_site->'equipment';
            ELSE
                v_equipment_arr := NULL;
            END IF;
            IF v_equipment_arr IS NULL OR jsonb_array_length(v_equipment_arr) < 1 THEN
                RAISE EXCEPTION 'Add equipment for sites[%]', v_site_idx
                    USING ERRCODE = 'P0001';
            END IF;

            INSERT INTO solar_app.site_details (
                customer_id,
                site_name,
                address_line1,
                address_line2,
                pincode_id,
                city_id,
                district_id,
                state_id,
                latitude,
                longitude,
                discom_id,
                consumer_number,
                meter_number,
                sanctioned_load_kw,
                connection_type_ref_data_id,
                installation_status_ref_data_id,
                commissioning_on,
                created_by,
                updated_by
            ) VALUES (
                v_customer_id,
                v_site_name,
                v_address1,
                v_address2,
                v_pincode_id,
                v_city_id,
                v_district_id,
                v_state_id,
                v_lat,
                v_lon,
                v_discom_id,
                v_consumer_no,
                v_meter_no,
                v_load_kw,
                v_conn_type_id,
                v_inst_status_id,
                v_commissioning_on,
                v_actor,
                v_actor
            )
            RETURNING site_id INTO v_site_id;

            IF v_first_site_id IS NULL THEN
                v_first_site_id := v_site_id;
            END IF;
            IF v_is_default THEN
                v_default_site_id := v_site_id;
            END IF;
            v_site_ids := v_site_ids || to_jsonb(v_site_id::TEXT);

            INSERT INTO solar_app.user_site_access_details (
                user_id,
                site_id,
                is_default,
                access_role_ref_data_id,
                created_by,
                updated_by
            ) VALUES (
                v_new_user_id,
                v_site_id,
                v_is_default,
                v_access_owner_id,
                v_actor,
                v_actor
            );

            FOR v_eq_idx IN 0 .. jsonb_array_length(v_equipment_arr) - 1 LOOP
                v_equipment := v_equipment_arr->v_eq_idx;

                v_eq_type_code := upper(NULLIF(btrim(COALESCE(v_equipment->>'equipment_type_code', '')), ''));
                IF v_eq_type_code IS NULL THEN
                    RAISE EXCEPTION 'equipment_type_code is required for sites[%].equipment[%]',
                        v_site_idx, v_eq_idx
                        USING ERRCODE = 'P0001';
                END IF;
                SELECT type_row.ref_data_id
                  INTO v_eq_type_id
                  FROM solar_app.ref_data AS type_row
                  JOIN solar_app.ref_data_categories AS category
                    ON category.category_id = type_row.category_id
                 WHERE category.category_code = 'EQUIPMENT_TYPES'
                   AND type_row.data_code = v_eq_type_code
                   AND category.active_ind IS TRUE
                   AND type_row.active_ind IS TRUE;
                IF v_eq_type_id IS NULL THEN
                    RAISE EXCEPTION 'equipment_type_code is not valid for sites[%].equipment[%]',
                        v_site_idx, v_eq_idx
                        USING ERRCODE = 'P0001';
                END IF;

                v_eq_product_id := NULL;
                v_tmp_text := NULLIF(btrim(COALESCE(v_equipment->>'product_id', '')), '');
                IF v_tmp_text IS NOT NULL THEN
                    IF v_tmp_text !~ '^[0-9]{1,18}$' THEN
                        RAISE EXCEPTION 'product_id is not valid for sites[%].equipment[%]',
                            v_site_idx, v_eq_idx
                            USING ERRCODE = 'P0001';
                    END IF;
                    v_eq_product_id := v_tmp_text::BIGINT;
                    IF NOT EXISTS (
                        SELECT 1 FROM solar_app.product_details AS product
                         WHERE product.product_id = v_eq_product_id
                           AND product.active_ind IS TRUE
                    ) THEN
                        RAISE EXCEPTION 'product_id is not valid for sites[%].equipment[%]',
                            v_site_idx, v_eq_idx
                            USING ERRCODE = 'P0001';
                    END IF;
                END IF;

                v_eq_brand_id := NULL;
                v_tmp_text := NULLIF(btrim(COALESCE(v_equipment->>'brand_ref_data_id', '')), '');
                IF v_tmp_text IS NOT NULL THEN
                    IF v_tmp_text !~ '^[0-9]{1,18}$' THEN
                        RAISE EXCEPTION 'brand_ref_data_id is not valid for sites[%].equipment[%]',
                            v_site_idx, v_eq_idx
                            USING ERRCODE = 'P0001';
                    END IF;
                    v_eq_brand_id := v_tmp_text::BIGINT;
                    IF NOT EXISTS (
                        SELECT 1
                          FROM solar_app.ref_data AS ref_row
                          JOIN solar_app.ref_data_categories AS category
                            ON category.category_id = ref_row.category_id
                         WHERE ref_row.ref_data_id = v_eq_brand_id
                           AND category.category_code = 'EQUIPMENT_BRANDS'
                           AND category.active_ind IS TRUE
                           AND ref_row.active_ind IS TRUE
                    ) THEN
                        RAISE EXCEPTION 'brand_ref_data_id is not valid for sites[%].equipment[%]',
                            v_site_idx, v_eq_idx
                            USING ERRCODE = 'P0001';
                    END IF;
                END IF;

                v_eq_model := NULLIF(btrim(v_equipment->>'model_name'), '');
                IF v_eq_model IS NOT NULL AND char_length(v_eq_model) > 150 THEN
                    RAISE EXCEPTION 'model_name is too long for sites[%].equipment[%]',
                        v_site_idx, v_eq_idx
                        USING ERRCODE = 'P0001';
                END IF;
                v_eq_serial := NULLIF(btrim(v_equipment->>'serial_no'), '');
                IF v_eq_serial IS NOT NULL AND char_length(v_eq_serial) > 80 THEN
                    RAISE EXCEPTION 'serial_no is too long for sites[%].equipment[%]',
                        v_site_idx, v_eq_idx
                        USING ERRCODE = 'P0001';
                END IF;
                v_eq_barcode := NULLIF(btrim(v_equipment->>'barcode'), '');
                IF v_eq_barcode IS NOT NULL AND char_length(v_eq_barcode) > 80 THEN
                    RAISE EXCEPTION 'barcode is too long for sites[%].equipment[%]',
                        v_site_idx, v_eq_idx
                        USING ERRCODE = 'P0001';
                END IF;
                v_eq_dongle := NULLIF(btrim(v_equipment->>'monitoring_dongle_id'), '');
                IF v_eq_dongle IS NOT NULL AND char_length(v_eq_dongle) > 80 THEN
                    RAISE EXCEPTION 'monitoring_dongle_id is too long for sites[%].equipment[%]',
                        v_site_idx, v_eq_idx
                        USING ERRCODE = 'P0001';
                END IF;

                v_tmp_text := NULLIF(btrim(COALESCE(v_equipment->>'quantity', '')), '');
                IF v_tmp_text IS NULL THEN
                    v_eq_qty := 1;
                ELSIF v_tmp_text !~ '^[0-9]+(\.[0-9]+)?$' THEN
                    RAISE EXCEPTION 'quantity is not valid for sites[%].equipment[%]',
                        v_site_idx, v_eq_idx
                        USING ERRCODE = 'P0001';
                ELSE
                    v_eq_qty := v_tmp_text::NUMERIC(12,3);
                    IF v_eq_qty <= 0 THEN
                        RAISE EXCEPTION 'quantity is not valid for sites[%].equipment[%]',
                            v_site_idx, v_eq_idx
                            USING ERRCODE = 'P0001';
                    END IF;
                END IF;

                v_eq_panel_w := NULL;
                v_tmp_text := NULLIF(btrim(COALESCE(v_equipment->>'panel_wattage', '')), '');
                IF v_tmp_text IS NOT NULL THEN
                    IF v_tmp_text !~ '^[0-9]+(\.[0-9]+)?$' THEN
                        RAISE EXCEPTION 'panel_wattage is not valid for sites[%].equipment[%]',
                            v_site_idx, v_eq_idx
                            USING ERRCODE = 'P0001';
                    END IF;
                    v_eq_panel_w := v_tmp_text::NUMERIC(10,3);
                END IF;

                v_eq_inv_kw := NULL;
                v_tmp_text := NULLIF(btrim(COALESCE(v_equipment->>'inverter_capacity_kw', '')), '');
                IF v_tmp_text IS NOT NULL THEN
                    IF v_tmp_text !~ '^[0-9]+(\.[0-9]+)?$' THEN
                        RAISE EXCEPTION 'inverter_capacity_kw is not valid for sites[%].equipment[%]',
                            v_site_idx, v_eq_idx
                            USING ERRCODE = 'P0001';
                    END IF;
                    v_eq_inv_kw := v_tmp_text::NUMERIC(8,3);
                END IF;

                v_eq_battery_ah := NULL;
                v_tmp_text := NULLIF(btrim(COALESCE(v_equipment->>'battery_capacity_ah', '')), '');
                IF v_tmp_text IS NOT NULL THEN
                    IF v_tmp_text !~ '^[0-9]+(\.[0-9]+)?$' THEN
                        RAISE EXCEPTION 'battery_capacity_ah is not valid for sites[%].equipment[%]',
                            v_site_idx, v_eq_idx
                            USING ERRCODE = 'P0001';
                    END IF;
                    v_eq_battery_ah := v_tmp_text::NUMERIC(10,2);
                END IF;

                v_eq_phase_id := NULL;
                v_tmp_text := NULLIF(btrim(COALESCE(v_equipment->>'phase_type_ref_data_id', '')), '');
                IF v_tmp_text IS NOT NULL THEN
                    IF v_tmp_text !~ '^[0-9]{1,18}$' THEN
                        RAISE EXCEPTION 'phase_type_ref_data_id is not valid for sites[%].equipment[%]',
                            v_site_idx, v_eq_idx
                            USING ERRCODE = 'P0001';
                    END IF;
                    v_eq_phase_id := v_tmp_text::BIGINT;
                    IF NOT EXISTS (
                        SELECT 1
                          FROM solar_app.ref_data AS ref_row
                          JOIN solar_app.ref_data_categories AS category
                            ON category.category_id = ref_row.category_id
                         WHERE ref_row.ref_data_id = v_eq_phase_id
                           AND category.category_code = 'PHASE_TYPES'
                           AND category.active_ind IS TRUE
                           AND ref_row.active_ind IS TRUE
                    ) THEN
                        RAISE EXCEPTION 'phase_type_ref_data_id is not valid for sites[%].equipment[%]',
                            v_site_idx, v_eq_idx
                            USING ERRCODE = 'P0001';
                    END IF;
                END IF;

                v_eq_structure_id := NULL;
                v_tmp_text := NULLIF(btrim(COALESCE(v_equipment->>'structure_type_ref_data_id', '')), '');
                IF v_tmp_text IS NOT NULL THEN
                    IF v_tmp_text !~ '^[0-9]{1,18}$' THEN
                        RAISE EXCEPTION 'structure_type_ref_data_id is not valid for sites[%].equipment[%]',
                            v_site_idx, v_eq_idx
                            USING ERRCODE = 'P0001';
                    END IF;
                    v_eq_structure_id := v_tmp_text::BIGINT;
                    IF NOT EXISTS (
                        SELECT 1
                          FROM solar_app.ref_data AS ref_row
                          JOIN solar_app.ref_data_categories AS category
                            ON category.category_id = ref_row.category_id
                         WHERE ref_row.ref_data_id = v_eq_structure_id
                           AND category.category_code = 'STRUCTURE_TYPES'
                           AND category.active_ind IS TRUE
                           AND ref_row.active_ind IS TRUE
                    ) THEN
                        RAISE EXCEPTION 'structure_type_ref_data_id is not valid for sites[%].equipment[%]',
                            v_site_idx, v_eq_idx
                            USING ERRCODE = 'P0001';
                    END IF;
                END IF;

                v_eq_commissioned_on := v_commissioning_on;
                v_tmp_text := NULLIF(btrim(COALESCE(v_equipment->>'commissioned_on', '')), '');
                IF v_tmp_text IS NOT NULL THEN
                    IF v_tmp_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
                        RAISE EXCEPTION 'commissioned_on is not valid for sites[%].equipment[%]',
                            v_site_idx, v_eq_idx
                            USING ERRCODE = 'P0001';
                    END IF;
                    v_eq_commissioned_on := v_tmp_text::DATE;
                END IF;

                INSERT INTO solar_app.equipment_details (
                    site_id,
                    product_id,
                    equipment_type_ref_data_id,
                    brand_ref_data_id,
                    model_name,
                    serial_no,
                    barcode,
                    quantity,
                    panel_wattage,
                    inverter_capacity_kw,
                    phase_type_ref_data_id,
                    monitoring_dongle_id,
                    structure_type_ref_data_id,
                    battery_capacity_ah,
                    commissioned_on,
                    created_by,
                    updated_by
                ) VALUES (
                    v_site_id,
                    v_eq_product_id,
                    v_eq_type_id,
                    v_eq_brand_id,
                    v_eq_model,
                    v_eq_serial,
                    v_eq_barcode,
                    v_eq_qty,
                    v_eq_panel_w,
                    v_eq_inv_kw,
                    v_eq_phase_id,
                    v_eq_dongle,
                    v_eq_structure_id,
                    v_eq_battery_ah,
                    v_eq_commissioned_on,
                    v_actor,
                    v_actor
                )
                RETURNING equipment_id INTO v_eq_id;

                v_equipment_ids := v_equipment_ids || to_jsonb(v_eq_id::TEXT);
            END LOOP;
        END LOOP;

        IF v_default_site_id IS NULL THEN
            v_default_site_id := v_first_site_id;
        END IF;

        INSERT INTO solar_app.order_details (
            order_no,
            order_source,
            customer_id,
            site_id,
            user_id,
            order_status_ref_data_id,
            assigned_admin_user_id,
            gross_amount,
            currency_code,
            remarks,
            created_by,
            updated_by
        ) VALUES (
            v_order_no,
            'MANUAL',
            v_customer_id,
            v_default_site_id,
            v_new_user_id,
            v_order_status_id,
            v_admin_user_id,
            v_gross_amount,
            v_currency_code,
            v_remarks,
            v_actor,
            v_actor
        )
        RETURNING order_id INTO v_order_id;

        UPDATE solar_app.site_details AS site
           SET order_id = v_order_id,
               updated_by = v_actor,
               updated_on = clock_timestamp()
         WHERE site.customer_id = v_customer_id
           AND site.active_ind IS TRUE
           AND site.site_id IN (
                SELECT site_id_text::BIGINT
                  FROM jsonb_array_elements_text(v_site_ids) AS site_id_text
           );

        FOR v_line_idx IN 0 .. jsonb_array_length(v_lines) - 1 LOOP
            v_line := v_lines->v_line_idx;

            v_tmp_text := NULLIF(btrim(COALESCE(v_line->>'line_no', '')), '');
            IF v_tmp_text IS NULL OR v_tmp_text !~ '^[0-9]{1,9}$' THEN
                RAISE EXCEPTION 'line_no is required for order_lines[%]', v_line_idx
                    USING ERRCODE = 'P0001';
            END IF;
            v_line_no := v_tmp_text::INTEGER;
            IF v_line_no < 1 THEN
                RAISE EXCEPTION 'line_no is required for order_lines[%]', v_line_idx
                    USING ERRCODE = 'P0001';
            END IF;

            v_line_desc := NULLIF(btrim(v_line->>'line_desc'), '');
            IF v_line_desc IS NULL OR char_length(v_line_desc) > 255 THEN
                RAISE EXCEPTION 'line_desc is required for order_lines[%]', v_line_idx
                    USING ERRCODE = 'P0001';
            END IF;

            v_line_product_id := NULL;
            v_tmp_text := NULLIF(btrim(COALESCE(v_line->>'product_id', '')), '');
            IF v_tmp_text IS NOT NULL THEN
                IF v_tmp_text !~ '^[0-9]{1,18}$' THEN
                    RAISE EXCEPTION 'product_id is not valid for order_lines[%]', v_line_idx
                        USING ERRCODE = 'P0001';
                END IF;
                v_line_product_id := v_tmp_text::BIGINT;
                IF NOT EXISTS (
                    SELECT 1 FROM solar_app.product_details AS product
                     WHERE product.product_id = v_line_product_id
                       AND product.active_ind IS TRUE
                ) THEN
                    RAISE EXCEPTION 'product_id is not valid for order_lines[%]', v_line_idx
                        USING ERRCODE = 'P0001';
                END IF;
            END IF;

            v_tmp_text := NULLIF(btrim(COALESCE(v_line->>'quantity', '')), '');
            IF v_tmp_text IS NULL THEN
                v_line_qty := 1;
            ELSIF v_tmp_text !~ '^[0-9]+(\.[0-9]+)?$' THEN
                RAISE EXCEPTION 'quantity is not valid for order_lines[%]', v_line_idx
                    USING ERRCODE = 'P0001';
            ELSE
                v_line_qty := v_tmp_text::NUMERIC(12,3);
                IF v_line_qty <= 0 THEN
                    RAISE EXCEPTION 'quantity is not valid for order_lines[%]', v_line_idx
                        USING ERRCODE = 'P0001';
                END IF;
            END IF;

            v_tmp_text := NULLIF(btrim(COALESCE(v_line->>'unit_rate', '')), '');
            IF v_tmp_text IS NULL THEN
                v_line_rate := 0;
            ELSIF v_tmp_text !~ '^[0-9]+(\.[0-9]+)?$' THEN
                RAISE EXCEPTION 'unit_rate is not valid for order_lines[%]', v_line_idx
                    USING ERRCODE = 'P0001';
            ELSE
                v_line_rate := v_tmp_text::NUMERIC(12,2);
            END IF;

            v_tmp_text := NULLIF(btrim(COALESCE(v_line->>'line_amount', '')), '');
            IF v_tmp_text IS NULL OR v_tmp_text !~ '^[0-9]+(\.[0-9]+)?$' THEN
                RAISE EXCEPTION 'line_amount is required for order_lines[%]', v_line_idx
                    USING ERRCODE = 'P0001';
            END IF;
            v_line_amount := v_tmp_text::NUMERIC(14,2);

            v_line_tax := NULLIF(btrim(v_line->>'tax_classification_code'), '');
            IF v_line_tax IS NOT NULL AND char_length(v_line_tax) > 30 THEN
                RAISE EXCEPTION 'tax_classification_code is too long for order_lines[%]', v_line_idx
                    USING ERRCODE = 'P0001';
            END IF;

            INSERT INTO solar_app.order_line_details (
                order_id,
                line_no,
                product_id,
                line_desc,
                tax_classification_code,
                quantity,
                unit_rate,
                line_amount,
                created_by,
                updated_by
            ) VALUES (
                v_order_id,
                v_line_no,
                v_line_product_id,
                v_line_desc,
                v_line_tax,
                v_line_qty,
                v_line_rate,
                v_line_amount,
                v_actor,
                v_actor
            );
        END LOOP;

        v_ntf_response := solar_app.fn_create_notification_details(
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'logged_in_user_id', v_actor,
                'recipient_user_id', v_new_user_id::TEXT,
                'notification_type_code', 'NTF_ACCOUNT_READY',
                'title', 'Account ready',
                'body', 'Your account is ready. Sign in with your registered mobile number after you set a PIN.',
                'related_entity_type', 'USER',
                'related_entity_id', v_new_user_id::TEXT,
                'payload_json', jsonb_build_object(
                    'entity_type', 'USER',
                    'entity_id', v_new_user_id::TEXT,
                    'customer_id', v_customer_id::TEXT,
                    'order_id', v_order_id::TEXT
                )
            ))
        );

        IF COALESCE(v_ntf_response->>'status', 'ERROR') IS DISTINCT FROM 'SUCCESS' THEN
            RAISE EXCEPTION 'Path B notification enqueue failed: %',
                COALESCE(v_ntf_response->>'message', 'unknown error')
                USING ERRCODE = 'P0001';
        END IF;
        v_notification_id := v_ntf_response->'data'->>'notification_id';

        v_data := jsonb_build_object(
            'user_id', v_new_user_id::TEXT,
            'customer_id', v_customer_id::TEXT,
            'customer_code', v_customer_code,
            'order_id', v_order_id::TEXT,
            'order_no', v_order_no,
            'site_ids', v_site_ids,
            'equipment_ids', v_equipment_ids,
            'notification_id', v_notification_id
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_status := 'ERROR';
            v_code := 409;
            v_message := 'A unique Path B value already exists';
            v_data := NULL;
            v_log_error := SQLERRM;
            v_sql_state := SQLSTATE;
            IF SQLERRM ILIKE '%mobile%' THEN
                v_message := 'An account with this mobile number already exists';
            ELSIF SQLERRM ILIKE '%customer_code%' OR SQLERRM ILIKE '%customer_details_code%' THEN
                v_message := 'This customer code already exists';
            ELSIF SQLERRM ILIKE '%order_no%' OR SQLERRM ILIKE '%order_details_no%' THEN
                v_message := 'This order number already exists';
            END IF;
        WHEN SQLSTATE 'P0001' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := SQLERRM;
            v_data := NULL;
            v_log_error := SQLERRM;
            v_sql_state := SQLSTATE;
            IF SQLERRM ILIKE '%notification enqueue failed%'
               OR SQLERRM ILIKE '%is not configured%' THEN
                v_code := 500;
                v_message := 'Customer could not be registered';
            END IF;
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Customer could not be registered';
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
            'logged_in_user_id', v_actor,
            'country_id', p_payload->>'country_id',
            'customer_code', p_payload->>'customer_code',
            'order_no', p_payload->>'order_no',
            'order_status_code', p_payload->>'order_status_code',
            'site_count', CASE
                WHEN p_payload ? 'sites' AND jsonb_typeof(p_payload->'sites') = 'array'
                THEN jsonb_array_length(p_payload->'sites')
                ELSE NULL
            END
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
            'fn_create_user_details',
            v_actor,
            v_new_user_id,
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

COMMENT ON FUNCTION solar_app.fn_create_user_details(JSONB) IS
'Path B ROLE_ADMIN registration: user (NULL PIN, REG_ADMIN_POST_INSTALL), customer, sites, equipment, MANUAL Installed/Commissioned order, site access, and NTF_ACCOUNT_READY.';
