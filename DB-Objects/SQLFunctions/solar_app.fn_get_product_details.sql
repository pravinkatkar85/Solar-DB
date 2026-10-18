-- Published catalogue list, or one published product with its active media.
-- No session is required. Draft and inactive products are omitted.
-- admin_registered is not read.

CREATE OR REPLACE FUNCTION solar_app.fn_get_product_details(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = pg_catalog, solar_app
AS $$
DECLARE
    v_started      TIMESTAMPTZ := clock_timestamp();
    v_api_endpoint VARCHAR(255);
    v_status       VARCHAR(20) := 'SUCCESS';
    v_code         INTEGER := 200;
    v_message      TEXT := 'Products loaded';
    v_data         JSONB := NULL;
    v_response     JSONB;
    v_log_error    TEXT;
    v_sql_state    VARCHAR(10);
    v_product_id   BIGINT;
    v_category_id  BIGINT;
    v_product_text TEXT;
    v_category_text TEXT;
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

        v_product_text := NULLIF(btrim(p_payload->>'product_id'), '');
        IF v_product_text IS NOT NULL AND v_product_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose a product';
            EXIT body;
        END IF;
        v_product_id := v_product_text::BIGINT;

        v_category_text := NULLIF(btrim(p_payload->>'category_ref_data_id'), '');
        IF v_category_text IS NOT NULL AND v_category_text !~ '^[0-9]{1,18}$' THEN
            v_status := 'ERROR';
            v_code := 400;
            v_message := 'Choose a category';
            EXIT body;
        END IF;
        v_category_id := v_category_text::BIGINT;

        IF v_product_id IS NOT NULL THEN
            SELECT jsonb_build_object(
                       'product_id', product.product_id::TEXT,
                       'product_code', product.product_code,
                       'product_name', product.product_name,
                       'category_name', category_row.data_value,
                       'short_description', product.short_description,
                       'long_description', product.long_description,
                       'specs_json', product.specs_json,
                       'list_price', product.list_price,
                       'currency_code', product.currency_code,
                       'tax_classification_code', product.tax_classification_code,
                       'thumbnail_url', product.thumbnail_url,
                       'media', COALESCE((
                           SELECT jsonb_agg(
                                      jsonb_build_object(
                                          'product_media_id', media.product_media_id::TEXT,
                                          'media_type', media.media_type,
                                          'file_url', media.file_url,
                                          'caption', media.caption,
                                          'sort_order', media.sort_order
                                      )
                                      ORDER BY media.sort_order, media.product_media_id
                                  )
                             FROM solar_app.product_media_details AS media
                            WHERE media.product_id = product.product_id
                              AND media.active_ind IS TRUE
                       ), '[]'::JSONB)
                   )
              INTO v_data
              FROM solar_app.product_details AS product
              JOIN solar_app.ref_data AS category_row
                ON category_row.ref_data_id = product.category_ref_data_id
             WHERE product.product_id = v_product_id
               AND product.active_ind IS TRUE
               AND product.is_published IS TRUE;

            IF v_data IS NULL THEN
                v_status := 'ERROR';
                v_code := 404;
                v_message := 'This product is not available';
                EXIT body;
            END IF;
            v_message := 'Product loaded';
        ELSE
            SELECT COALESCE(
                       jsonb_agg(
                           jsonb_build_object(
                               'product_id', product.product_id::TEXT,
                               'product_code', product.product_code,
                               'product_name', product.product_name,
                               'category_name', category_row.data_value,
                               'short_description', product.short_description,
                               'list_price', product.list_price,
                               'currency_code', product.currency_code,
                               'thumbnail_url', product.thumbnail_url,
                               'sort_order', product.sort_order
                           )
                           ORDER BY product.sort_order, product.product_name
                       ),
                       '[]'::JSONB
                   )
              INTO v_data
              FROM solar_app.product_details AS product
              JOIN solar_app.ref_data AS category_row
                ON category_row.ref_data_id = product.category_ref_data_id
             WHERE product.active_ind IS TRUE
               AND product.is_published IS TRUE
               AND (v_category_id IS NULL OR product.category_ref_data_id = v_category_id);
            v_data := jsonb_build_object('products', v_data);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            v_status := 'ERROR';
            v_code := 500;
            v_message := 'Products could not be loaded';
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
            api_endpoint, function_name, logged_in_user_id, request_payload,
            execution_status, error_message, sql_state, execution_time_ms,
            created_by, updated_by
        ) VALUES (
            v_api_endpoint,
            'fn_get_product_details',
            'SYSTEM',
            jsonb_strip_nulls(jsonb_build_object(
                'api_endpoint', v_api_endpoint,
                'product_id', v_product_id
            )),
            CASE WHEN v_status = 'SUCCESS' THEN 'SUCCESS' ELSE 'ERROR' END,
            v_log_error,
            v_sql_state,
            GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (clock_timestamp() - v_started)) * 1000))::INTEGER,
            'SYSTEM',
            'SYSTEM'
        );
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END;

    RETURN v_response;
END;
$$;

COMMENT ON FUNCTION solar_app.fn_get_product_details(JSONB) IS
    'Returns published active catalogue products, or one published product and its active media. No session is required.';
