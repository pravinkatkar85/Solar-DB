-- Development tests for solar_app.fn_get_dropdown_data.
--
-- There is no existing SQL test directory. This script lives with the other
-- manual SQL scripts and is not a seed or schema change.
--
-- Safety:
--   * The function inserts audit rows into solar_app.log_sql_functions.
--   * This script runs inside one transaction and ends with ROLLBACK, so those
--     audit rows are not kept.
--   * It does not insert, update, or delete reference or business data.
--   * Run it only against a development database that already has 01_schema.sql,
--     02_functions.sql, and 03_seed_data.sql applied.
--
-- psql command (replace the database name if yours is different):
--   psql -d SolarDB -v ON_ERROR_STOP=1 -f SQLScripts/05_test_fn_get_dropdown_data.sql
--
-- If a test fails, psql stops with the transaction aborted. Run ROLLBACK;
-- before using that session again.

BEGIN;

DO $test$
DECLARE
    v_result            JSONB;
    v_country_id        BIGINT;
    v_district_id       BIGINT;
    v_missing_country   BIGINT;
    v_country_count     BIGINT;
    v_state_count       BIGINT;
    v_role_count        BIGINT;
    v_discom_count      BIGINT;
    v_option_count      INTEGER;
    v_endpoint          CONSTANT TEXT := '/api/dropdowns';
