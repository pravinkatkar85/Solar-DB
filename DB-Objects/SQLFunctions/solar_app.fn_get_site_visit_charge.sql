-- Read-only visit-fee quote for one site and one proposed visit date.
-- Does not reserve a credit, create a booking or visit, or change a milestone.
-- Authored only. Do not install this file until separately approved.
-- A fee is returned only from a non-development default office and a non-development slab.
-- Free visit count and radius come only from plan_snapshot_json.

CREATE OR REPLACE FUNCTION solar_app.fn_get_site_visit_charge(p_payload JSONB)
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
    v_message            TEXT := 'Visit fee calculated';
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
    v_visit_text         TEXT;
    v_visit_on           DATE;
    v_purpose_text       TEXT;
    v_purpose_id         BIGINT;
    v_purpose_ok         BOOLEAN := FALSE;
    v_site_lat           NUMERIC(10,7);
    v_site_lon           NUMERIC(10,7);
    v_office_count       INTEGER := 0;
    v_office_id          BIGINT;
    v_office_lat         NUMERIC(10,7);
    v_office_lon         NUMERIC(10,7);
    v_distance           NUMERIC(12,2);
    v_contract_id        BIGINT;
    v_snapshot           JSONB;
    v_count_value        JSONB;
    v_radius_value       JSONB;
    v_allowance          INTEGER;
    v_radius             NUMERIC(12,2);
    v_allowance_known    BOOLEAN := FALSE;
    v_radius_known       BOOLEAN := FALSE;
    v_snapshot_reason    TEXT;
    v_held               INTEGER;
    v_credits_known      BOOLEAN := FALSE;
    v_available          INTEGER;
    v_specific_count     INTEGER := 0;
    v_general_count      INTEGER := 0;
    v_slab_id            BIGINT;
    v_charge             NUMERIC(12,2);
    v_currency           CHAR(3);
    v_free_slab          BOOLEAN;
    v_quote_status       TEXT := 'UNAVAILABLE';
    v_unavailable        TEXT;
    v_entitled           BOOLEAN := FALSE;
    v_entitlement_reason TEXT := 'NO_ELIGIBLE_CONTRACT';
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
            v_message := 'This account cannot view a visit fee';
            EXIT body;
        END IF;

        v_site_text := NULLIF(btrim(COALESCE(p_payload->>'site_id', '')), '');
        IF v_site_text IS NULL OR v_site_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose an installation';
            EXIT body;
        END IF;
        v_site_id := v_site_text::BIGINT;

        v_visit_text := NULLIF(btrim(COALESCE(p_payload->>'visit_on', '')), '');
        IF v_visit_text IS NULL OR v_visit_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose a visit date';
            EXIT body;
        END IF;
        BEGIN
            v_visit_on := v_visit_text::DATE;
        EXCEPTION
            WHEN OTHERS THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Choose a visit date';
                EXIT body;
        END;

        v_purpose_text := NULLIF(btrim(COALESCE(p_payload->>'visit_purpose_ref_data_id', '')), '');
        IF v_purpose_text IS NOT NULL THEN
            IF v_purpose_text !~ '^[0-9]{1,18}$' THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Choose a visit purpose';
                EXIT body;
            END IF;
            v_purpose_id := v_purpose_text::BIGINT;
            SELECT EXISTS (
                SELECT 1
                  FROM solar_app.ref_data AS purpose
                  JOIN solar_app.ref_data_categories AS category
                    ON category.category_id = purpose.category_id
                 WHERE purpose.ref_data_id = v_purpose_id
                   AND purpose.active_ind IS TRUE
                   AND category.category_code = 'SITE_VISIT_PURPOSES'
                   AND category.active_ind IS TRUE
            )
              INTO v_purpose_ok;
            IF v_purpose_ok IS NOT TRUE THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'Choose a visit purpose';
                EXIT body;
            END IF;
        END IF;

        SELECT customer.customer_id
          INTO v_customer_id
          FROM solar_app.customer_details AS customer
         WHERE customer.user_id = v_user_id
           AND customer.active_ind IS TRUE;

        SELECT site.latitude, site.longitude
          INTO v_site_lat, v_site_lon
          FROM solar_app.site_details AS site
         WHERE site.site_id = v_site_id
           AND site.customer_id = v_customer_id
           AND site.active_ind IS TRUE;

        IF NOT FOUND THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'This installation was not found';
            EXIT body;
        END IF;

        SELECT contract.amc_contract_id, contract.plan_snapshot_json
          INTO v_contract_id, v_snapshot
          FROM solar_app.amc_contract_details AS contract
         WHERE contract.site_id = v_site_id
           AND contract.active_ind IS TRUE
           AND contract.contract_status = 'ACTIVE'
           AND contract.start_on <= v_visit_on
           AND contract.expiry_on >= v_visit_on
         ORDER BY contract.start_on DESC, contract.amc_contract_id DESC
         LIMIT 1;

        IF v_contract_id IS NOT NULL THEN
            IF jsonb_typeof(v_snapshot) IS DISTINCT FROM 'object' THEN
                v_snapshot_reason := 'INVALID_SNAPSHOT';
            ELSE
                v_count_value := v_snapshot->'free_visit_count';
                v_radius_value := v_snapshot->'free_visit_radius_km';
                IF v_count_value IS NULL OR jsonb_typeof(v_count_value) = 'null' THEN
                    v_snapshot_reason := 'MISSING_SNAPSHOT_COUNT';
                ELSIF jsonb_typeof(v_count_value) IS DISTINCT FROM 'number'
                   OR (v_count_value #>> '{}')::NUMERIC < 0
                   OR (v_count_value #>> '{}')::NUMERIC <> trunc((v_count_value #>> '{}')::NUMERIC) THEN
                    v_snapshot_reason := 'INVALID_SNAPSHOT';
                ELSE
                    v_allowance := (v_count_value #>> '{}')::INTEGER;
                    v_allowance_known := TRUE;
                END IF;

                IF v_snapshot_reason IS NULL OR v_snapshot_reason = 'MISSING_SNAPSHOT_COUNT' THEN
                    IF v_radius_value IS NULL OR jsonb_typeof(v_radius_value) = 'null' THEN
                        v_snapshot_reason := COALESCE(v_snapshot_reason, 'MISSING_SNAPSHOT_RADIUS');
                    ELSIF jsonb_typeof(v_radius_value) IS DISTINCT FROM 'number'
                       OR (v_radius_value #>> '{}')::NUMERIC < 0 THEN
                        v_snapshot_reason := 'INVALID_SNAPSHOT';
                        v_allowance_known := FALSE;
                        v_allowance := NULL;
                    ELSE
                        v_radius := round((v_radius_value #>> '{}')::NUMERIC, 2);
                        v_radius_known := TRUE;
                    END IF;
                END IF;
            END IF;

            IF v_allowance_known AND to_regclass('solar_app.amc_credit_reservation_details') IS NOT NULL THEN
                SELECT COUNT(*)::INTEGER
                  INTO v_held
                  FROM solar_app.amc_credit_reservation_details AS held
                 WHERE held.amc_contract_id = v_contract_id
                   AND held.reservation_status IN ('RESERVED', 'CONSUMED')
                   AND held.active_ind IS TRUE;
                v_credits_known := TRUE;
                v_available := GREATEST(0, v_allowance - v_held);
            END IF;
        END IF;

        IF v_site_lat IS NULL OR v_site_lon IS NULL THEN
            v_unavailable := 'MISSING_SITE_COORDINATES';
        ELSE
            SELECT COUNT(*)
              INTO v_office_count
              FROM solar_app.ref_office_locations AS office
             WHERE office.is_default IS TRUE
               AND office.active_ind IS TRUE
               AND left(office.office_code, 4) IS DISTINCT FROM 'DEV_';

            IF v_office_count IS DISTINCT FROM 1 THEN
                v_unavailable := 'MISSING_APPROVED_OFFICE';
            ELSE
                SELECT office.office_location_id, office.latitude, office.longitude
                  INTO v_office_id, v_office_lat, v_office_lon
                  FROM solar_app.ref_office_locations AS office
                 WHERE office.is_default IS TRUE
                   AND office.active_ind IS TRUE
                   AND left(office.office_code, 4) IS DISTINCT FROM 'DEV_';

                v_distance := round((
                    6371 * 2 * asin(least(1.0, sqrt(
                        power(sin(radians((v_site_lat - v_office_lat) / 2)), 2)
                        + cos(radians(v_office_lat)) * cos(radians(v_site_lat))
                          * power(sin(radians((v_site_lon - v_office_lon) / 2)), 2)
                    )))
                )::NUMERIC, 2);

                IF v_purpose_id IS NOT NULL THEN
                    SELECT COUNT(*)
                      INTO v_specific_count
                      FROM solar_app.ref_visit_charge_slabs AS slab
                     WHERE slab.active_ind IS TRUE
                       AND slab.created_by IS DISTINCT FROM 'DEV_SEED'
                       AND slab.visit_purpose_ref_data_id = v_purpose_id
                       AND slab.effective_from <= v_visit_on
                       AND (slab.effective_to IS NULL OR slab.effective_to >= v_visit_on)
                       AND v_distance >= slab.min_distance_km
                       AND (slab.max_distance_km IS NULL OR v_distance < slab.max_distance_km);
                END IF;

                IF v_specific_count > 1 THEN
                    v_unavailable := 'AMBIGUOUS_SLAB';
                ELSIF v_specific_count = 1 THEN
                    SELECT slab.visit_charge_slab_id, slab.charge_amount, slab.currency_code, slab.is_free_ind
                      INTO v_slab_id, v_charge, v_currency, v_free_slab
                      FROM solar_app.ref_visit_charge_slabs AS slab
                     WHERE slab.active_ind IS TRUE
                       AND slab.created_by IS DISTINCT FROM 'DEV_SEED'
                       AND slab.visit_purpose_ref_data_id = v_purpose_id
                       AND slab.effective_from <= v_visit_on
                       AND (slab.effective_to IS NULL OR slab.effective_to >= v_visit_on)
                       AND v_distance >= slab.min_distance_km
                       AND (slab.max_distance_km IS NULL OR v_distance < slab.max_distance_km);
                ELSE
                    SELECT COUNT(*)
                      INTO v_general_count
                      FROM solar_app.ref_visit_charge_slabs AS slab
                     WHERE slab.active_ind IS TRUE
                       AND slab.created_by IS DISTINCT FROM 'DEV_SEED'
                       AND slab.visit_purpose_ref_data_id IS NULL
                       AND slab.effective_from <= v_visit_on
                       AND (slab.effective_to IS NULL OR slab.effective_to >= v_visit_on)
                       AND v_distance >= slab.min_distance_km
                       AND (slab.max_distance_km IS NULL OR v_distance < slab.max_distance_km);

                    IF v_general_count > 1 THEN
                        v_unavailable := 'AMBIGUOUS_SLAB';
                    ELSIF v_general_count = 1 THEN
                        SELECT slab.visit_charge_slab_id, slab.charge_amount, slab.currency_code, slab.is_free_ind
                          INTO v_slab_id, v_charge, v_currency, v_free_slab
                          FROM solar_app.ref_visit_charge_slabs AS slab
                         WHERE slab.active_ind IS TRUE
                           AND slab.created_by IS DISTINCT FROM 'DEV_SEED'
                           AND slab.visit_purpose_ref_data_id IS NULL
                           AND slab.effective_from <= v_visit_on
                           AND (slab.effective_to IS NULL OR slab.effective_to >= v_visit_on)
                           AND v_distance >= slab.min_distance_km
                           AND (slab.max_distance_km IS NULL OR v_distance < slab.max_distance_km);
                    ELSE
                        v_unavailable := 'MISSING_SLAB';
                    END IF;
                END IF;
            END IF;
        END IF;

        IF v_unavailable IS NULL AND v_slab_id IS NULL THEN
            v_unavailable := 'MISSING_SLAB';
        END IF;

        IF v_unavailable IS NULL AND v_slab_id IS NOT NULL THEN
            v_quote_status := 'AVAILABLE';
            v_message := 'Visit fee calculated';
        ELSE
            v_quote_status := 'UNAVAILABLE';
            v_message := 'Visit fee is not available';
            v_slab_id := NULL;
            v_charge := NULL;
            v_currency := NULL;
            v_free_slab := NULL;
        END IF;

        IF v_free_slab IS TRUE THEN
            v_entitlement_reason := 'FREE_PRICING_SLAB';
        ELSIF v_contract_id IS NULL THEN
            v_entitlement_reason := 'NO_ELIGIBLE_CONTRACT';
        ELSIF v_snapshot_reason IS NOT NULL THEN
            v_entitlement_reason := v_snapshot_reason;
        ELSIF v_distance IS NULL THEN
            v_entitlement_reason := 'DISTANCE_UNKNOWN';
        ELSIF v_radius_known IS NOT TRUE OR v_distance > v_radius THEN
            v_entitlement_reason := 'OUTSIDE_SNAPSHOT_RADIUS';
        ELSIF v_credits_known IS NOT TRUE THEN
            v_entitlement_reason := 'CREDIT_HOLD_UNAVAILABLE';
        ELSIF v_available <= 0 THEN
            v_entitlement_reason := 'NO_CREDIT_REMAINING';
        ELSE
            v_entitled := TRUE;
            v_entitlement_reason := 'WITHIN_SNAPSHOT_ALLOWANCE';
        END IF;

        v_data := jsonb_build_object(
            'quote_status', v_quote_status,
            'unavailable_reason', v_unavailable,
            'site_id', v_site_id::TEXT,
            'visit_on', to_char(v_visit_on, 'YYYY-MM-DD'),
            'office_location_id', CASE WHEN v_office_id IS NULL THEN NULL ELSE v_office_id::TEXT END,
            'distance_km', v_distance,
            'visit_charge_slab_id', CASE WHEN v_slab_id IS NULL THEN NULL ELSE v_slab_id::TEXT END,
            'charge_amount', v_charge,
            'currency_code', NULLIF(btrim(v_currency), ''),
            'is_free_slab', v_free_slab,
            'free_entitlement', jsonb_build_object(
                'eligible', v_entitled,
                'reason', v_entitlement_reason,
                'amc_contract_id', CASE WHEN v_contract_id IS NULL THEN NULL ELSE v_contract_id::TEXT END,
                'snapshot_free_visit_count', CASE WHEN v_allowance_known THEN v_allowance ELSE NULL END,
                'snapshot_free_visit_radius_km', CASE WHEN v_radius_known THEN v_radius ELSE NULL END,
                'held_or_consumed_count', CASE WHEN v_credits_known THEN v_held ELSE NULL END,
                'available_credit_count', CASE WHEN v_credits_known THEN v_available ELSE NULL END
            )
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Visit fee could not be calculated';
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
            'fn_get_site_visit_charge',
            v_actor,
            v_user_id,
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'session_id', v_session_id,
                'site_id', v_site_id,
                'visit_on', v_visit_on
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

COMMENT ON FUNCTION solar_app.fn_get_site_visit_charge(JSONB) IS
    'Returns a read-only visit-fee quote for a site owned by the session customer. It does not reserve a credit or write a booking, visit, or milestone.';
