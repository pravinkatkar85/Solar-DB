-- Admin approve or reject of one KYC document.
-- Reject (ACTION_REQUIRED) requires a non-empty rejection_comment.
-- Only ROLE_ADMIN may update verification. Customer ownership of the document is required.
-- On a successful status change, enqueues NTF_KYC_STATUS for the customer user via
-- fn_create_notification_details. Notification failure rolls back the status update.
-- Do not install this file until separately approved.

CREATE OR REPLACE FUNCTION solar_app.fn_update_kyc_document_details(p_payload JSONB)
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
    v_message            TEXT := 'KYC document updated';
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
    v_role_code          VARCHAR(50);
    v_claimed            TEXT;
    v_action             TEXT;
    v_doc_text           TEXT;
    v_doc_id             BIGINT;
    v_customer_id        BIGINT;
    v_comment            TEXT;
    v_target_code        VARCHAR(50);
    v_target_status_id   BIGINT;
    v_updated            INTEGER := 0;
    v_prev_status_id     BIGINT;
    v_recipient_user_id  BIGINT;
    v_recipient_active   BOOLEAN;
    v_recipient_account  VARCHAR(50);
    v_doc_type_name      TEXT;
    v_ntf_response       JSONB;
    v_ntf_body           TEXT;
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
            v_message := 'This account cannot review KYC documents';
            EXIT body;
        END IF;
        IF v_role_code IS DISTINCT FROM 'ROLE_ADMIN' THEN
            v_status := 'ERROR';
            v_code := 403;
            v_message := 'Only an administrator can review KYC documents';
            EXIT body;
        END IF;

        v_action := upper(NULLIF(btrim(COALESCE(p_payload->>'action', '')), ''));
        IF v_action NOT IN ('APPROVE', 'REJECT') THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose approve or reject';
            EXIT body;
        END IF;

        v_doc_text := NULLIF(btrim(COALESCE(p_payload->>'kyc_document_id', '')), '');
        IF v_doc_text IS NULL OR v_doc_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose a KYC document';
            EXIT body;
        END IF;
        v_doc_id := v_doc_text::BIGINT;

        SELECT doc.customer_id,
               doc.verification_status_ref_data_id,
               COALESCE(NULLIF(btrim(type_row.data_value), ''), type_row.data_code, 'KYC document')
          INTO v_customer_id, v_prev_status_id, v_doc_type_name
          FROM solar_app.kyc_document_details AS doc
          LEFT JOIN solar_app.ref_data AS type_row
            ON type_row.ref_data_id = doc.document_type_ref_data_id
         WHERE doc.kyc_document_id = v_doc_id
           AND doc.active_ind IS TRUE;
        IF v_customer_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This KYC document was not found';
            EXIT body;
        END IF;

        IF v_action = 'REJECT' THEN
            v_comment := NULLIF(btrim(COALESCE(p_payload->>'rejection_comment', '')), '');
            IF v_comment IS NULL OR char_length(v_comment) > 500 THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Enter a rejection comment';
                EXIT body;
            END IF;
            v_target_code := 'ACTION_REQUIRED';
        ELSE
            v_comment := NULL;
            v_target_code := 'KYC_APPROVED';
        END IF;

        SELECT status_row.ref_data_id
          INTO v_target_status_id
          FROM solar_app.ref_data AS status_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = status_row.category_id
         WHERE category.category_code = 'DOCUMENT_VERIFICATION_STATUSES'
           AND status_row.data_code = v_target_code
           AND category.active_ind IS TRUE
           AND status_row.active_ind IS TRUE;
        IF v_target_status_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'KYC document could not be updated';
            v_log_error := v_target_code || ' is not configured';
            EXIT body;
        END IF;

        UPDATE solar_app.kyc_document_details AS doc
           SET verification_status_ref_data_id = v_target_status_id,
               verified_by_user_id = v_user_id,
               rejection_comment = v_comment,
               updated_by = v_actor,
               updated_on = clock_timestamp()
         WHERE doc.kyc_document_id = v_doc_id
           AND doc.active_ind IS TRUE;
        GET DIAGNOSTICS v_updated = ROW_COUNT;
        IF v_updated IS DISTINCT FROM 1 THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This KYC document was not found';
            EXIT body;
        END IF;

        IF v_action = 'REJECT' THEN
            v_message := 'KYC document marked action required';
        ELSE
            v_message := 'KYC document approved';
        END IF;

        -- Notify only when verification status actually changes (avoids duplicate
        -- notifications on successful retries of the same decision).
        IF v_prev_status_id IS DISTINCT FROM v_target_status_id THEN
            SELECT customer.user_id,
                   app_user.active_ind,
                   account_row.data_code
              INTO v_recipient_user_id, v_recipient_active, v_recipient_account
              FROM solar_app.customer_details AS customer
              JOIN solar_app.user_details AS app_user
                ON app_user.user_id = customer.user_id
              LEFT JOIN solar_app.ref_data AS account_row
                ON account_row.ref_data_id = app_user.account_status_ref_data_id
             WHERE customer.customer_id = v_customer_id
               AND customer.active_ind IS TRUE;

            -- BRD: inbox rows are not created for inactive/suspended users.
            IF v_recipient_user_id IS NOT NULL
               AND v_recipient_active IS TRUE
               AND v_recipient_account IS DISTINCT FROM 'ACCT_SUSPENDED' THEN
                IF v_action = 'REJECT' THEN
                    v_ntf_body := left(
                        'Your ' || v_doc_type_name || ' document needs action. ' || v_comment,
                        1000
                    );
                ELSE
                    v_ntf_body := left(
                        'Your ' || v_doc_type_name || ' document was approved.',
                        1000
                    );
                END IF;

                v_ntf_response := solar_app.fn_create_notification_details(
                    jsonb_strip_nulls(jsonb_build_object(
                        'api_endpoint', v_api_endpoint,
                        'logged_in_user_id', v_actor,
                        'recipient_user_id', v_recipient_user_id::TEXT,
                        'notification_type_code', 'NTF_KYC_STATUS',
                        'title', 'KYC reviewed',
                        'body', v_ntf_body,
                        'related_entity_type', 'KYC',
                        'related_entity_id', v_doc_id::TEXT,
                        'payload_json', jsonb_strip_nulls(jsonb_build_object(
                            'entity_type', 'KYC',
                            'entity_id', v_doc_id::TEXT,
                            'status_code', v_target_code,
                            'rejection_comment', v_comment
                        ))
                    ))
                );

                IF COALESCE(v_ntf_response->>'status', 'ERROR') IS DISTINCT FROM 'SUCCESS' THEN
                    RAISE EXCEPTION 'KYC notification enqueue failed: %',
                        COALESCE(v_ntf_response->>'message', 'unknown error')
                        USING ERRCODE = 'P0001';
                END IF;
            END IF;
        END IF;

        SELECT jsonb_build_object(
            'kyc_document_id', doc.kyc_document_id::TEXT,
            'status_code', status_row.data_code,
            'status_name', status_row.data_value,
            'rejection_comment', doc.rejection_comment,
            'verified_by_user_id', doc.verified_by_user_id::TEXT,
            'notification_id', CASE
                WHEN v_ntf_response IS NOT NULL
                 AND v_ntf_response->>'status' = 'SUCCESS'
                THEN v_ntf_response->'data'->>'notification_id'
                ELSE NULL
            END
        )
          INTO v_data
          FROM solar_app.kyc_document_details AS doc
          JOIN solar_app.ref_data AS status_row
            ON status_row.ref_data_id = doc.verification_status_ref_data_id
         WHERE doc.kyc_document_id = v_doc_id;
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'KYC document could not be updated';
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
            'fn_update_kyc_document_details',
            v_actor,
            v_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'kyc_document_id', v_doc_id,
                'action', v_action
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

COMMENT ON FUNCTION solar_app.fn_update_kyc_document_details(JSONB) IS
    'Admin approve or reject of one KYC document. Reject requires rejection_comment and sets ACTION_REQUIRED.';
