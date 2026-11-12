# solar_app.fn_create_technician_details

Admin creates one technician login (`user_details`) and the required 1:1 `technician_details` row.

Session identity and role come only from `jwt_token_hash` → `log_user_sessions` → `user_details`. Payload role, `technician_id`, `logged_in_user_id`, and ownership fields are not trusted. `ROLE_ADMIN` is required.

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | 1–255 characters |
| `jwt_token_hash` | yes | 64-char hex of the admin session JWT |
| `logged_in_user_id` / `user_id` | no | If present must match session user id |
| `country_id` | yes | Active `ref_countries.country_id` |
| `national_number` | yes | Digits; length/regex from that country |
| `full_name` | yes | 1–150 characters |
| `employee_code` | yes | 1–30 characters; unique |
| `email` | no | Max 150 |
| `service_radius_km` | no | `>= 0` |
| `is_available` | no | Default `true` |
| `pin` / `pin_hash` | forbidden | Must be absent or blank |

## Fixed server values

- Role `ROLE_TECHNICIAN`
- Account `ACCT_ACTIVE`
- `admin_registered = TRUE`
- Registration source `REG_ADMIN_POST_INSTALL`
- `pin_hash = NULL`

## Codes

- 200 created
- 400 validation (including forbidden PIN)
- 401 authentication required / invalid session
- 403 not an active admin
- 409 duplicate mobile or employee code
- 500 unexpected failure / missing reference data

## Response `data` (200)

`technician_id`, `user_id`, `employee_code`, `mobile_e164`, `full_name`, `is_available`, `admin_registered`, `role_code`.

Source: `DB-Objects/SQLFunctions/solar_app.fn_create_technician_details.sql`. Loader line in `SQLScripts/02_functions.sql`. Do not install until approved.
