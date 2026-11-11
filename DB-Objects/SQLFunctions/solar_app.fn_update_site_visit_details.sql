-- Completes the one site visit for a confirmed service booking.
-- When no visit exists, generates visit_no as SV- plus the identity padded to 8 digits.
-- fn_create_site_visit_details is not authored. This function inserts that visit.
-- Copies the stored quote. It does not recalculate the fee.
-- Consumes the RESERVED credit row for that request when the stored quote is an AMC credit.
-- A free pricing slab does not consume a credit. A completed visit is not completed again.
-- Do not install this file until migration 08 has been applied and this install is approved.

CREATE OR REPLACE FUNCTION solar_app.fn_update_site_visit_details(p_payload JSONB)
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
    v_message            TEXT := 'Site visit completed';
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
    v_request_text       TEXT;
    v_request_id         BIGINT;
    v_request_no         VARCHAR(30);
    v_site_id            BIGINT;
    v_request_status     VARCHAR(50);
    v_preferred_on       DATE;
    v_slot_id            BIGINT;
    v_milestone_id       BIGINT;
    v_request_contract   BIGINT;
    v_quoted_amount      NUMERIC(12,2);
    v_quoted_currency    CHAR(3);
    v_quoted_slab_id     BIGINT;
    v_quote_confirmed_on TIMESTAMPTZ;
    v_quote_snapshot     JSONB;
    v_coverage           TEXT;
    v_free_flag          BOOLEAN;
    v_snapshot_seq_text  TEXT;
    v_reservation_id     BIGINT;
    v_reservation_seq    INTEGER;
    v_reservation_status VARCHAR(20);
    v_consume            BOOLEAN := FALSE;
    v_chargeable         BOOLEAN := TRUE;
    v_visit_id           BIGINT;
    v_visit_no           VARCHAR(30);
    v_visit_status       VARCHAR(50);
    v_visit_active       BOOLEAN;
    v_completed_on       TIMESTAMPTZ;
    v_purpose_id         BIGINT;
    v_completed_status_id BIGINT;
    v_request_completed_id BIGINT;
    v_milestone_status   VARCHAR(50);
    v_milestone_completed_id BIGINT;
    v_office_text        TEXT;
    v_office_id          BIGINT;
    v_distance_text      TEXT;
    v_distance           NUMERIC(8,2);
    v_duplicate          BOOLEAN := FALSE;
    v_updated            INTEGER;
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
            v_message := 'This account cannot complete a site visit';
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
            v_message := 'This service request was not found';
            EXIT body;
        END IF;

        v_request_text := NULLIF(btrim(COALESCE(p_payload->>'service_request_id', '')), '');
        IF v_request_text IS NULL OR v_request_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose a service request';
            EXIT body;
        END IF;

        SELECT request.service_request_id,
               request.service_request_no,
               request.site_id,
               request.preferred_on,
               request.slot_window_ref_data_id,
               request.milestone_id,
               request.amc_contract_id,
               request.quoted_charge_amount,
               request.quoted_currency_code,
               request.visit_charge_slab_id,
               request.quote_confirmed_on,
               request.fee_quote_snapshot_json,
               status_row.data_code
          INTO v_request_id, v_request_no, v_site_id, v_preferred_on, v_slot_id,
               v_milestone_id, v_request_contract, v_quoted_amount, v_quoted_currency,
               v_quoted_slab_id, v_quote_confirmed_on, v_quote_snapshot, v_request_status
          FROM solar_app.service_request_details AS request
          JOIN solar_app.ref_data AS status_row
            ON status_row.ref_data_id = request.status_ref_data_id
         WHERE request.service_request_id = v_request_text::BIGINT
           AND request.customer_id = v_customer_id
           AND request.active_ind IS TRUE
           FOR UPDATE;
        IF v_request_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This service request was not found';
            EXIT body;
        END IF;

        IF v_request_status NOT IN ('SR_OPEN', 'SR_ASSIGNED', 'SR_IN_PROGRESS') THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'This service request can no longer be changed';
            EXIT body;
        END IF;

        IF v_quote_confirmed_on IS NULL
           OR v_quoted_amount IS NULL
           OR v_quoted_currency IS NULL
           OR v_quoted_slab_id IS NULL
           OR v_preferred_on IS NULL
           OR jsonb_typeof(v_quote_snapshot) IS DISTINCT FROM 'object' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'This visit cannot be completed';
            EXIT body;
        END IF;

        v_coverage := v_quote_snapshot->>'coverage';
        IF v_coverage NOT IN ('FREE_SLAB', 'AMC_CREDIT', 'PAID_SLAB')
           OR jsonb_typeof(v_quote_snapshot #> '{fee,is_free_slab}') IS DISTINCT FROM 'boolean' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'This visit cannot be completed';
            EXIT body;
        END IF;
        v_free_flag := (v_quote_snapshot #> '{fee,is_free_slab}') = 'true'::JSONB;
        IF v_free_flag IS DISTINCT FROM (v_coverage = 'FREE_SLAB') THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'This visit cannot be completed';
            EXIT body;
        END IF;

        SELECT held.amc_credit_reservation_id, held.credit_seq, held.reservation_status
          INTO v_reservation_id, v_reservation_seq, v_reservation_status
          FROM solar_app.amc_credit_reservation_details AS held
         WHERE held.service_request_id = v_request_id
           AND held.active_ind IS TRUE
           AND held.reservation_status IN ('RESERVED', 'CONSUMED')
           FOR UPDATE;

        v_snapshot_seq_text := v_quote_snapshot->>'credit_seq';
        IF v_coverage = 'FREE_SLAB' OR v_coverage = 'PAID_SLAB' THEN
            IF v_reservation_id IS NOT NULL THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'This visit cannot be completed';
                EXIT body;
            END IF;
            v_consume := FALSE;
            v_chargeable := v_coverage = 'PAID_SLAB';
        ELSE
            IF v_reservation_status IS DISTINCT FROM 'RESERVED'
               OR v_snapshot_seq_text IS NULL
               OR v_snapshot_seq_text !~ '^[0-9]+$'
               OR v_snapshot_seq_text::INTEGER IS DISTINCT FROM v_reservation_seq
               OR v_request_contract IS NULL THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'This visit cannot be completed';
                EXIT body;
            END IF;
            v_consume := TRUE;
            v_chargeable := FALSE;
        END IF;

        IF v_milestone_id IS NOT NULL THEN
            SELECT status_row.data_code
              INTO v_milestone_status
              FROM solar_app.service_milestone_details AS milestone
              JOIN solar_app.ref_data AS status_row
                ON status_row.ref_data_id = milestone.status_ref_data_id
             WHERE milestone.service_milestone_id = v_milestone_id
               AND milestone.site_id = v_site_id
               AND milestone.active_ind IS TRUE
               FOR UPDATE;
            IF v_milestone_status IS NULL THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'This visit cannot be completed';
                EXIT body;
            END IF;
        END IF;

        -- Lock only site_visit_details. FOR UPDATE on the LEFT JOIN side of
        -- ref_data raises SQLSTATE 0A000 (nullable side of an outer join).
        SELECT visit.site_visit_id, visit.visit_no, visit.active_ind, visit.completed_on, visit_status.data_code
          INTO v_visit_id, v_visit_no, v_visit_active, v_completed_on, v_visit_status
          FROM solar_app.site_visit_details AS visit
          LEFT JOIN solar_app.ref_data AS visit_status
            ON visit_status.ref_data_id = visit.visit_status_ref_data_id
         WHERE visit.service_request_id = v_request_id
           FOR UPDATE OF visit;
        IF v_visit_id IS NOT NULL AND (v_completed_on IS NOT NULL OR v_visit_status = 'VISIT_COMPLETED') THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'This visit is already completed';
            EXIT body;
        END IF;
        IF v_visit_id IS NOT NULL AND (
            v_visit_active IS NOT TRUE
            OR v_visit_status IN ('VISIT_CANCELLED', 'VISIT_NO_SHOW')
        ) THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'This visit cannot be completed';
            EXIT body;
        END IF;

        SELECT status_row.ref_data_id
          INTO v_completed_status_id
          FROM solar_app.ref_data AS status_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = status_row.category_id
         WHERE category.category_code = 'SITE_VISIT_STATUSES'
           AND status_row.data_code = 'VISIT_COMPLETED'
           AND category.active_ind IS TRUE
           AND status_row.active_ind IS TRUE;
        SELECT status_row.ref_data_id
          INTO v_request_completed_id
          FROM solar_app.ref_data AS status_row
          JOIN solar_app.ref_data_categories AS category
            ON category.category_id = status_row.category_id
         WHERE category.category_code = 'SERVICE_REQUEST_STATUSES'
           AND status_row.data_code = 'SR_COMPLETED'
           AND category.active_ind IS TRUE
           AND status_row.active_ind IS TRUE;
        IF v_completed_status_id IS NULL OR v_request_completed_id IS NULL THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Site visit could not be completed';
            v_log_error := 'Completion status is not configured';
            EXIT body;
        END IF;

        IF v_visit_id IS NULL THEN
            SELECT purpose.ref_data_id
              INTO v_purpose_id
              FROM solar_app.ref_data AS purpose
              JOIN solar_app.ref_data_categories AS category
                ON category.category_id = purpose.category_id
             WHERE category.category_code = 'SITE_VISIT_PURPOSES'
               AND purpose.data_code = 'VISIT_SERVICE'
               AND category.active_ind IS TRUE
               AND purpose.active_ind IS TRUE;
            v_office_text := v_quote_snapshot #>> '{fee,office_location_id}';
            IF v_purpose_id IS NULL OR v_office_text IS NULL OR v_office_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'This visit cannot be completed';
                EXIT body;
            END IF;
            v_office_id := v_office_text::BIGINT;
        END IF;

        v_distance_text := v_quote_snapshot #>> '{fee,distance_km}';
        IF v_distance_text IS NOT NULL AND v_distance_text ~ '^[0-9]+(\.[0-9]+)?$' THEN
            v_distance := v_distance_text::NUMERIC(8,2);
        END IF;

        BEGIN
            IF v_visit_id IS NULL THEN
                v_visit_id := nextval(pg_get_serial_sequence('solar_app.site_visit_details', 'site_visit_id'));
                v_visit_no := 'SV-' || lpad(v_visit_id::TEXT, 8, '0');
                INSERT INTO solar_app.site_visit_details (
                    site_visit_id,
                    visit_no,
                    visit_purpose_ref_data_id,
                    customer_id,
                    site_id,
                    service_request_id,
                    service_milestone_id,
                    amc_contract_id,
                    office_location_id,
                    slot_window_ref_data_id,
                    visit_status_ref_data_id,
                    scheduled_on,
                    completed_on,
                    distance_from_office_km,
                    visit_charge_slab_id,
                    is_chargeable_ind,
                    is_free_entitlement_ind,
                    charge_amount,
                    currency_code,
                    charge_rule_snapshot_json,
                    created_by,
                    updated_by
                ) OVERRIDING SYSTEM VALUE VALUES (
                    v_visit_id,
                    v_visit_no,
                    v_purpose_id,
                    v_customer_id,
                    v_site_id,
                    v_request_id,
                    v_milestone_id,
                    CASE WHEN v_consume THEN v_request_contract ELSE NULL END,
                    v_office_id,
                    v_slot_id,
                    v_completed_status_id,
                    v_preferred_on,
                    clock_timestamp(),
                    v_distance,
                    v_quoted_slab_id,
                    v_chargeable,
                    v_consume,
                    v_quoted_amount,
                    v_quoted_currency,
                    v_quote_snapshot,
                    v_actor,
                    v_actor
                );
            ELSE
                UPDATE solar_app.site_visit_details
                   SET service_milestone_id = v_milestone_id,
                       amc_contract_id = CASE WHEN v_consume THEN v_request_contract ELSE NULL END,
                       visit_status_ref_data_id = v_completed_status_id,
                       scheduled_on = v_preferred_on,
                       completed_on = clock_timestamp(),
                       distance_from_office_km = v_distance,
                       visit_charge_slab_id = v_quoted_slab_id,
                       is_chargeable_ind = v_chargeable,
                       is_free_entitlement_ind = v_consume,
                       charge_amount = v_quoted_amount,
                       currency_code = v_quoted_currency,
                       charge_rule_snapshot_json = v_quote_snapshot,
                       updated_by = v_actor,
                       updated_on = clock_timestamp()
                 WHERE site_visit_id = v_visit_id
                   AND service_request_id = v_request_id
                   AND completed_on IS NULL;
                GET DIAGNOSTICS v_updated = ROW_COUNT;
                IF v_updated IS DISTINCT FROM 1 THEN
                    RAISE EXCEPTION 'visit_not_open' USING ERRCODE = 'P0001';
                END IF;
            END IF;

            IF v_consume THEN
                UPDATE solar_app.amc_credit_reservation_details
                   SET reservation_status = 'CONSUMED',
                       updated_by = v_actor,
                       updated_on = clock_timestamp()
                 WHERE amc_credit_reservation_id = v_reservation_id
                   AND service_request_id = v_request_id
                   AND reservation_status = 'RESERVED'
                   AND active_ind IS TRUE;
                GET DIAGNOSTICS v_updated = ROW_COUNT;
                IF v_updated IS DISTINCT FROM 1 THEN
                    RAISE EXCEPTION 'credit_not_reserved' USING ERRCODE = 'P0001';
                END IF;
            END IF;

            UPDATE solar_app.service_request_details
               SET status_ref_data_id = v_request_completed_id,
                   updated_by = v_actor,
                   updated_on = clock_timestamp()
             WHERE service_request_id = v_request_id
               AND customer_id = v_customer_id;

            IF v_milestone_status IN ('MS_DUE', 'MS_BOOKED') THEN
                SELECT status_row.ref_data_id
                  INTO v_milestone_completed_id
                  FROM solar_app.ref_data AS status_row
                  JOIN solar_app.ref_data_categories AS category
                    ON category.category_id = status_row.category_id
                 WHERE category.category_code = 'MILESTONE_STATUSES'
                   AND status_row.data_code = 'MS_COMPLETED'
                   AND category.active_ind IS TRUE
                   AND status_row.active_ind IS TRUE;
                IF v_milestone_completed_id IS NULL THEN
                    RAISE EXCEPTION 'milestone_status_missing' USING ERRCODE = 'P0001';
                END IF;
                UPDATE solar_app.service_milestone_details
                   SET status_ref_data_id = v_milestone_completed_id,
                       updated_by = v_actor,
                       updated_on = clock_timestamp()
                 WHERE service_milestone_id = v_milestone_id
                   AND (
                       service_request_id = v_request_id
                       OR service_request_id IS NULL
                   );
                GET DIAGNOSTICS v_updated = ROW_COUNT;
                IF v_updated IS DISTINCT FROM 1 THEN
                    RAISE EXCEPTION 'milestone_not_open' USING ERRCODE = 'P0001';
                END IF;
            END IF;

            v_data := jsonb_build_object(
                'site_visit_id', v_visit_id::TEXT,
                'visit_no', v_visit_no,
                'service_request_id', v_request_id::TEXT,
                'service_request_no', v_request_no,
                'status_code', 'VISIT_COMPLETED',
                'charge_amount', v_quoted_amount,
                'currency_code', NULLIF(btrim(v_quoted_currency), ''),
                'visit_charge_slab_id', v_quoted_slab_id::TEXT,
                'coverage', v_coverage,
                'credit_consumed', v_consume
            );
        EXCEPTION
            WHEN unique_violation THEN
                v_duplicate := TRUE;
            WHEN SQLSTATE 'P0001' THEN
                v_status := 'ERROR';
                v_code := 500;
                v_message := 'Site visit could not be completed';
                v_data := NULL;
                v_log_error := SQLERRM;
                v_sql_state := SQLSTATE;
        END;

        IF v_duplicate THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'This service request already has a visit';
            v_data := NULL;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Site visit could not be completed';
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
            'fn_update_site_visit_details',
            v_actor,
            v_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'service_request_id', v_request_id
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

COMMENT ON FUNCTION solar_app.fn_update_site_visit_details(JSONB) IS
    'Creates the one visit for a confirmed booking when needed and completes it. Copies the stored quote and consumes that booking''s RESERVED credit only when the quote is an AMC credit.';
