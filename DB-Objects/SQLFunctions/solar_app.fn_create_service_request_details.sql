-- Books one Open preventive service request.
-- When an approved office and an approved slab exist, stores that server quote.
-- A paid visit that qualifies for a free AMC credit also reserves that credit.
-- A free pricing slab does not reserve a credit.
-- When that approved office or slab configuration is absent, the request is booked
-- with no quote, no currency, no slab, and no credit reservation.
-- Client fee, credit count, contract id, and user id are not authoritative.
-- Do not install this file until migration 08 has been applied and this install is approved.
-- Cancellation, rescheduling, and visit completion are not handled here.

CREATE OR REPLACE FUNCTION solar_app.fn_create_service_request_details(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = pg_catalog, solar_app
AS $$
DECLARE
    v_started             TIMESTAMPTZ := clock_timestamp();
    v_api_endpoint        VARCHAR(255);
    v_actor               VARCHAR(50) := 'SYSTEM';
    v_status              VARCHAR(20) := 'SUCCESS';
    v_code                INTEGER := 200;
    v_message             TEXT := 'Service request booked';
    v_data                JSONB := NULL;
    v_response            JSONB;
    v_log_error           TEXT;
    v_sql_state           VARCHAR(10);
    v_token_hash          TEXT;
    v_session_count       INTEGER := 0;
    v_session_id          BIGINT;
    v_user_id             BIGINT;
    v_active              BOOLEAN;
    v_account_code        VARCHAR(50);
    v_claimed             TEXT;
    v_customer_id         BIGINT;
    v_site_text           TEXT;
    v_site_id             BIGINT;
    v_type_text           TEXT;
    v_type_id             BIGINT;
    v_slot_text           TEXT;
    v_slot_id             BIGINT;
    v_date_text           TEXT;
    v_preferred_on        DATE;
    v_milestone_text      TEXT;
    v_milestone_id        BIGINT;
    v_claim_end           DATE;
    v_milestone_request   BIGINT;
    v_milestone_status    VARCHAR(50);
    v_milestone_blocked   BOOLEAN := FALSE;
    v_status_id           BIGINT;
    v_fee                 JSONB;
    v_fee_data            JSONB;
    v_fee_code            INTEGER;
    v_quote_status        TEXT;
    v_entitlement_reason  TEXT;
    v_pricing_configured  BOOLEAN := FALSE;
    v_unquoted            BOOLEAN := FALSE;
    v_free_slab           BOOLEAN := FALSE;
    v_slab_charge         NUMERIC(12,2);
    v_quoted_amount       NUMERIC(12,2);
    v_currency            CHAR(3);
    v_slab_text           TEXT;
    v_slab_id             BIGINT;
    v_distance            NUMERIC(12,2);
    v_contract_id         BIGINT;
    v_linked_contract_id  BIGINT;
    v_snapshot            JSONB;
    v_count_value         JSONB;
    v_radius_value        JSONB;
    v_allowance           INTEGER;
    v_radius              NUMERIC(12,2);
    v_credit_seq          INTEGER;
    v_coverage            TEXT := 'PAID_SLAB';
    v_reserve             BOOLEAN := FALSE;
    v_saved               BOOLEAN := FALSE;
    v_attempt             INTEGER;
    v_request_id          BIGINT;
    v_request_no          VARCHAR(30);
    v_updated             INTEGER;
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
            v_message := 'This account cannot book a service request';
            EXIT body;
        END IF;

        SELECT customer.customer_id
          INTO v_customer_id
          FROM solar_app.customer_details AS customer
         WHERE customer.user_id = v_user_id
           AND customer.active_ind IS TRUE;
        IF v_customer_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'No installation is recorded for your account yet';
            EXIT body;
        END IF;

        v_site_text := NULLIF(btrim(COALESCE(p_payload->>'site_id', '')), '');
        IF v_site_text IS NULL OR v_site_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose an installation';
            EXIT body;
        END IF;

        SELECT site.site_id
          INTO v_site_id
          FROM solar_app.site_details AS site
         WHERE site.site_id = v_site_text::BIGINT
           AND site.customer_id = v_customer_id
           AND site.active_ind IS TRUE;
        IF v_site_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This installation was not found';
            EXIT body;
        END IF;

        v_type_text := NULLIF(btrim(COALESCE(p_payload->>'service_type_ref_data_id', '')), '');
        IF v_type_text IS NULL OR v_type_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose a service type';
            EXIT body;
        END IF;
        SELECT type_row.ref_data_id
          INTO v_type_id
          FROM solar_app.ref_data AS type_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = type_row.category_id
         WHERE type_row.ref_data_id = v_type_text::BIGINT
           AND category.category_code = 'SERVICE_TYPES'
           AND category.active_ind IS TRUE
           AND type_row.active_ind IS TRUE;
        IF v_type_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose a service type';
            EXIT body;
        END IF;

        v_slot_text := NULLIF(btrim(COALESCE(p_payload->>'slot_window_ref_data_id', '')), '');
        IF v_slot_text IS NULL OR v_slot_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose a time window';
            EXIT body;
        END IF;
        SELECT slot_row.ref_data_id
          INTO v_slot_id
          FROM solar_app.ref_data AS slot_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = slot_row.category_id
         WHERE slot_row.ref_data_id = v_slot_text::BIGINT
           AND category.category_code = 'SERVICE_SLOT_WINDOWS'
           AND category.active_ind IS TRUE
           AND slot_row.active_ind IS TRUE;
        IF v_slot_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose a time window';
            EXIT body;
        END IF;

        v_date_text := NULLIF(btrim(COALESCE(p_payload->>'preferred_on', '')), '');
        IF v_date_text IS NULL OR v_date_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose a preferred date';
            EXIT body;
        END IF;
        BEGIN
            v_preferred_on := v_date_text::DATE;
        EXCEPTION
            WHEN OTHERS THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Choose a preferred date';
        END;
        IF v_status <> 'SUCCESS' THEN
            EXIT body;
        END IF;

        v_milestone_text := NULLIF(btrim(COALESCE(p_payload->>'milestone_id', '')), '');
        IF v_milestone_text IS NOT NULL THEN
            IF v_milestone_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'This service visit cannot be claimed';
                EXIT body;
            END IF;
            SELECT milestone.service_milestone_id,
                   milestone.claim_window_end_on,
                   milestone.service_request_id,
                   status_row.data_code
              INTO v_milestone_id, v_claim_end, v_milestone_request, v_milestone_status
              FROM solar_app.service_milestone_details AS milestone
              JOIN solar_app.ref_data AS status_row
                ON status_row.ref_data_id = milestone.status_ref_data_id
              JOIN solar_app.ref_data_categories AS category
                ON category.category_id = status_row.category_id
             WHERE milestone.service_milestone_id = v_milestone_text::BIGINT
               AND milestone.site_id = v_site_id
               AND milestone.active_ind IS TRUE
               AND category.category_code = 'MILESTONE_STATUSES'
               AND category.active_ind IS TRUE
               AND status_row.active_ind IS TRUE;
            IF v_milestone_id IS NULL
               OR v_milestone_status IS DISTINCT FROM 'MS_DUE'
               OR v_milestone_request IS NOT NULL
               OR v_claim_end IS NULL
               OR v_preferred_on > v_claim_end THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'This service visit cannot be claimed';
                EXIT body;
            END IF;
        END IF;

        SELECT status_row.ref_data_id
          INTO v_status_id
          FROM solar_app.ref_data AS status_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = status_row.category_id
         WHERE category.category_code = 'SERVICE_REQUEST_STATUSES'
           AND status_row.data_code = 'SR_OPEN'
           AND category.active_ind IS TRUE
           AND status_row.active_ind IS TRUE;
        IF v_status_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Service request could not be booked';
            v_log_error := 'SR_OPEN is not configured';
            EXIT body;
        END IF;

        v_fee := solar_app.fn_get_site_visit_charge(jsonb_build_object(
            'api_endpoint', v_api_endpoint,
            'jwt_token_hash', v_token_hash,
            'site_id', v_site_id::TEXT,
            'visit_on', to_char(v_preferred_on, 'YYYY-MM-DD')
        ));
        v_fee_data := v_fee->'data';
        v_fee_code := NULL;
        IF v_fee IS NULL OR jsonb_typeof(v_fee) <> 'object' THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Service request could not be booked';
            EXIT body;
        END IF;
        IF COALESCE(v_fee->>'code', '') ~ '^[0-9]+$' THEN
            v_fee_code := (v_fee->>'code')::INTEGER;
        END IF;
        IF v_fee->>'status' IS DISTINCT FROM 'SUCCESS' OR v_fee_code IS DISTINCT FROM 200 THEN
            v_status := 'ERROR';
            v_code := CASE
                WHEN v_fee_code IN (400, 401, 403, 404, 500) THEN v_fee_code
                ELSE 500
            END;
            v_message := COALESCE(NULLIF(btrim(v_fee->>'message'), ''), 'Service request could not be booked');
            EXIT body;
        END IF;

        v_quote_status := v_fee_data->>'quote_status';
        v_entitlement_reason := v_fee_data #>> '{free_entitlement,reason}';
        SELECT (
                   SELECT COUNT(*)
                     FROM solar_app.ref_office_locations AS office
                    WHERE office.is_default IS TRUE
                      AND office.active_ind IS TRUE
                      AND left(office.office_code, 4) IS DISTINCT FROM 'DEV_'
               ) = 1
           AND EXISTS (
                   SELECT 1
                     FROM solar_app.ref_visit_charge_slabs AS slab
                    WHERE slab.active_ind IS TRUE
                      AND slab.created_by IS DISTINCT FROM 'DEV_SEED'
               )
          INTO v_pricing_configured;

        -- Store a fee only from an available quote whose credit hold was checked.
        -- Absent approved office or slab configuration keeps the previous unpriced booking.
        IF v_quote_status = 'AVAILABLE'
           AND v_entitlement_reason IS DISTINCT FROM 'CREDIT_HOLD_UNAVAILABLE' THEN
            v_unquoted := FALSE;
        ELSIF v_pricing_configured IS TRUE OR v_quote_status = 'AVAILABLE' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Visit fee is not available';
            v_data := v_fee_data;
            EXIT body;
        ELSE
            v_unquoted := TRUE;
        END IF;

        IF NOT v_unquoted AND (
           jsonb_typeof(v_fee_data->'is_free_slab') IS DISTINCT FROM 'boolean'
           OR v_fee_data->>'charge_amount' IS NULL
           OR v_fee_data->>'currency_code' IS NULL
           OR COALESCE(v_fee_data->>'visit_charge_slab_id', '') !~ '^[0-9]{1,18}$'
           OR v_fee_data->>'distance_km' IS NULL
        ) THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Visit fee is not available';
            v_data := v_fee_data;
            EXIT body;
        END IF;

        IF NOT v_unquoted THEN
        BEGIN
            v_free_slab := (v_fee_data->'is_free_slab') = 'true'::JSONB;
            v_slab_charge := (v_fee_data->>'charge_amount')::NUMERIC(12,2);
            v_distance := (v_fee_data->>'distance_km')::NUMERIC(12,2);
            v_currency := btrim(v_fee_data->>'currency_code');
            v_slab_text := v_fee_data->>'visit_charge_slab_id';
            v_slab_id := v_slab_text::BIGINT;
        EXCEPTION
            WHEN OTHERS THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Visit fee is not available';
                v_data := v_fee_data;
        END;
        IF v_status <> 'SUCCESS' OR v_slab_charge IS NULL OR v_slab_charge < 0 OR v_distance IS NULL THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Visit fee is not available';
            v_data := v_fee_data;
            EXIT body;
        END IF;
        END IF;

        FOR v_attempt IN 1..3 LOOP
            BEGIN
                v_reserve := FALSE;
                v_credit_seq := NULL;
                v_contract_id := NULL;
                v_linked_contract_id := NULL;
                v_coverage := 'PAID_SLAB';
                v_quoted_amount := v_slab_charge;

                IF v_unquoted THEN
                    v_coverage := NULL;
                    v_quoted_amount := NULL;
                    v_currency := NULL;
                    v_slab_id := NULL;
                    v_slab_charge := NULL;
                ELSIF v_free_slab THEN
                    v_coverage := 'FREE_SLAB';
                ELSE
                    SELECT contract.amc_contract_id, contract.plan_snapshot_json
                      INTO v_contract_id, v_snapshot
                      FROM solar_app.amc_contract_details AS contract
                     WHERE contract.site_id = v_site_id
                       AND contract.active_ind IS TRUE
                       AND contract.contract_status = 'ACTIVE'
                       AND contract.start_on <= v_preferred_on
                       AND contract.expiry_on >= v_preferred_on
                     ORDER BY contract.start_on DESC, contract.amc_contract_id DESC
                     LIMIT 1
                       FOR UPDATE;

                    IF v_contract_id IS NOT NULL AND jsonb_typeof(v_snapshot) = 'object' THEN
                        v_count_value := v_snapshot->'free_visit_count';
                        v_radius_value := v_snapshot->'free_visit_radius_km';
                        IF jsonb_typeof(v_count_value) = 'number' AND jsonb_typeof(v_radius_value) = 'number' THEN
                            IF (v_count_value #>> '{}')::NUMERIC >= 0
                               AND (v_count_value #>> '{}')::NUMERIC = trunc((v_count_value #>> '{}')::NUMERIC)
                               AND (v_radius_value #>> '{}')::NUMERIC >= 0 THEN
                                v_allowance := (v_count_value #>> '{}')::INTEGER;
                                v_radius := round((v_radius_value #>> '{}')::NUMERIC, 2);
                                IF v_allowance >= 1 AND v_distance <= v_radius THEN
                                    -- Lowest unused sequence. A released row does not block that number.
                                    -- The locked contract row serializes allocation. A row count is not incremented.
                                    SELECT free_seq.seq
                                      INTO v_credit_seq
                                      FROM generate_series(1, v_allowance) AS free_seq(seq)
                                     WHERE NOT EXISTS (
                                           SELECT 1
                                             FROM solar_app.amc_credit_reservation_details AS held
                                            WHERE held.amc_contract_id = v_contract_id
                                              AND held.credit_seq = free_seq.seq
                                              AND held.reservation_status IN ('RESERVED', 'CONSUMED')
                                              AND held.active_ind IS TRUE
                                           )
                                     ORDER BY free_seq.seq
                                     LIMIT 1;
                                    IF v_credit_seq IS NOT NULL THEN
                                        v_reserve := TRUE;
                                        v_coverage := 'AMC_CREDIT';
                                        v_quoted_amount := 0;
                                        v_linked_contract_id := v_contract_id;
                                    END IF;
                                END IF;
                            END IF;
                        END IF;
                    END IF;
                END IF;

                IF v_milestone_id IS NOT NULL THEN
                    SELECT milestone.claim_window_end_on,
                           milestone.service_request_id,
                           status_row.data_code
                      INTO v_claim_end, v_milestone_request, v_milestone_status
                      FROM solar_app.service_milestone_details AS milestone
                      JOIN solar_app.ref_data AS status_row
                        ON status_row.ref_data_id = milestone.status_ref_data_id
                     WHERE milestone.service_milestone_id = v_milestone_id
                       AND milestone.site_id = v_site_id
                       AND milestone.active_ind IS TRUE
                       FOR UPDATE;
                    IF v_milestone_status IS DISTINCT FROM 'MS_DUE'
                       OR v_milestone_request IS NOT NULL
                       OR v_claim_end IS NULL
                       OR v_preferred_on > v_claim_end THEN
                        RAISE EXCEPTION 'milestone_unavailable' USING ERRCODE = 'P0001';
                    END IF;
                END IF;

                v_request_id := nextval(pg_get_serial_sequence(
                    'solar_app.service_request_details',
                    'service_request_id'
                ));
                v_request_no := 'SR-' || lpad(v_request_id::TEXT, 8, '0');

                INSERT INTO solar_app.service_request_details (
                    service_request_id,
                    service_request_no,
                    site_id,
                    customer_id,
                    service_type_ref_data_id,
                    slot_window_ref_data_id,
                    status_ref_data_id,
                    preferred_on,
                    milestone_id,
                    amc_contract_id,
                    quoted_charge_amount,
                    quoted_currency_code,
                    visit_charge_slab_id,
                    fee_quote_snapshot_json,
                    quote_confirmed_on,
                    created_by,
                    updated_by
                ) OVERRIDING SYSTEM VALUE VALUES (
                    v_request_id,
                    v_request_no,
                    v_site_id,
                    v_customer_id,
                    v_type_id,
                    v_slot_id,
                    v_status_id,
                    v_preferred_on,
                    v_milestone_id,
                    v_linked_contract_id,
                    CASE WHEN v_unquoted THEN NULL ELSE v_quoted_amount END,
                    CASE WHEN v_unquoted THEN NULL ELSE v_currency END,
                    CASE WHEN v_unquoted THEN NULL ELSE v_slab_id END,
                    CASE
                        WHEN v_unquoted THEN '{}'::JSONB
                        ELSE jsonb_build_object(
                            'coverage', v_coverage,
                            'credit_seq', v_credit_seq,
                            'slab_charge_amount', v_slab_charge,
                            'fee', v_fee_data
                        )
                    END,
                    CASE WHEN v_unquoted THEN NULL ELSE clock_timestamp() END,
                    v_actor,
                    v_actor
                );

                IF v_reserve THEN
                    INSERT INTO solar_app.amc_credit_reservation_details (
                        service_request_id,
                        amc_contract_id,
                        credit_seq,
                        reservation_status,
                        created_by,
                        updated_by
                    ) VALUES (
                        v_request_id,
                        v_linked_contract_id,
                        v_credit_seq,
                        'RESERVED',
                        v_actor,
                        v_actor
                    );
                END IF;

                IF v_milestone_id IS NOT NULL THEN
                    UPDATE solar_app.service_milestone_details
                       SET service_request_id = v_request_id,
                           updated_by = v_actor,
                           updated_on = clock_timestamp()
                     WHERE service_milestone_id = v_milestone_id
                       AND site_id = v_site_id
                       AND service_request_id IS NULL
                       AND active_ind IS TRUE;
                    GET DIAGNOSTICS v_updated = ROW_COUNT;
                    IF v_updated IS DISTINCT FROM 1 THEN
                        RAISE EXCEPTION 'milestone_unavailable' USING ERRCODE = 'P0001';
                    END IF;
                END IF;

                v_saved := TRUE;
                EXIT;
            EXCEPTION
                WHEN unique_violation THEN
                    v_saved := FALSE;
                WHEN SQLSTATE 'P0001' THEN
                    v_milestone_blocked := TRUE;
                    EXIT;
            END;
        END LOOP;

        IF v_milestone_blocked THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'This service visit cannot be claimed';
            v_data := NULL;
        ELSIF NOT v_saved THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Service request could not be booked';
            v_data := NULL;
        ELSE
            v_data := jsonb_build_object(
                'service_request_id', v_request_id::TEXT,
                'service_request_no', v_request_no,
                'site_id', v_site_id::TEXT,
                'quoted_charge_amount', v_quoted_amount,
                'quoted_currency_code', NULLIF(btrim(v_currency), ''),
                'visit_charge_slab_id', CASE WHEN v_slab_id IS NULL THEN NULL ELSE v_slab_id::TEXT END,
                'coverage', v_coverage,
                'amc_contract_id', CASE WHEN v_linked_contract_id IS NULL THEN NULL ELSE v_linked_contract_id::TEXT END,
                'credit_seq', v_credit_seq,
                'quote_confirmed', NOT v_unquoted
            );
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Service request could not be booked';
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
            'fn_create_service_request_details',
            v_actor,
            v_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'site_id', v_site_id,
                'service_type_ref_data_id', v_type_id,
                'slot_window_ref_data_id', v_slot_id,
                'preferred_on', v_date_text,
                'coverage', CASE WHEN v_saved THEN v_coverage ELSE NULL END
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

COMMENT ON FUNCTION solar_app.fn_create_service_request_details(JSONB) IS
    'Books an Open preventive service request, stores the server-calculated quote, and reserves one AMC credit when the paid visit qualifies. A free pricing slab does not reserve a credit.';
