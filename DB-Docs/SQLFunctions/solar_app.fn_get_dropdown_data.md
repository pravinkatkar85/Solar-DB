# Function: `solar_app.fn_get_dropdown_data(p_payload JSONB)`

- Schema: `solar_app`
- Source: `DB-Objects/SQLFunctions/solar_app.fn_get_dropdown_data.sql`
- Loader: `SQLScripts/02_functions.sql`
- Tests: `SQLScripts/05_test_fn_get_dropdown_data.sql`
- Language: `plpgsql`
- Return type: `JSONB`
- Status: deployed. The API calls it from `POST /api/dropdowns` and does not send `logged_in_user_id`, so this function applies `SYSTEM`.

`DB-Objects/Functions/` and `DB-Docs/Functions/` are generated from the live database. This document is the maintained contract. It is not replaced by `scripts/export_db_objects.mjs`.

## Purpose

Return the active options for one dropdown code configured in `solar_app.ref_dropdown_config`. Flutter dropdowns use this single function. The caller supplies a dropdown code and, for a cascading list, the selected parent value. The function never executes table names, column names, or SQL text received from the client.

## Input

One JSON object:

| Field | Required | Rule |
| --- | --- | --- |
| `api_endpoint` | yes | String, 1 to 255 characters |
| `logged_in_user_id` | no | String up to 50 characters. Omitted or blank becomes `SYSTEM` |
| `dropdown_code` | yes | String matching `^[A-Z][A-Z0-9_]{0,49}$`, then looked up in active `ref_dropdown_config` |
| `parent_value` | when the config has `parent_filter_column` | String or number. Integer parent columns accept digits only |

```json
{
  "api_endpoint": "/api/dropdowns",
  "logged_in_user_id": "DEV_TEST",
  "dropdown_code": "STATES",
  "parent_value": "1"
}
```

`parent_value` for `STATES` must be the selected `country_id`. Resolve that id from `country_code` in the caller. Do not assume an identity value.

## Output

Every response has `status`, `code`, `message`, and `data`.

| Case | `status` | `code` | `data` |
| --- | --- | --- | --- |
| Options found | `SUCCESS` | 200 | Object below |
| No matching rows | `SUCCESS` | 200 | Same object with `options: []` |
| Invalid payload, code, or parent value | `ERROR` | 400 | `null` |
| Unknown or inactive dropdown code | `ERROR` | 404 | `null` |
| Config fails the allowlist | `ERROR` | 500 | `null` |
| Unexpected database error | `ERROR` | 500 | `null` |

Success `data`:

```json
{
  "dropdown_code": "USER_ROLES",
  "cache_ttl_seconds": 3600,
  "options": [
    {"value": "1", "label": "End Customer"}
  ]
}
```

`value` and `label` are text. For the current seed, `REF_DATA` options use `ref_data_id` and `data_value`. Table options use the configured id and label columns, such as `state_id` and `state_name`.

Client messages are fixed. `SQLERRM` is written only to `log_sql_functions.error_message`.

## Allowlist

- `REF_DATA` reads `ref_data` joined to `ref_data_categories` for the configured `category_code`. Value, label, and sort columns must be in the fixed column list in the function.
- `TABLE` reads only an existing `solar_app.ref_*` table. Configured columns must exist, and the table must have `active_ind`.
- Identifiers are quoted with `format('%I')`. Parent values are bound with `USING`.
- Rows with `active_ind = FALSE` are omitted. An inactive config row returns 404.
- When `parent_filter_column` is set and `parent_value` is missing, the function returns 400. The schema does not define another behavior.
- `include_null_parent = TRUE` also returns rows whose parent filter column is NULL. `DISCOMS_BY_DISTRICT` therefore includes every statewide DISCOM, including other states, because the config filters only `district_id`.

## Logging

`fn_log_function_execution` does not exist. This function inserts one row into `solar_app.log_sql_functions`. The stored payload keeps `api_endpoint`, `logged_in_user_id`, `dropdown_code`, and `parent_value`. A failure of that insert does not replace the JSON response. `log_api_execution` remains the API layer's audit.

## Not implemented

`DB-Design.md` mentions `ref_dropdown_config.extra_where_sql`. That column is not in `01_schema.sql`, so no extra predicate is applied.

## Related objects

- `solar_app.ref_dropdown_config`
- `solar_app.ref_data` and `solar_app.ref_data_categories`
- `solar_app.ref_countries`, `ref_states`, `ref_districts`, `ref_cities`, `ref_pincodes`, `ref_discoms`, `ref_amc_plans`, `ref_office_locations`
- `solar_app.log_sql_functions`
