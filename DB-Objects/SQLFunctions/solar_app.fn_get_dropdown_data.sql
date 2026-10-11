-- Authored source for solar_app.fn_get_dropdown_data.
-- Loaded by SQLScripts/02_functions.sql. Do not duplicate this body there.
--
-- This file does not create tables, triggers, seed data, or grants.
-- fn_log_function_execution does not exist yet, so this function writes its
-- own row to solar_app.log_sql_functions. It does not log to log_api_execution;
-- that table is the API layer's audit.
--
-- DB-Design.md mentions ref_dropdown_config.extra_where_sql. That column is
-- not in the executable schema, so this function does not apply an extra
-- predicate.

CREATE OR REPLACE FUNCTION solar_app.fn_get_dropdown_data(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = pg_catalog, solar_app
AS $$
DECLARE
    v_started           TIMESTAMPTZ := clock_timestamp();
    v_api_endpoint      VARCHAR(255);
    v_logged_in_user    VARCHAR(50) := 'SYSTEM';
    v_dropdown_code     TEXT;
    v_parent_text       TEXT;
    v_status            VARCHAR(20) := 'SUCCESS';
    v_code              INTEGER := 200;
    v_message           TEXT := 'Dropdown options loaded';
    v_data              JSONB := NULL;
    v_response          JSONB;
    v_log_error         TEXT;
    v_sql_state         VARCHAR(10);
    v_source_type       VARCHAR(20);
    v_category_code     VARCHAR(50);
    v_source_table      TEXT;
    v_value_column      TEXT;
    v_label_column      TEXT;
    v_parent_column     TEXT;
    v_sort_column       TEXT;
    v_include_null      BOOLEAN := FALSE;
    v_cache_ttl         INTEGER;
    v_parent_type       TEXT;
    v_cast_type         TEXT;
    v_sql               TEXT;
    v_options           JSONB;
    v_identifier_ok     BOOLEAN;
    v_log_payload       JSONB;
BEGIN
    <<body>>
    BEGIN
        IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Payload must be a JSON object';
            EXIT body;
        END IF;

        IF p_payload ? 'api_endpoint'
           AND jsonb_typeof(p_payload->'api_endpoint') <> 'string' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'api_endpoint must be a string';
            EXIT body;
        END IF;

        v_api_endpoint := NULLIF(btrim(p_payload->>'api_endpoint'), '');
        IF v_api_endpoint IS NULL OR char_length(v_api_endpoint) > 255 THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'api_endpoint is required and must be 255 characters or fewer';
            EXIT body;
        END IF;

        IF p_payload ? 'logged_in_user_id'
           AND jsonb_typeof(p_payload->'logged_in_user_id') NOT IN ('string', 'null') THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'logged_in_user_id must be a string';
            EXIT body;
        END IF;

        IF NULLIF(btrim(p_payload->>'logged_in_user_id'), '') IS NOT NULL THEN
            IF char_length(btrim(p_payload->>'logged_in_user_id')) > 50 THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'logged_in_user_id must be 50 characters or fewer';
                EXIT body;
            END IF;
            v_logged_in_user := btrim(p_payload->>'logged_in_user_id');
        END IF;

        IF NOT (p_payload ? 'dropdown_code')
           OR jsonb_typeof(p_payload->'dropdown_code') <> 'string' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'dropdown_code is required';
            EXIT body;
        END IF;

        v_dropdown_code := btrim(p_payload->>'dropdown_code');
        -- Codes in ref_dropdown_config are stable tokens such as STATES.
        -- Anything else is rejected before the lookup so it cannot be used
        -- as SQL text.
        IF v_dropdown_code !~ '^[A-Z][A-Z0-9_]{0,49}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'dropdown_code is not valid';
            EXIT body;
        END IF;

        IF p_payload ? 'parent_value'
           AND jsonb_typeof(p_payload->'parent_value') NOT IN ('string', 'number', 'null') THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'parent_value must be a string or number';
            EXIT body;
        END IF;

        v_parent_text := NULLIF(btrim(p_payload->>'parent_value'), '');

        SELECT cfg.source_type,
               cfg.category_code,
               cfg.source_table,
               cfg.value_column,
               cfg.label_column,
               cfg.parent_filter_column,
               cfg.sort_column,
               cfg.include_null_parent,
               cfg.cache_ttl_seconds
          INTO v_source_type,
               v_category_code,
               v_source_table,
               v_value_column,
               v_label_column,
               v_parent_column,
               v_sort_column,
               v_include_null,
               v_cache_ttl
          FROM solar_app.ref_dropdown_config cfg
         WHERE cfg.dropdown_code = v_dropdown_code
           AND cfg.active_ind IS TRUE;

        IF NOT FOUND THEN
            v_status := 'ERROR';
            v_code := 404;
            v_message := 'Dropdown was not found';
            EXIT body;
        END IF;

        v_identifier_ok := COALESCE(v_value_column, '') ~ '^[a-z][a-z0-9_]{0,62}$'
            AND COALESCE(v_label_column, '') ~ '^[a-z][a-z0-9_]{0,62}$'
            AND COALESCE(v_sort_column, v_label_column, '') ~ '^[a-z][a-z0-9_]{0,62}$'
            AND (v_parent_column IS NULL OR v_parent_column ~ '^[a-z][a-z0-9_]{0,62}$')
            AND COALESCE(v_value_column, '') !~ '(^|_)(regex|secret|password|token|credential|pin)($|_)'
            AND COALESCE(v_label_column, '') !~ '(^|_)(regex|secret|password|token|credential|pin)($|_)'
            AND COALESCE(v_sort_column, '') !~ '(^|_)(regex|secret|password|token|credential|pin)($|_)'
            AND COALESCE(v_parent_column, '') !~ '(^|_)(regex|secret|password|token|credential|pin)($|_)';

        IF v_source_type = 'REF_DATA' THEN
            v_source_table := 'ref_data';
            v_identifier_ok := v_identifier_ok
                AND v_category_code IS NOT NULL
                AND v_value_column IN ('ref_data_id', 'data_code', 'data_value')
                AND v_label_column IN ('data_value', 'data_code', 'data_desc')
                AND COALESCE(v_sort_column, 'sort_order') IN ('sort_order', 'data_value', 'data_code', 'ref_data_id')
                AND (v_parent_column IS NULL OR v_parent_column = 'parent_ref_data_id');
        ELSIF v_source_type = 'TABLE' THEN
            v_identifier_ok := v_identifier_ok
                AND COALESCE(v_source_table, '') ~ '^ref_[a-z][a-z0-9_]{0,60}$';
        ELSE
            v_identifier_ok := FALSE;
        END IF;

        IF NOT v_identifier_ok THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Dropdown configuration is not valid';
            v_log_error := 'Dropdown metadata failed identifier validation';
            EXIT body;
        END IF;

        v_sort_column := COALESCE(v_sort_column, v_label_column);

        IF v_source_type = 'TABLE' THEN
            IF NOT EXISTS (
                SELECT 1
                  FROM information_schema.columns col
                 WHERE col.table_schema = 'solar_app'
                   AND col.table_name = v_source_table
                   AND col.column_name = 'active_ind'
            ) OR NOT EXISTS (
                SELECT 1
                  FROM information_schema.columns col
                 WHERE col.table_schema = 'solar_app'
                   AND col.table_name = v_source_table
                   AND col.column_name = v_value_column
            ) OR NOT EXISTS (
                SELECT 1
                  FROM information_schema.columns col
                 WHERE col.table_schema = 'solar_app'
                   AND col.table_name = v_source_table
                   AND col.column_name = v_label_column
            ) OR NOT EXISTS (
                SELECT 1
                  FROM information_schema.columns col
                 WHERE col.table_schema = 'solar_app'
                   AND col.table_name = v_source_table
                   AND col.column_name = v_sort_column
            ) OR (
                v_parent_column IS NOT NULL
                AND NOT EXISTS (
                    SELECT 1
                      FROM information_schema.columns col
                     WHERE col.table_schema = 'solar_app'
                       AND col.table_name = v_source_table
                       AND col.column_name = v_parent_column
                )
            ) THEN
                v_status := 'ERROR';
                v_code := 500;
                v_message := 'Dropdown configuration is not valid';
                v_log_error := 'Dropdown metadata does not match solar_app columns';
                EXIT body;
            END IF;
        END IF;

        -- A configured parent column means the list is cascading. The schema
        -- does not say what to return when the caller omits parent_value, so
        -- this function requires it instead of returning every child row.
        IF v_parent_column IS NOT NULL AND v_parent_text IS NULL THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'parent_value is required for this dropdown';
            EXIT body;
        END IF;

        IF v_parent_column IS NOT NULL THEN
            SELECT col.data_type
              INTO v_parent_type
              FROM information_schema.columns col
             WHERE col.table_schema = 'solar_app'
               AND col.table_name = v_source_table
               AND col.column_name = v_parent_column;

            v_cast_type := CASE v_parent_type
                WHEN 'bigint' THEN 'bigint'
                WHEN 'integer' THEN 'integer'
                WHEN 'smallint' THEN 'smallint'
                WHEN 'text' THEN 'text'
                WHEN 'character varying' THEN 'text'
                ELSE NULL
            END;

            IF v_cast_type IS NULL THEN
                v_status := 'ERROR';
                v_code := 500;
                v_message := 'Dropdown configuration is not valid';
                v_log_error := 'Parent filter column type is not supported';
                EXIT body;
            END IF;

            IF v_cast_type IN ('bigint', 'integer', 'smallint') THEN
                IF v_parent_text !~ '^[0-9]{1,18}$'
                   OR v_parent_text::NUMERIC > 9223372036854775807
                   OR (v_cast_type = 'smallint' AND v_parent_text::NUMERIC > 32767)
                   OR (v_cast_type = 'integer' AND v_parent_text::NUMERIC > 2147483647) THEN
                    v_status := 'ERROR';
                    v_code := 400;
                    v_message := 'parent_value is not valid';
                    EXIT body;
                END IF;
            END IF;

            IF v_cast_type = 'text' AND char_length(v_parent_text) > 200 THEN
                v_status := 'ERROR';
                v_code := 400;
                v_message := 'parent_value is not valid';
                EXIT body;
            END IF;
        END IF;

        IF v_source_type = 'REF_DATA' AND v_parent_column IS NULL THEN
            v_sql := format(
                'SELECT COALESCE(jsonb_agg(jsonb_build_object('
                || '''value'', src.%1$I::text, ''label'', src.%2$I::text) '
                || 'ORDER BY src.%3$I, src.%2$I), ''[]''::jsonb) '
                || 'FROM solar_app.ref_data src '
                || 'JOIN solar_app.ref_data_categories cat '
                || 'ON cat.category_id = src.category_id '
                || 'WHERE cat.category_code = $1 '
                || 'AND cat.active_ind IS TRUE '
                || 'AND src.active_ind IS TRUE',
                v_value_column,
                v_label_column,
                v_sort_column
            );
            EXECUTE v_sql INTO v_options USING v_category_code;
        ELSIF v_source_type = 'REF_DATA' THEN
            v_sql := format(
                'SELECT COALESCE(jsonb_agg(jsonb_build_object('
                || '''value'', src.%1$I::text, ''label'', src.%2$I::text) '
                || 'ORDER BY src.%3$I, src.%2$I), ''[]''::jsonb) '
                || 'FROM solar_app.ref_data src '
                || 'JOIN solar_app.ref_data_categories cat '
                || 'ON cat.category_id = src.category_id '
                || 'WHERE cat.category_code = $1 '
                || 'AND cat.active_ind IS TRUE '
                || 'AND src.active_ind IS TRUE '
                || 'AND (src.%4$I = $2::%5$s OR ($3::boolean AND src.%4$I IS NULL))',
                v_value_column,
                v_label_column,
                v_sort_column,
                v_parent_column,
                v_cast_type
            );
            EXECUTE v_sql INTO v_options
                USING v_category_code, v_parent_text, v_include_null;
        ELSIF v_parent_column IS NULL THEN
            v_sql := format(
                'SELECT COALESCE(jsonb_agg(jsonb_build_object('
                || '''value'', src.%1$I::text, ''label'', src.%2$I::text) '
                || 'ORDER BY src.%3$I, src.%2$I), ''[]''::jsonb) '
                || 'FROM solar_app.%4$I src '
                || 'WHERE src.active_ind IS TRUE',
                v_value_column,
                v_label_column,
                v_sort_column,
                v_source_table
            );
            EXECUTE v_sql INTO v_options;
        ELSE
            v_sql := format(
                'SELECT COALESCE(jsonb_agg(jsonb_build_object('
                || '''value'', src.%1$I::text, ''label'', src.%2$I::text) '
                || 'ORDER BY src.%3$I, src.%2$I), ''[]''::jsonb) '
                || 'FROM solar_app.%4$I src '
                || 'WHERE src.active_ind IS TRUE '
                || 'AND (src.%5$I = $1::%6$s OR ($2::boolean AND src.%5$I IS NULL))',
                v_value_column,
                v_label_column,
                v_sort_column,
                v_source_table,
                v_parent_column,
                v_cast_type
            );
            EXECUTE v_sql INTO v_options USING v_parent_text, v_include_null;
        END IF;

        IF v_options = '[]'::JSONB THEN
            v_message := 'No dropdown options found';
        END IF;

        v_data := jsonb_build_object(
            'dropdown_code', v_dropdown_code,
            'cache_ttl_seconds', v_cache_ttl,
            'options', v_options
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Dropdown options could not be loaded';
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

    -- Keep only the fields this function reads. Extra client keys are not
    -- written to the audit log.
    IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
        v_log_payload := NULL;
    ELSE
        v_log_payload := jsonb_strip_nulls(jsonb_build_object(
            'api_endpoint', p_payload->>'api_endpoint',
            'logged_in_user_id', p_payload->>'logged_in_user_id',
            'dropdown_code', p_payload->>'dropdown_code',
            'parent_value', p_payload->>'parent_value'
        ));
    END IF;

    BEGIN
        INSERT INTO solar_app.log_sql_functions (
            api_endpoint,
            function_name,
            logged_in_user_id,
            request_payload,
            execution_status,
            error_message,
            sql_state,
            execution_time_ms,
            created_by,
            updated_by
        ) VALUES (
            v_api_endpoint,
            'fn_get_dropdown_data',
            v_logged_in_user,
            v_log_payload,
            CASE WHEN v_status = 'SUCCESS' THEN 'SUCCESS' ELSE 'ERROR' END,
            v_log_error,
            v_sql_state,
            GREATEST(
                0,
                FLOOR(EXTRACT(EPOCH FROM (clock_timestamp() - v_started)) * 1000)
            )::INTEGER,
            v_logged_in_user,
            v_logged_in_user
        );
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END;

    RETURN v_response;
END;
$$;

COMMENT ON FUNCTION solar_app.fn_get_dropdown_data(JSONB) IS
    'Returns active dropdown options for one allowlisted ref_dropdown_config code. Parent filters are bound parameters. Client text is never executed as SQL.';
