# solar_app.fn_update_notification_details

Mark one or all inbox rows read for the authenticated session user only.

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | 1–255 characters |
| `jwt_token_hash` | yes | Active session hash |
| `action` | yes | `MARK_READ` or `MARK_ALL_READ` |
| `notification_id` | when `MARK_READ` | Must belong to the session user |

## Codes

- 200 updated
- 400 validation
- 401 authentication is required
- 403 inactive / suspended
- 404 notification not found (or not owned)
- 500 unexpected failure

Source: `DB-Objects/SQLFunctions/solar_app.fn_update_notification_details.sql`. Do not install until approved.
