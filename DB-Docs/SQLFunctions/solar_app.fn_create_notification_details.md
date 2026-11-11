# solar_app.fn_create_notification_details

Enqueue one in-app inbox row and optional push `PENDING` delivery log rows. Called from other business `fn_*` after a successful domain change. **No triggers.** Not exposed as a public API route.

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | 1–255 characters |
| `logged_in_user_id` | no | Actor for audit; blank becomes `SYSTEM` |
| `recipient_user_id` | yes | Target `user_details.user_id` |
| `notification_type_code` | yes | Active `NOTIFICATION_TYPES` code (e.g. `NTF_KYC_STATUS`) |
| `title` | no | Defaults to type display name; max 200 |
| `body` | yes | Max 1000 |
| `payload_json` | no | JSON object deep-link; defaults `{}` |
| `related_entity_type` | with id | Must match `notification_details` check allowlist |
| `related_entity_id` | with type | Digits only |

Inactive or suspended recipients return **403** and no inbox row. Push delivery rows are created only when `push_notifications_enabled` is true and the recipient has active sessions with a non-empty `push_token`.

## Codes

- 200 created
- 400 validation
- 403 recipient cannot receive notifications
- 500 unexpected failure

Source: `DB-Objects/SQLFunctions/solar_app.fn_create_notification_details.sql`. Do not install until approved.
