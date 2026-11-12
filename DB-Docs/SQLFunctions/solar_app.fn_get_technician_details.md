# solar_app.fn_get_technician_details

Admin lists technician profiles from `technician_details` joined to `user_details`.

Session identity and role come only from `jwt_token_hash` → `log_user_sessions` → `user_details`. Payload role, `logged_in_user_id`, and ownership fields are not trusted. `ROLE_ADMIN` is required.

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | 1–255 characters |
| `jwt_token_hash` | yes | 64-char hex of the admin session JWT |
| `logged_in_user_id` / `user_id` | no | If present must match session user id |
| `active_ind` | no | Boolean filter on `technician_details.active_ind` |
| `is_available` | no | Boolean filter on `technician_details.is_available` |

## Codes

- 200 list loaded (empty list is success)
- 400 validation
- 401 authentication required / invalid session
- 403 not an active admin
- 500 unexpected failure

## Response `data` (200)

`technicians` array of objects with:

- `technician_id`
- `user_id`
- `employee_code`
- `full_name` (schema-backed display name)
- `mobile_e164` (schema-backed mobile)
- `active_ind`
- `is_available`

Never returns `pin_hash`, PIN, OTP, or session tokens.

Source: `DB-Objects/SQLFunctions/solar_app.fn_get_technician_details.sql`. Loader line in `SQLScripts/02_functions.sql`. Do not install until approved.
