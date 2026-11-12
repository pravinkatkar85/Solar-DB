# solar_app.fn_update_job_assignment_details

Technician-owned job lifecycle: `ACCEPT`, `RESCHEDULE`, `START`, `COMPLETE`.

Session identity and role come only from `jwt_token_hash` → `log_user_sessions` → `user_details`. Payload `technician_id`, assigned user id, and ownership fields are not trusted. `ROLE_TECHNICIAN` is required. `JOB_REJECTED` is **not** implemented.

Does **not** create `site_visit_details` or `service_request_details` rows. Does **not** change `fn_update_site_visit_details` (customer completion).

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | 1–255 characters |
| `jwt_token_hash` | yes | 64-char hex of the technician session JWT |
| `action` | yes | `ACCEPT` \| `RESCHEDULE` \| `START` \| `COMPLETE` |
| `job_id` | yes | Must belong to the session technician |
| `accept_reject_reason` / `reason` | RESCHEDULE | 1–500 characters |
| `scheduled_on` | RESCHEDULE | `YYYY-MM-DD` |
| `checklist_responses` | COMPLETE | Array of response objects |
| `media` | COMPLETE | Array; must include `BEFORE` and `AFTER` |
| `signature` | COMPLETE | Object with `signature_url` |

### Checklist response object

| Field | Notes |
| --- | --- |
| `checklist_item_id` | Active `ref_checklist_items` for this `job_type` |
| `is_pass` | Required for mandatory `BOOLEAN` items |
| `measured_value` | Required for mandatory `NUMERIC` / `TEXT` items |
| `remarks` | Optional; max 500 |

### Media object

| Field | Notes |
| --- | --- |
| `media_purpose` | `BEFORE` \| `AFTER` \| `INVERTER_STATUS` \| `OTHER` |
| `file_url` | Required; max 500 |
| `captured_on` | Optional timestamptz |

## Status transitions

| Action | From | To | Parent sync |
| --- | --- | --- | --- |
| ACCEPT | `JOB_QUEUED`, `JOB_RESCHEDULED` | `JOB_ACCEPTED` | none |
| RESCHEDULE | `JOB_QUEUED`, `JOB_ACCEPTED`, `JOB_RESCHEDULED` | `JOB_RESCHEDULED` | updates linked visit `scheduled_on` when `site_visit_id` set |
| START | `JOB_ACCEPTED` | `JOB_IN_PROGRESS` | linked SR → `SR_IN_PROGRESS`; linked visit → `VISIT_IN_PROGRESS` |
| COMPLETE | `JOB_IN_PROGRESS` | `JOB_COMPLETED` | linked SR → `SR_COMPLETED`; linked visit → `VISIT_COMPLETED` |

## Completion rules

- All mandatory checklist items for the job’s `job_type` must be answered (`SITE_VISIT` has no seeded checklist templates).
- At least one `BEFORE` and one `AFTER` media row required.
- Signature `signature_url` required; one active sign-off stored.
- Notifications: `NTF_SERVICE_REQUEST` to customer on SR complete; `NTF_SITE_VISIT_DONE` to customer and active admins on visit complete. Failure rolls back.

## Codes

- 200 updated
- 400 validation (including missing reason / checklist / photos / signature)
- 401 authentication required / invalid session
- 403 not an active technician
- 404 job not found / not owned
- 409 illegal status transition or duplicate completion
- 500 unexpected failure / missing reference data / notification enqueue failure

Source: `DB-Objects/SQLFunctions/solar_app.fn_update_job_assignment_details.sql`. Loader line in `SQLScripts/02_functions.sql`. Do not install until approved.
