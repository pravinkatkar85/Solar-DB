# solar_app.fn_update_technician_details

Admin updates one technician profile, availability, or activation.

Session identity and role come only from `jwt_token_hash` → `log_user_sessions` → `user_details`. Payload role and ownership fields are not trusted. `ROLE_ADMIN` is required.

Soft-deactivation (`active_ind = false`) updates both `technician_details.active_ind` and the linked `user_details.active_ind`. Reactivation sets both back to `true`. Availability uses `technician_details.is_available` and hides the technician from new job allocation when `false`.

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | 1–255 characters |
| `jwt_token_hash` | yes | 64-char hex of the admin session JWT |
| `logged_in_user_id` / `user_id` | no | If present must match session user id |
| `technician_id` | yes | Existing technician with `ROLE_TECHNICIAN` |
| `full_name` | no | 1–150 when supplied |
| `email` | no | Max 150; blank clears |
| `employee_code` | no | 1–30; unique among technicians |
| `service_radius_km` | no | `>= 0`, or null to clear |
| `is_available` | no | Boolean |
| `active_ind` | no | Boolean activation flag |

At least one updatable field must be present.

## Codes

- 200 updated
- 400 validation / no fields
- 401 authentication required / invalid session
- 403 not an active admin
- 404 technician not found
- 409 duplicate employee code
- 500 unexpected failure

## Response `data` (200)

`technician_id`, `user_id`, `employee_code`, `full_name`, `email`, `service_radius_km`, `is_available`, `active_ind`, `user_active_ind`.

Source: `DB-Objects/SQLFunctions/solar_app.fn_update_technician_details.sql`. Loader line in `SQLScripts/02_functions.sql`. Do not install until approved.
