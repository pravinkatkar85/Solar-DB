# solar_app.fn_get_job_assignment_details

Lists active jobs for the signed-in technician, or returns one owned job detail with checklist template rows, media, and sign-off.

Session identity and role come only from `jwt_token_hash` → `log_user_sessions` → `user_details`. Payload `technician_id` and ownership fields are not trusted. `ROLE_TECHNICIAN` and an active `technician_details` row for the session user are required.

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | 1–255 characters |
| `jwt_token_hash` | yes | 64-char hex of the technician session JWT |
| `logged_in_user_id` / `user_id` | no | If present must match session user id |
| `job_id` | no | When present, returns detail for that owned job |

## Codes

- 200 list or detail
- 400 validation
- 401 authentication required / invalid session
- 403 not an active technician
- 404 job not found / not owned
- 500 unexpected failure

## Response `data` (200)

- List: `technician_id`, `jobs` array (id, type, status, site, parents, schedule).
- Detail: job fields plus `checklist`, `media`, `signoff`. Checklist templates come from `ref_checklist_items` for the job’s `job_type` (no `SITE_VISIT` templates in seed).

Source: `DB-Objects/SQLFunctions/solar_app.fn_get_job_assignment_details.sql`. Loader line in `SQLScripts/02_functions.sql`. Do not install until approved.
