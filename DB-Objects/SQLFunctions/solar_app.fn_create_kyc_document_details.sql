-- Creates one KYC document upload for the session customer at status KYC_PENDING.
-- File size must be > 0 and at most the BRD 2 MB ceiling (2097152), optionally
-- tightened by an active DEV_KYC_UPLOAD_MAX_BYTES business parameter.
-- Client verification status, verifier, and rejection comment are ignored.
-- Notification enqueue is not called because fn_create_notification_details is not implemented.
-- Do not install this file until separately approved.

CREATE OR REPLACE FUNCTION solar_app.fn_create_kyc_document_details(p_payload JSONB)
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
    v_message            TEXT := 'KYC document uploaded';
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
    v_type_text          TEXT;
    v_type_id            BIGINT;
    v_file_url           TEXT;
    v_mime               TEXT;
    v_size_text          TEXT;
    v_size               INTEGER;
    v_max_bytes          INTEGER := 2097152;
    v_param_bytes        NUMERIC;
    v_status_id          BIGINT;
    v_doc_id             BIGINT;
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
            v_message := 'This account cannot upload KYC documents';
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
            v_message := 'This account cannot upload KYC documents';
            EXIT body;
        END IF;

        v_site_text := NULLIF(btrim(COALESCE(p_payload->>'site_id', '')), '');
        IF v_site_text IS NOT NULL THEN
            IF v_site_text !~ '^[0-9]{1,18}$' THEN
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
        END IF;

        v_type_text := NULLIF(btrim(COALESCE(p_payload->>'document_type_ref_data_id', '')), '');
        IF v_type_text IS NULL OR v_type_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose a document type';
            EXIT body;
        END IF;
        v_type_id := v_type_text::BIGINT;
        IF NOT EXISTS (
            SELECT 1
              FROM solar_app.ref_data AS type_row
              JOIN solar_app.ref_data_categories AS category
                ON category.category_id = type_row.category_id
             WHERE type_row.ref_data_id = v_type_id
               AND type_row.active_ind IS TRUE
               AND category.category_code = 'DOCUMENT_TYPES'
               AND category.active_ind IS TRUE
        ) THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose a document type';
            EXIT body;
        END IF;

        v_file_url := NULLIF(btrim(COALESCE(p_payload->>'file_url', '')), '');
        IF v_file_url IS NULL OR char_length(v_file_url) > 500 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Upload a document file';
            EXIT body;
        END IF;

        v_mime := NULLIF(btrim(COALESCE(p_payload->>'mime_type', '')), '');
        IF v_mime IS NOT NULL AND char_length(v_mime) > 100 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Unsupported document format';
            EXIT body;
        END IF;

        SELECT numeric_value
          INTO v_param_bytes
          FROM solar_app.ref_business_parameters AS param
         WHERE param.parameter_code = 'DEV_KYC_UPLOAD_MAX_BYTES'
           AND param.active_ind IS TRUE
           AND param.value_type = 'NUMERIC'
           AND param.numeric_value IS NOT NULL
           AND param.effective_from <= CURRENT_DATE
           AND (param.effective_to IS NULL OR param.effective_to >= CURRENT_DATE)
         ORDER BY param.effective_from DESC
         LIMIT 1;
        IF v_param_bytes IS NOT NULL
           AND v_param_bytes > 0
           AND v_param_bytes < v_max_bytes THEN
            v_max_bytes := trunc(v_param_bytes)::INTEGER;
        END IF;

        v_size_text := NULLIF(btrim(COALESCE(p_payload->>'file_size_bytes', '')), '');
        IF v_size_text IS NULL OR v_size_text !~ '^[0-9]{1,9}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Document size is required';
            EXIT body;
        END IF;
        v_size := v_size_text::INTEGER;
        IF v_size <= 0 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Document size is required';
            EXIT body;
        END IF;
        IF v_size > v_max_bytes THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Document must be 2 MB or smaller';
            EXIT body;
        END IF;

        SELECT status_row.ref_data_id
          INTO v_status_id
          FROM solar_app.ref_data AS status_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = status_row.category_id
         WHERE category.category_code = 'DOCUMENT_VERIFICATION_STATUSES'
           AND status_row.data_code = 'KYC_PENDING'
           AND category.active_ind IS TRUE
           AND status_row.active_ind IS TRUE;
        IF v_status_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'KYC document could not be uploaded';
            v_log_error := 'KYC_PENDING is not configured';
            EXIT body;
        END IF;

        INSERT INTO solar_app.kyc_document_details (
            customer_id,
            site_id,
            document_type_ref_data_id,
            file_url,
            mime_type,
            file_size_bytes,
            verification_status_ref_data_id,
            verified_by_user_id,
            rejection_comment,
            created_by,
            updated_by
        ) VALUES (
            v_customer_id,
            v_site_id,
            v_type_id,
            v_file_url,
            v_mime,
            v_size,
            v_status_id,
            NULL,
            NULL,
            v_actor,
            v_actor
        )
        RETURNING kyc_document_id INTO v_doc_id;

        SELECT jsonb_build_object(
            'kyc_document_id', doc.kyc_document_id::TEXT,
            'site_id', CASE WHEN doc.site_id IS NULL THEN NULL ELSE doc.site_id::TEXT END,
            'document_type_id', doc.document_type_ref_data_id::TEXT,
            'document_type_code', type_row.data_code,
            'document_type_name', type_row.data_value,
            'file_url', doc.file_url,
            'mime_type', doc.mime_type,
            'file_size_bytes', doc.file_size_bytes,
            'status_code', status_row.data_code,
            'status_name', status_row.data_value
        )
          INTO v_data
          FROM solar_app.kyc_document_details AS doc
          JOIN solar_app.ref_data AS type_row
            ON type_row.ref_data_id = doc.document_type_ref_data_id
          JOIN solar_app.ref_data AS status_row
            ON status_row.ref_data_id = doc.verification_status_ref_data_id
         WHERE doc.kyc_document_id = v_doc_id;
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'KYC document could not be uploaded';
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
            'fn_create_kyc_document_details',
            v_actor,
            v_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'site_id', v_site_id,
                'document_type_ref_data_id', v_type_id,
                'file_size_bytes', v_size,
                'mime_type', v_mime
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

COMMENT ON FUNCTION solar_app.fn_create_kyc_document_details(JSONB) IS
    'Uploads one KYC document for the session customer at Pending Verification. Client status and reject fields are ignored.';
