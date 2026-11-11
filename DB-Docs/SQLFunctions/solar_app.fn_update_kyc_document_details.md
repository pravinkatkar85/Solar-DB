# solar_app.fn_update_kyc_document_details

Admin review of one active KYC document. Session user must have `ROLE_ADMIN`.

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `action` | yes | `APPROVE` or `REJECT` |
| `kyc_document_id` | yes | Active document |
| `rejection_comment` | when `REJECT` | Mandatory non-empty, max 500. Cleared on approve |

`APPROVE` sets `KYC_APPROVED`. `REJECT` sets `ACTION_REQUIRED` and stores the comment. `verified_by_user_id` is the admin session user.

When verification status **changes**, the function calls `fn_create_notification_details` with type `NTF_KYC_STATUS` for the owning customer's `user_id`. Rejection body includes the comment. Inactive/suspended customers skip inbox creation. A failed notification enqueue raises inside the body block so the KYC status update is rolled back. Same-status retries do not create another notification.

## Codes

- 200 updated
- 400 validation / missing reject comment
- 401 authentication is required
- 403 not admin / inactive
- 404 document not found
- 500 unexpected failure (including notification enqueue failure)

Source: `DB-Objects/SQLFunctions/solar_app.fn_update_kyc_document_details.sql`. Do not install until approved.
