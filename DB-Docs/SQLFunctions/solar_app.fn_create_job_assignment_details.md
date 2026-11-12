# solar_app.fn_create_job_assignment_details

Admin assigns an existing active `SERVICE_REQUEST` or `SITE_VISIT` to an active available technician, creates `job_assignment_details` in `JOB_QUEUED`, and enqueues notifications through `fn_create_notification_details`.

Session identity and role come only from `jwt_token_hash` → `log_user_sessions` → `user_details`. Payload role, assigned user id, and ownership fields are not trusted. `ROLE_ADMIN` is required.

Phase 1 supports only `job_type` values `SERVICE_REQUEST` and `SITE_VISIT`. Complaint and commissioning assignment are out of scope.

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | 1–255 characters |
| `jwt_token_hash` | yes | 64-char hex of the admin session JWT |
| `logged_in_user_id` / `user_id` | no | If present must match session user id |
| `job_type` | yes | `SERVICE_REQUEST` or `SITE_VISIT` |
| `technician_id` | yes | Active, available `ROLE_TECHNICIAN` |
| `service_request_id` | when SR | Active SR in `SR_OPEN` or `SR_ASSIGNED` |
| `site_visit_id` | when visit | Active visit in `VISIT_SCHEDULED` or `VISIT_ASSIGNED` with a `site_id` |
| `scheduled_on` | conditional | `YYYY-MM-DD`; required for SR when `preferred_on` is null; defaults to SR `preferred_on` or visit `scheduled_on` |
| `sequence_no` | no | Non-negative integer route order |

## Side effects

- `SERVICE_REQUEST`: sets `technician_id`, status `SR_ASSIGNED`; creates job; notifies technician with `NTF_JOB_ASSIGNED` and `NTF_SERVICE_REQUEST`; notifies customer with `NTF_SERVICE_REQUEST` when the linked customer user can receive inbox rows.
- `SITE_VISIT`: sets `assigned_to_user_id` to the technician’s `user_id`, status `VISIT_ASSIGNED`; creates job; notifies technician with `NTF_JOB_ASSIGNED` and `NTF_SITE_VISIT_ASSIGNED`; notifies customer with `NTF_SITE_VISIT_ASSIGNED` when linked and eligible.
- Rejects inactive / unavailable / suspended technicians.
- Rejects duplicate active jobs for the same parent (`JOB_QUEUED`, `JOB_ACCEPTED`, `JOB_RESCHEDULED`, `JOB_IN_PROGRESS`).
- Notification enqueue failure raises inside the body block so parent updates and the job insert roll back.

## Codes

- 200 assigned
- 400 validation
- 401 authentication required / invalid session
- 403 not an active admin
- 404 technician / parent not found
- 409 inactive technician, invalid parent status, missing visit site, or duplicate active job
- 500 unexpected failure / missing reference data / notification enqueue failure

## Response `data` (200)

`job_id`, `job_type`, `job_status_code`, `technician_id`, `technician_user_id`, `site_id`, `service_request_id` or `site_visit_id`, `scheduled_on`, `sequence_no`, `notification_id` (`NTF_JOB_ASSIGNED`), `related_notification_ids`.

Source: `DB-Objects/SQLFunctions/solar_app.fn_create_job_assignment_details.sql`. Loader line in `SQLScripts/02_functions.sql`. Do not install until approved.