BEGIN
    IF to_regprocedure('solar_app.fn_get_dropdown_data(jsonb)') IS NULL THEN
        RAISE EXCEPTION 'Install SQLScripts/02_functions.sql before running this test';
    END IF;

    SELECT country_id
      INTO v_country_id
      FROM solar_app.ref_countries
     WHERE country_code = 'IN'
       AND active_ind IS TRUE;

    IF v_country_id IS NULL THEN
        RAISE EXCEPTION 'Canonical seed must include active country IN';
    END IF;

    SELECT COUNT(*)
      INTO v_country_count
      FROM solar_app.ref_countries
     WHERE active_ind IS TRUE;

    SELECT COUNT(*)
      INTO v_state_count
      FROM solar_app.ref_states
     WHERE country_id = v_country_id
       AND active_ind IS TRUE;

    SELECT COUNT(*)
      INTO v_role_count
      FROM solar_app.ref_data data_row
      JOIN solar_app.ref_data_categories category_row
        ON category_row.category_id = data_row.category_id
     WHERE category_row.category_code = 'USER_ROLES'
       AND category_row.active_ind IS TRUE
       AND data_row.active_ind IS TRUE;

    IF v_role_count = 0 OR v_state_count = 0 THEN
        RAISE EXCEPTION 'Canonical seed must include USER_ROLES and states for IN';
    END IF;

    -- 1. Valid configured REF_DATA dropdown.
    v_result := solar_app.fn_get_dropdown_data(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'logged_in_user_id', 'DEV_TEST',
        'dropdown_code', 'USER_ROLES'
    ));

    v_option_count := jsonb_array_length(v_result #> '{data,options}');
    IF v_result->>'status' IS DISTINCT FROM 'SUCCESS'
       OR (v_result->>'code')::INTEGER IS DISTINCT FROM 200
       OR v_option_count IS DISTINCT FROM v_role_count
       OR jsonb_typeof(v_result #> '{data,options,0}') IS DISTINCT FROM 'object'
       OR (v_result #>> '{data,options,0,value}') IS NULL
       OR (v_result #>> '{data,options,0,label}') IS NULL THEN
        RAISE EXCEPTION 'Valid USER_ROLES dropdown failed: %', v_result;
    END IF;

    -- 2. Unknown dropdown code.
    v_result := solar_app.fn_get_dropdown_data(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'logged_in_user_id', 'DEV_TEST',
        'dropdown_code', 'NOT_A_REAL_DROPDOWN'
    ));

    IF v_result->>'status' IS DISTINCT FROM 'ERROR'
       OR (v_result->>'code')::INTEGER IS DISTINCT FROM 404
       OR v_result->'data' IS DISTINCT FROM 'null'::JSONB THEN
        RAISE EXCEPTION 'Unknown dropdown code failed: %', v_result;
    END IF;

    -- 3. Missing and malformed payload fields.
    v_result := solar_app.fn_get_dropdown_data(NULL);
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 400 THEN
        RAISE EXCEPTION 'Null payload should be rejected: %', v_result;
    END IF;

    v_result := solar_app.fn_get_dropdown_data('[]'::JSONB);
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 400 THEN
        RAISE EXCEPTION 'Array payload should be rejected: %', v_result;
    END IF;

    v_result := solar_app.fn_get_dropdown_data(jsonb_build_object(
        'logged_in_user_id', 'DEV_TEST',
        'dropdown_code', 'USER_ROLES'
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 400 THEN
        RAISE EXCEPTION 'Missing api_endpoint should be rejected: %', v_result;
    END IF;

    v_result := solar_app.fn_get_dropdown_data(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'logged_in_user_id', 'DEV_TEST'
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 400 THEN
        RAISE EXCEPTION 'Missing dropdown_code should be rejected: %', v_result;
    END IF;

    v_result := solar_app.fn_get_dropdown_data(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'logged_in_user_id', 'DEV_TEST',
        'dropdown_code', 'STATES'
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 400
       OR v_result->>'message' IS DISTINCT FROM 'parent_value is required for this dropdown' THEN
        RAISE EXCEPTION 'STATES without parent_value should be rejected: %', v_result;
    END IF;

    -- 4. Empty result: a well-formed parent id that matches no country.
    SELECT COALESCE(MAX(country_id), 0) + 1
      INTO v_missing_country
      FROM solar_app.ref_countries;

    v_result := solar_app.fn_get_dropdown_data(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'logged_in_user_id', 'DEV_TEST',
        'dropdown_code', 'STATES',
        'parent_value', v_missing_country::TEXT
    ));

    IF v_result->>'status' IS DISTINCT FROM 'SUCCESS'
       OR (v_result->>'code')::INTEGER IS DISTINCT FROM 200
       OR v_result #> '{data,options}' IS DISTINCT FROM '[]'::JSONB
       OR v_result->>'message' IS DISTINCT FROM 'No dropdown options found' THEN
        RAISE EXCEPTION 'Empty STATES result failed: %', v_result;
    END IF;

    -- 5. Parent-filtered dropdown, including statewide NULL district rows.
    v_result := solar_app.fn_get_dropdown_data(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'logged_in_user_id', 'DEV_TEST',
        'dropdown_code', 'STATES',
        'parent_value', v_country_id::TEXT
    ));

    v_option_count := jsonb_array_length(v_result #> '{data,options}');
    IF v_result->>'status' IS DISTINCT FROM 'SUCCESS'
       OR v_option_count IS DISTINCT FROM v_state_count
       OR EXISTS (
            SELECT 1
              FROM jsonb_array_elements(v_result #> '{data,options}') option_row
             WHERE NOT EXISTS (
                    SELECT 1
                      FROM solar_app.ref_states state_row
                     WHERE state_row.country_id = v_country_id
                       AND state_row.active_ind IS TRUE
                       AND state_row.state_id::TEXT = option_row->>'value'
             )
       ) THEN
        RAISE EXCEPTION 'Parent-filtered STATES failed: %', v_result;
    END IF;

    SELECT district_id
      INTO v_district_id
      FROM solar_app.ref_discoms
     WHERE discom_code = 'TPL_AMD'
       AND active_ind IS TRUE;

    IF v_district_id IS NULL THEN
        RAISE EXCEPTION 'Canonical seed must include active DISCOM TPL_AMD';
    END IF;

    SELECT COUNT(*)
      INTO v_discom_count
      FROM solar_app.ref_discoms
     WHERE active_ind IS TRUE
       AND (district_id = v_district_id OR district_id IS NULL);

    v_result := solar_app.fn_get_dropdown_data(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'logged_in_user_id', 'DEV_TEST',
        'dropdown_code', 'DISCOMS_BY_DISTRICT',
        'parent_value', v_district_id::TEXT
    ));

    IF v_result->>'status' IS DISTINCT FROM 'SUCCESS'
       OR jsonb_array_length(v_result #> '{data,options}') IS DISTINCT FROM v_discom_count THEN
        RAISE EXCEPTION 'DISCOMS_BY_DISTRICT null-parent rule failed: %', v_result;
    END IF;

    -- 6. SQL-injection-style input must not change data or execute SQL.
    v_result := solar_app.fn_get_dropdown_data(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'logged_in_user_id', 'DEV_TEST',
        'dropdown_code', 'USER_ROLES''; DROP TABLE solar_app.ref_countries; --'
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 400
       OR v_result->'data' IS DISTINCT FROM 'null'::JSONB THEN
        RAISE EXCEPTION 'Unsafe dropdown_code should be rejected: %', v_result;
    END IF;

    v_result := solar_app.fn_get_dropdown_data(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'logged_in_user_id', 'DEV_TEST',
        'dropdown_code', 'STATES',
        'parent_value', '1 OR 1=1'
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 400 THEN
        RAISE EXCEPTION 'Unsafe parent_value should be rejected: %', v_result;
    END IF;

    v_result := solar_app.fn_get_dropdown_data(jsonb_build_object(
        'api_endpoint', v_endpoint,
        'logged_in_user_id', 'DEV_TEST',
        'dropdown_code', 'STATES',
        'parent_value', '1; DELETE FROM solar_app.ref_states'
    ));
    IF (v_result->>'code')::INTEGER IS DISTINCT FROM 400 THEN
        RAISE EXCEPTION 'Unsafe parent_value statement should be rejected: %', v_result;
    END IF;

    IF to_regclass('solar_app.ref_countries') IS NULL
       OR (SELECT COUNT(*) FROM solar_app.ref_countries WHERE active_ind IS TRUE) IS DISTINCT FROM v_country_count
       OR (SELECT COUNT(*) FROM solar_app.ref_states WHERE country_id = v_country_id AND active_ind IS TRUE) IS DISTINCT FROM v_state_count THEN
        RAISE EXCEPTION 'Injection-style input changed reference data';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM solar_app.log_sql_functions
         WHERE function_name = 'fn_get_dropdown_data'
           AND logged_in_user_id = 'DEV_TEST'
    ) THEN
        RAISE EXCEPTION 'Function did not write log_sql_functions';
    END IF;

    RAISE NOTICE 'fn_get_dropdown_data tests passed';
END
$test$;

ROLLBACK;
