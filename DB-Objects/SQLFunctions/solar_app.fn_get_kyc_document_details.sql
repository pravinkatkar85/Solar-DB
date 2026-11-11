-- Lists active KYC documents.
-- Customers: only documents for the session user's customer record.
-- ROLE_ADMIN: cross-customer queue (admin may have no customer_details row).
-- Optional site_id and status_code filters. A payload user id / role is not trusted.
-- Do not install this file until separately approved.

CREATE OR REPLACE FUNCTION solar_app.fn_get_kyc_document_details(p_payload JSONB)
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
    v_message       TEXT := 'KYC documents loaded';
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
    v_role_code     VARCHAR(50);
    v_is_admin      BOOLEAN := FALSE;
    v_claimed       TEXT;
    v_customer_id   BIGINT;
    v_site_text     TEXT;
    v_site_id       BIGINT;
    v_status_text   TEXT;
    v_status_code   VARCHAR(50);
    v_rows          JSONB;
    v_types         JSONB;
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

        SELECT app_user.active_ind, account_row.data_code, role_row.data_code
          INTO v_active, v_account_code, v_role_code
          FROM solar_app.user_details AS app_user
          LEFT JOIN solar_app.ref_data AS account_row
            ON account_row.ref_data_id = app_user.account_status_ref_data_id
          LEFT JOIN solar_app.ref_data AS role_row
            ON role_row.ref_data_id = app_user.role_ref_data_id
         WHERE app_user.user_id = v_user_id;

        IF NOT FOUND OR v_active IS NOT TRUE OR v_account_code = 'ACCT_SUSPENDED' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'This account cannot view KYC documents';
            EXIT body;
        END IF;

        v_is_admin := (v_role_code IS NOT DISTINCT FROM 'ROLE_ADMIN');

        SELECT customer.customer_id
          INTO v_customer_id
          FROM solar_app.customer_details AS customer
         WHERE customer.user_id = v_user_id
           AND customer.active_ind IS TRUE;

        v_site_text := NULLIF(btrim(COALESCE(p_payload->>'site_id', '')), '');
        IF v_site_text IS NOT NULL THEN
            IF v_site_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Choose a site';
                EXIT body;
            END IF;
            v_site_id := v_site_text::BIGINT;
            IF v_is_admin THEN
                IF NOT EXISTS (
                    SELECT 1
                      FROM solar_app.site_details AS site
                     WHERE site.site_id = v_site_id
                       AND site.active_ind IS TRUE
                ) THEN
                    v_status := 'ERROR';
                    v_code := 404;
                    v_message := 'This site was not found';
                    EXIT body;
                END IF;
            ELSIF v_customer_id IS NULL OR NOT EXISTS (
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
        END IF;

        v_status_text := NULLIF(btrim(COALESCE(p_payload->>'status_code', '')), '');
        IF v_status_text IS NOT NULL THEN
            v_status_code := upper(v_status_text);
            IF v_status_code NOT IN ('KYC_PENDING', 'KYC_APPROVED', 'ACTION_REQUIRED') THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Choose a document status';
                EXIT body;
            END IF;
            IF NOT EXISTS (
                SELECT 1
                  FROM solar_app.ref_data AS status_row
                  JOIN solar_app.ref_data_categories AS category
                    ON category.category_id = status_row.category_id
                 WHERE category.category_code = 'DOCUMENT_VERIFICATION_STATUSES'
                   AND status_row.data_code = v_status_code
                   AND category.active_ind IS TRUE
                   AND status_row.active_ind IS TRUE
            ) THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Choose a document status';
                EXIT body;
            END IF;
        END IF;

        SELECT COALESCE(jsonb_agg(listed.item ORDER BY listed.sort_order, listed.data_code), '[]'::jsonb)
          INTO v_types
          FROM (
                SELECT type_row.sort_order,
                       type_row.data_code,
                       jsonb_build_object(
                           'document_type_id', type_row.ref_data_id::TEXT,
                           'document_type_code', type_row.data_code,
                           'document_type_name', type_row.data_value
                       ) AS item
                  FROM solar_app.ref_data AS type_row
                  JOIN solar_app.ref_data_categories AS category
                    ON category.category_id = type_row.category_id
                 WHERE category.category_code = 'DOCUMENT_TYPES'
                   AND category.active_ind IS TRUE
                   AND type_row.active_ind IS TRUE
               ) AS listed;

        IF (NOT v_is_admin) AND v_customer_id IS NULL THEN
            v_rows := '[]'::jsonb;
        ELSE
            SELECT COALESCE(jsonb_agg(listed.item ORDER BY listed.created_on DESC), '[]'::jsonb)
              INTO v_rows
              FROM (
                    SELECT doc.created_on,
                           jsonb_build_object(
                               'kyc_document_id', doc.kyc_document_id::TEXT,
                               'customer_id', doc.customer_id::TEXT,
                               'customer_code', customer.customer_code,
                               'billing_name', customer.billing_name,
                               'site_id', CASE WHEN doc.site_id IS NULL THEN NULL ELSE doc.site_id::TEXT END,
                               'site_name', site.site_name,
                               'document_type_id', doc.document_type_ref_data_id::TEXT,
                               'document_type_code', type_row.data_code,
                               'document_type_name', type_row.data_value,
                               'file_url', doc.file_url,
                               'mime_type', doc.mime_type,
                               'file_size_bytes', doc.file_size_bytes,
                               'status_code', status_row.data_code,
                               'status_name', status_row.data_value,
                               'rejection_comment', doc.rejection_comment,
                               'created_on', to_char(doc.created_on AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                           ) AS item
                      FROM solar_app.kyc_document_details AS doc
                      JOIN solar_app.ref_data AS type_row
                        ON type_row.ref_data_id = doc.document_type_ref_data_id
                      JOIN solar_app.ref_data AS status_row
                        ON status_row.ref_data_id = doc.verification_status_ref_data_id
                      JOIN solar_app.customer_details AS customer
                        ON customer.customer_id = doc.customer_id
                       AND customer.active_ind IS TRUE
                      LEFT JOIN solar_app.site_details AS site
                        ON site.site_id = doc.site_id
                     WHERE doc.active_ind IS TRUE
                       AND (
                            v_is_admin
                            OR doc.customer_id = v_customer_id
                       )
                       AND (
                            v_site_id IS NULL
                            OR doc.site_id IS NULL
                            OR doc.site_id = v_site_id
                       )
                       AND (
                            v_status_code IS NULL
                            OR status_row.data_code = v_status_code
                       )
                   ) AS listed;
        END IF;

        v_data := jsonb_build_object(
            'document_types', v_types,
            'documents', v_rows
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'KYC documents could not be loaded';
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
            'fn_get_kyc_document_details',
            v_actor,
            v_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'site_id', v_site_id,
                'status_code', v_status_code,
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

COMMENT ON FUNCTION solar_app.fn_get_kyc_document_details(JSONB) IS
    'Returns DOCUMENT_TYPES checklist rows and active KYC documents. Customers see owned rows only; ROLE_ADMIN may list across customers. Optional site_id and status_code filters.';
