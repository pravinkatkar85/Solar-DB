# solar_app.fn_get_product_details

`solar_app.fn_get_product_details(p_payload JSONB) RETURNS JSONB`

Public read. No session and no `admin_registered` check.

- Without `product_id`: `data.products` contains active rows where `is_published` is true, ordered by `sort_order`, then name. Optional `category_ref_data_id` filters that list.
- With `product_id`: `data` is that published product, including `specs_json` and active `media`. A missing, inactive, or unpublished product returns 404 `This product is not available`.
- `api_endpoint` is required. Codes: 200, 400, 404, 500.
