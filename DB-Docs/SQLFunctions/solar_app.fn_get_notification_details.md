# solar_app.fn_get_notification_details

Lists active inbox notifications for the authenticated session user. Client-supplied `recipient_user_id` / `user_id` values are rejected when they do not match the session.

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | 1–255 characters |
| `jwt_token_hash` | yes | Active session hash |

## Data

```json
{
  "unread_count": 1,
  "notifications": [
    {
      "notification_id": "1",
      "notification_type_code": "NTF_KYC_STATUS",
      "notification_type_name": "KYC reviewed",
      "title": "KYC reviewed",
      "body": "Your document was approved.",
      "payload_json": { "entity_type": "KYC", "entity_id": "12" },
      "related_entity_type": "KYC",
      "related_entity_id": "12",
      "is_read_ind": false,
      "read_on": null,
      "created_on": "2026-11-11T12:00:00Z"
    }
  ]
}
```

## Codes

- 200 loaded
- 400 validation
- 401 authentication is required
- 403 inactive / suspended
- 500 unexpected failure

Source: `DB-Objects/SQLFunctions/solar_app.fn_get_notification_details.sql`. Do not install until approved.
