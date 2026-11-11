-- Cancels, lapses, or reschedules one service request owned by the session customer.
-- A RESERVED credit can be released. A CONSUMED credit is never released.
-- Reschedule stores a new quote only after the customer confirms that server fee, currency, and slab.
-- A different slab is a mismatch. The original booking and reservation stay unchanged.
-- A failed reschedule leaves the original booking, quote, and reservation unchanged.
-- Do not install this file until migration 08 has been applied and this install is approved.

CREATE OR REPLACE FUNCTION solar_app.fn_update_service_request_details(p_payload JSONB)
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
    v_message              TEXT := 'Service request updated';
    v_data                 JSONB := NULL;
    v_response             JSONB;
    v_log_error            TEXT;
    v_sql_state            VARCHAR(10);
    v_token_hash           TEXT;
    v_session_count        INTEGER := 0;
    v_session_id           BIGINT;
    v_user_id              BIGINT;
    v_active               BOOLEAN;
    v_account_code         VARCHAR(50);
    v_claimed              TEXT;
    v_customer_id          BIGINT;
    v_action               TEXT;
    v_request_text         TEXT;
    v_request_id           BIGINT;
    v_request_no           VARCHAR(30);
    v_site_id              BIGINT;
    v_request_status       VARCHAR(50);
    v_milestone_id         BIGINT;
    v_target_code          VARCHAR(50);
    v_target_status_id     BIGINT;
    v_visit_completed      BOOLEAN := FALSE;
    v_reservation_id       BIGINT;
    v_reservation_contract BIGINT;
    v_reservation_seq      INTEGER;
    v_reservation_status   VARCHAR(20);
    v_credit_released      BOOLEAN := FALSE;
    v_other_request_id     BIGINT;
    v_milestone_status     VARCHAR(50);
    v_claim_end            DATE;
    v_milestone_link       BIGINT;
    v_next_status_code     VARCHAR(50);
    v_next_status_id       BIGINT;
    v_visit_cancelled_id   BIGINT;
    v_date_text            TEXT;
    v_preferred_on         DATE;
    v_fee                  JSONB;
    v_fee_data             JSONB;
    v_fee_code             INTEGER;
    v_quote_status         TEXT;
    v_free_slab            BOOLEAN := FALSE;
    v_slab_charge          NUMERIC(12,2);
    v_quoted_amount        NUMERIC(12,2);
    v_currency             CHAR(3);
    v_slab_id              BIGINT;
    v_distance             NUMERIC(12,2);
    v_contract_id          BIGINT;
    v_linked_contract_id   BIGINT;
    v_snapshot             JSONB;
    v_count_value          JSONB;
    v_radius_value         JSONB;
    v_allowance            INTEGER;
    v_radius               NUMERIC(12,2);
    v_credit_seq           INTEGER;
    v_coverage             TEXT := 'PAID_SLAB';
    v_reserve              BOOLEAN := FALSE;
    v_keep_reservation     BOOLEAN := FALSE;
    v_confirmed_amount_text TEXT;
    v_confirmed_currency   TEXT;
    v_confirmed_slab_text  TEXT;
    v_confirmed_amount     NUMERIC(12,2);
    v_confirmed_slab_id    BIGINT;
    v_confirmation_sent    BOOLEAN := FALSE;
    v_preview              BOOLEAN := FALSE;
    v_mismatch             BOOLEAN := FALSE;
    v_saved                BOOLEAN := FALSE;
    v_attempt              INTEGER;
    v_updated              INTEGER;
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
            v_message := 'This account cannot change a service request';
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

        v_action := upper(NULLIF(btrim(COALESCE(p_payload->>'action', '')), ''));
        IF v_action NOT IN ('CANCEL', 'LAPSE', 'RESCHEDULE') THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose cancel, lapse, or reschedule';
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
               request.milestone_id,
               status_row.data_code
          INTO v_request_id, v_request_no, v_site_id, v_milestone_id, v_request_status
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

        IF v_request_status IN ('SR_COMPLETED', 'SR_CANCELLED', 'SR_LAPSED') THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'This service request can no longer be changed';
            EXIT body;
        END IF;

        SELECT EXISTS (
            SELECT 1
              FROM solar_app.site_visit_details AS visit
              LEFT JOIN solar_app.ref_data AS visit_status
                ON visit_status.ref_data_id = visit.visit_status_ref_data_id
             WHERE visit.service_request_id = v_request_id
               AND (
                   visit.completed_on IS NOT NULL
                   OR visit_status.data_code = 'VISIT_COMPLETED'
               )
        )
          INTO v_visit_completed;
        IF v_visit_completed IS TRUE THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'This service request can no longer be changed';
            EXIT body;
        END IF;

        SELECT held.amc_credit_reservation_id,
               held.amc_contract_id,
               held.credit_seq,
               held.reservation_status
          INTO v_reservation_id, v_reservation_contract, v_reservation_seq, v_reservation_status
          FROM solar_app.amc_credit_reservation_details AS held
         WHERE held.service_request_id = v_request_id
           AND held.active_ind IS TRUE
           AND held.reservation_status IN ('RESERVED', 'CONSUMED')
           FOR UPDATE;
        IF v_reservation_status = 'CONSUMED' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'This service request can no longer be changed';
            EXIT body;
        END IF;

        IF v_action IN ('CANCEL', 'LAPSE') THEN
            v_target_code := CASE WHEN v_action = 'LAPSE' THEN 'SR_LAPSED' ELSE 'SR_CANCELLED' END;
            SELECT status_row.ref_data_id
              INTO v_target_status_id
              FROM solar_app.ref_data AS status_row
              JOIN solar_app.ref_data_categories AS category
                ON category.category_id = status_row.category_id
             WHERE category.category_code = 'SERVICE_REQUEST_STATUSES'
               AND status_row.data_code = v_target_code
               AND category.active_ind IS TRUE
               AND status_row.active_ind IS TRUE;
            IF v_target_status_id IS NULL THEN
                v_status := 'ERROR';
                v_code := 500;
                v_message := 'Service request could not be changed';
                v_log_error := v_target_code || ' is not configured';
                EXIT body;
            END IF;

            SELECT visit_status.ref_data_id
              INTO v_visit_cancelled_id
              FROM solar_app.ref_data AS visit_status
              JOIN solar_app.ref_data_categories AS category
                ON category.category_id = visit_status.category_id
             WHERE category.category_code = 'SITE_VISIT_STATUSES'
               AND visit_status.data_code = 'VISIT_CANCELLED'
               AND category.active_ind IS TRUE
               AND visit_status.active_ind IS TRUE;
            IF v_visit_cancelled_id IS NULL AND EXISTS (
                SELECT 1
                  FROM solar_app.site_visit_details AS visit
                 WHERE visit.service_request_id = v_request_id
                   AND visit.completed_on IS NULL
            ) THEN
                v_status := 'ERROR';
                v_code := 500;
                v_message := 'Service request could not be changed';
                v_log_error := 'VISIT_CANCELLED is not configured';
                EXIT body;
            END IF;

            UPDATE solar_app.service_request_details
               SET status_ref_data_id = v_target_status_id,
                   milestone_id = NULL,
                   updated_by = v_actor,
                   updated_on = clock_timestamp()
             WHERE service_request_id = v_request_id
               AND customer_id = v_customer_id;

            IF v_reservation_status = 'RESERVED' THEN
                UPDATE solar_app.amc_credit_reservation_details
                   SET reservation_status = 'RELEASED',
                       updated_by = v_actor,
                       updated_on = clock_timestamp()
                 WHERE amc_credit_reservation_id = v_reservation_id
                   AND reservation_status = 'RESERVED'
                   AND active_ind IS TRUE;
                GET DIAGNOSTICS v_updated = ROW_COUNT;
                v_credit_released := v_updated = 1;
            END IF;

            IF v_milestone_id IS NOT NULL THEN
                SELECT milestone.service_request_id,
                       milestone.claim_window_end_on,
                       status_row.data_code
                  INTO v_milestone_link, v_claim_end, v_milestone_status
                  FROM solar_app.service_milestone_details AS milestone
                  JOIN solar_app.ref_data AS status_row
                    ON status_row.ref_data_id = milestone.status_ref_data_id
                 WHERE milestone.service_milestone_id = v_milestone_id
                   AND milestone.active_ind IS TRUE
                   FOR UPDATE;

                SELECT other.service_request_id
                  INTO v_other_request_id
                  FROM solar_app.service_request_details AS other
                  JOIN solar_app.ref_data AS other_status
                    ON other_status.ref_data_id = other.status_ref_data_id
                 WHERE other.milestone_id = v_milestone_id
                   AND other.service_request_id <> v_request_id
                   AND other.active_ind IS TRUE
                   AND other_status.data_code NOT IN ('SR_CANCELLED', 'SR_LAPSED')
                 ORDER BY other.service_request_id
                 LIMIT 1;

                IF v_milestone_status IS NOT NULL AND v_milestone_status IS DISTINCT FROM 'MS_COMPLETED' THEN
                    IF v_other_request_id IS NOT NULL THEN
                        IF v_milestone_link = v_request_id THEN
                            UPDATE solar_app.service_milestone_details
                               SET service_request_id = v_other_request_id,
                                   updated_by = v_actor,
                                   updated_on = clock_timestamp()
                             WHERE service_milestone_id = v_milestone_id
                               AND service_request_id = v_request_id;
                        END IF;
                    ELSE
                        v_next_status_code := CASE
                            WHEN v_claim_end IS NOT NULL AND v_claim_end < CURRENT_DATE THEN 'MS_LAPSED'
                            ELSE 'MS_DUE'
                        END;
                        SELECT status_row.ref_data_id
                          INTO v_next_status_id
                          FROM solar_app.ref_data AS status_row
                          JOIN solar_app.ref_data_categories AS category
                            ON category.category_id = status_row.category_id
                         WHERE category.category_code = 'MILESTONE_STATUSES'
                           AND status_row.data_code = v_next_status_code
                           AND category.active_ind IS TRUE
                           AND status_row.active_ind IS TRUE;
                        IF v_next_status_id IS NULL THEN
                            RAISE EXCEPTION 'milestone_status_missing' USING ERRCODE = 'P0001';
                        END IF;
                        UPDATE solar_app.service_milestone_details
                           SET service_request_id = CASE
                                   WHEN service_request_id = v_request_id THEN NULL
                                   ELSE service_request_id
                               END,
                               status_ref_data_id = v_next_status_id,
                               updated_by = v_actor,
                               updated_on = clock_timestamp()
                         WHERE service_milestone_id = v_milestone_id;
                    END IF;
                END IF;
            END IF;

            IF v_visit_cancelled_id IS NOT NULL THEN
                UPDATE solar_app.site_visit_details
                   SET visit_status_ref_data_id = v_visit_cancelled_id,
                       updated_by = v_actor,
                       updated_on = clock_timestamp()
                 WHERE service_request_id = v_request_id
                   AND completed_on IS NULL;
            END IF;

            v_message := CASE
                WHEN v_action = 'LAPSE' THEN 'Service request lapsed'
                ELSE 'Service request cancelled'
            END;
            v_data := jsonb_build_object(
                'service_request_id', v_request_id::TEXT,
                'service_request_no', v_request_no,
                'status_code', v_target_code,
                'credit_released', v_credit_released
            );
        ELSE
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

            IF v_milestone_id IS NOT NULL THEN
                SELECT milestone.claim_window_end_on
                  INTO v_claim_end
                  FROM solar_app.service_milestone_details AS milestone
                 WHERE milestone.service_milestone_id = v_milestone_id
                   AND milestone.site_id = v_site_id
                   AND milestone.active_ind IS TRUE;
                IF v_claim_end IS NULL OR v_preferred_on > v_claim_end THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'This service visit cannot be claimed';
                    EXIT body;
                END IF;
            END IF;

            v_confirmed_amount_text := NULLIF(btrim(COALESCE(p_payload->>'confirmed_charge_amount', '')), '');
            v_confirmed_currency := NULLIF(btrim(COALESCE(p_payload->>'confirmed_currency_code', '')), '');
            v_confirmed_slab_text := NULLIF(btrim(COALESCE(p_payload->>'confirmed_visit_charge_slab_id', '')), '');
            IF ((v_confirmed_amount_text IS NULL)::INTEGER
                + (v_confirmed_currency IS NULL)::INTEGER
                + (v_confirmed_slab_text IS NULL)::INTEGER) NOT IN (0, 3) THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Confirm the new visit fee';
                EXIT body;
            END IF;
            v_confirmation_sent := v_confirmed_amount_text IS NOT NULL;
            IF v_confirmation_sent AND (
                v_confirmed_amount_text !~ '^[0-9]+(\.[0-9]{1,2})?$'
                OR v_confirmed_slab_text !~ '^[0-9]{1,18}$'
            ) THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Confirm the new visit fee';
                EXIT body;
            END IF;
            IF v_confirmation_sent THEN
                v_confirmed_amount := v_confirmed_amount_text::NUMERIC(12,2);
                v_confirmed_slab_id := v_confirmed_slab_text::BIGINT;
            END IF;

            v_fee := solar_app.fn_get_site_visit_charge(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'jwt_token_hash', v_token_hash,
                'site_id', v_site_id::TEXT,
                'visit_on', to_char(v_preferred_on, 'YYYY-MM-DD')
            ));
            IF v_fee IS NULL OR jsonb_typeof(v_fee) <> 'object' THEN
                v_status := 'ERROR';
                v_code := 500;
                v_message := 'Service request could not be changed';
                EXIT body;
            END IF;
            v_fee_data := v_fee->'data';
            IF COALESCE(v_fee->>'code', '') ~ '^[0-9]+$' THEN
                v_fee_code := (v_fee->>'code')::INTEGER;
            END IF;
            IF v_fee->>'status' IS DISTINCT FROM 'SUCCESS' OR v_fee_code IS DISTINCT FROM 200 THEN
                v_status := 'ERROR';
                v_code := CASE
                    WHEN v_fee_code IN (400, 401, 403, 404, 500) THEN v_fee_code
                    ELSE 500
                END;
                v_message := COALESCE(NULLIF(btrim(v_fee->>'message'), ''), 'Service request could not be changed');
                EXIT body;
            END IF;
            v_quote_status := v_fee_data->>'quote_status';
            IF v_quote_status IS DISTINCT FROM 'AVAILABLE'
               OR v_fee_data #>> '{free_entitlement,reason}' = 'CREDIT_HOLD_UNAVAILABLE' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Visit fee is not available';
                v_data := v_fee_data;
                EXIT body;
            END IF;
            IF jsonb_typeof(v_fee_data->'is_free_slab') IS DISTINCT FROM 'boolean'
               OR v_fee_data->>'charge_amount' IS NULL
               OR v_fee_data->>'currency_code' IS NULL
               OR COALESCE(v_fee_data->>'visit_charge_slab_id', '') !~ '^[0-9]{1,18}$'
               OR v_fee_data->>'distance_km' IS NULL THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Visit fee is not available';
                v_data := v_fee_data;
                EXIT body;
            END IF;
            BEGIN
                v_free_slab := (v_fee_data->'is_free_slab') = 'true'::JSONB;
                v_slab_charge := (v_fee_data->>'charge_amount')::NUMERIC(12,2);
                v_distance := (v_fee_data->>'distance_km')::NUMERIC(12,2);
                v_currency := btrim(v_fee_data->>'currency_code');
                v_slab_id := (v_fee_data->>'visit_charge_slab_id')::BIGINT;
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

            FOR v_attempt IN 1..3 LOOP
                BEGIN
                    v_reserve := FALSE;
                    v_keep_reservation := FALSE;
                    v_credit_seq := NULL;
                    v_contract_id := NULL;
                    v_linked_contract_id := NULL;
                    v_coverage := 'PAID_SLAB';
                    v_quoted_amount := v_slab_charge;

                    IF v_free_slab THEN
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
                                                  AND held.amc_credit_reservation_id IS DISTINCT FROM v_reservation_id
                                               )
                                         ORDER BY free_seq.seq
                                         LIMIT 1;
                                        IF v_credit_seq IS NOT NULL THEN
                                            v_reserve := TRUE;
                                            v_coverage := 'AMC_CREDIT';
                                            v_quoted_amount := 0;
                                            v_linked_contract_id := v_contract_id;
                                            v_keep_reservation := v_reservation_status = 'RESERVED'
                                                AND v_reservation_contract = v_contract_id
                                                AND v_reservation_seq = v_credit_seq;
                                        END IF;
                                    END IF;
                                END IF;
                            END IF;
                        END IF;
                    END IF;

                    IF NOT v_confirmation_sent THEN
                        v_preview := TRUE;
                        EXIT;
                    END IF;
                    IF v_confirmed_amount IS DISTINCT FROM v_quoted_amount
                       OR upper(btrim(v_confirmed_currency)) IS DISTINCT FROM upper(btrim(v_currency))
                       OR v_confirmed_slab_id IS DISTINCT FROM v_slab_id THEN
                        v_mismatch := TRUE;
                        EXIT;
                    END IF;

                    IF v_reservation_status = 'RESERVED' AND NOT v_keep_reservation THEN
                        UPDATE solar_app.amc_credit_reservation_details
                           SET reservation_status = 'RELEASED',
                               updated_by = v_actor,
                               updated_on = clock_timestamp()
                         WHERE amc_credit_reservation_id = v_reservation_id
                           AND reservation_status = 'RESERVED'
                           AND active_ind IS TRUE;
                    END IF;

                    IF v_reserve AND NOT v_keep_reservation THEN
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

                    UPDATE solar_app.service_request_details
                       SET preferred_on = v_preferred_on,
                           amc_contract_id = v_linked_contract_id,
                           quoted_charge_amount = v_quoted_amount,
                           quoted_currency_code = v_currency,
                           visit_charge_slab_id = v_slab_id,
                           fee_quote_snapshot_json = jsonb_build_object(
                               'coverage', v_coverage,
                               'credit_seq', v_credit_seq,
                               'slab_charge_amount', v_slab_charge,
                               'fee', v_fee_data
                           ),
                           quote_confirmed_on = clock_timestamp(),
                           updated_by = v_actor,
                           updated_on = clock_timestamp()
                     WHERE service_request_id = v_request_id
                       AND customer_id = v_customer_id;

                    UPDATE solar_app.site_visit_details
                       SET scheduled_on = v_preferred_on,
                           updated_by = v_actor,
                           updated_on = clock_timestamp()
                     WHERE service_request_id = v_request_id
                       AND completed_on IS NULL;

                    v_saved := TRUE;
                    EXIT;
                EXCEPTION
                    WHEN unique_violation THEN
                        v_saved := FALSE;
                        v_preview := FALSE;
                        v_mismatch := FALSE;
                END;
            END LOOP;

            IF v_preview OR v_mismatch THEN
                IF v_mismatch THEN
                    v_status := 'ERROR';
                    v_code := 400;
                END IF;
                v_message := 'Confirm the new visit fee';
                v_data := jsonb_build_object(
                    'confirmation_required', TRUE,
                    'service_request_id', v_request_id::TEXT,
                    'service_request_no', v_request_no,
                    'preferred_on', to_char(v_preferred_on, 'YYYY-MM-DD'),
                    'quoted_charge_amount', v_quoted_amount,
                    'quoted_currency_code', NULLIF(btrim(v_currency), ''),
                    'visit_charge_slab_id', v_slab_id::TEXT,
                    'coverage', v_coverage
                );
            ELSIF NOT v_saved THEN
                v_status := 'ERROR';
                v_code := 500;
                v_message := 'Service request could not be changed';
                v_data := NULL;
            ELSE
                v_message := 'Service request rescheduled';
                v_data := jsonb_build_object(
                    'confirmation_required', FALSE,
                    'service_request_id', v_request_id::TEXT,
                    'service_request_no', v_request_no,
                    'preferred_on', to_char(v_preferred_on, 'YYYY-MM-DD'),
                    'quoted_charge_amount', v_quoted_amount,
                    'quoted_currency_code', NULLIF(btrim(v_currency), ''),
                    'visit_charge_slab_id', v_slab_id::TEXT,
                    'coverage', v_coverage,
                    'amc_contract_id', CASE WHEN v_linked_contract_id IS NULL THEN NULL ELSE v_linked_contract_id::TEXT END,
                    'credit_seq', v_credit_seq
                );
            END IF;
        END IF;
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Service request could not be changed';
            v_data := NULL;
            v_log_error := SQLERRM;
            v_sql_state := SQLSTATE;
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Service request could not be changed';
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
            'fn_update_service_request_details',
            v_actor,
            v_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'service_request_id', v_request_id,
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

COMMENT ON FUNCTION solar_app.fn_update_service_request_details(JSONB) IS
    'Cancels or lapses an uncompleted booking and releases only a RESERVED credit, or reschedules it after the customer confirms the recalculated fee.';
