-- Lists AMC contracts and free-service milestones for sites owned by the session customer.
-- A payload user id is not trusted. Visit fees are not calculated here.
-- free_visit_count and free_visit_radius_km come only from plan_snapshot_json.
-- A missing or unusable key is JSON null. The live plan columns are not used for those two fields.
-- Rows stay ordered by expiry date, then site name, for the existing Phase 1 screen.

CREATE OR REPLACE FUNCTION solar_app.fn_get_amc_contract_details(p_payload JSONB)
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
    v_message       TEXT := 'Service coverage loaded';
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
    v_contracts     JSONB;
    v_milestones    JSONB;
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
            v_message := 'This account cannot view service coverage';
            EXIT body;
        END IF;

        SELECT customer.customer_id
          INTO v_customer_id
          FROM solar_app.customer_details AS customer
         WHERE customer.user_id = v_user_id
           AND customer.active_ind IS TRUE;

        SELECT COALESCE(jsonb_agg(listed.item ORDER BY listed.expiry_on, listed.site_name), '[]'::jsonb)
          INTO v_contracts
          FROM (
                SELECT contract.expiry_on, site.site_name,
                       jsonb_build_object(
                           'amc_contract_id', contract.amc_contract_id::TEXT,
                           'site_id', site.site_id::TEXT,
                           'site_name', site.site_name,
                           'plan_name', plan.plan_name,
                           'contract_status', contract.contract_status,
                           'start_on', to_char(contract.start_on, 'YYYY-MM-DD'),
                           'expiry_on', to_char(contract.expiry_on, 'YYYY-MM-DD'),
                           'includes_cleaning', plan.includes_cleaning,
                           'includes_breakdown', plan.includes_breakdown,
                           'free_visit_count', CASE
                               WHEN jsonb_typeof(contract.plan_snapshot_json->'free_visit_count') = 'number'
                                AND (contract.plan_snapshot_json #>> '{free_visit_count}')::NUMERIC >= 0
                                AND (contract.plan_snapshot_json #>> '{free_visit_count}')::NUMERIC
                                    = trunc((contract.plan_snapshot_json #>> '{free_visit_count}')::NUMERIC)
                               THEN trunc((contract.plan_snapshot_json #>> '{free_visit_count}')::NUMERIC)
                               ELSE NULL
                           END,
                           'free_visit_radius_km', CASE
                               WHEN jsonb_typeof(contract.plan_snapshot_json->'free_visit_radius_km') = 'number'
                                AND (contract.plan_snapshot_json #>> '{free_visit_radius_km}')::NUMERIC >= 0
                               THEN round((contract.plan_snapshot_json #>> '{free_visit_radius_km}')::NUMERIC, 2)
                               ELSE NULL
                           END
                       ) AS item
                  FROM solar_app.amc_contract_details AS contract
                  JOIN solar_app.site_details AS site
                    ON site.site_id = contract.site_id
                   AND site.active_ind IS TRUE
                  JOIN solar_app.ref_amc_plans AS plan
                    ON plan.amc_plan_id = contract.amc_plan_id
                 WHERE site.customer_id = v_customer_id
                   AND contract.active_ind IS TRUE
               ) AS listed;

        SELECT COALESCE(jsonb_agg(listed.item ORDER BY listed.due_on, listed.milestone_no), '[]'::jsonb)
          INTO v_milestones
          FROM (
                SELECT milestone.due_on, milestone.milestone_no,
                       jsonb_build_object(
                           'service_milestone_id', milestone.service_milestone_id::TEXT,
                           'site_id', site.site_id::TEXT,
                           'site_name', site.site_name,
                           'milestone_no', milestone.milestone_no,
                           'due_on', to_char(milestone.due_on, 'YYYY-MM-DD'),
                           'claim_window_end_on', to_char(milestone.claim_window_end_on, 'YYYY-MM-DD'),
                           'status_code', status_row.data_code,
                           'status_name', status_row.data_value
                       ) AS item
                  FROM solar_app.service_milestone_details AS milestone
                  JOIN solar_app.site_details AS site
                    ON site.site_id = milestone.site_id
                   AND site.active_ind IS TRUE
                  LEFT JOIN solar_app.ref_data AS status_row
                    ON status_row.ref_data_id = milestone.status_ref_data_id
                 WHERE site.customer_id = v_customer_id
                   AND milestone.active_ind IS TRUE
               ) AS listed;

        v_data := jsonb_build_object('contracts', v_contracts, 'milestones', v_milestones);
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Service coverage could not be loaded';
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
            'fn_get_amc_contract_details',
            v_actor,
            v_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id
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

COMMENT ON FUNCTION solar_app.fn_get_amc_contract_details(JSONB) IS
    'Returns active AMC contracts and free-service milestones for sites owned by the session customer. It does not calculate a visit fee.';
