# solar_app.fn_get_payment_details

Lists or returns offline payments.

Session identity comes only from `jwt_token_hash` → `log_user_sessions`.

- `ROLE_ADMIN`: all payments; optional filters
- Customer (active `customer_details` for session user): only that customer’s payments; mismatched `customer_id` → 403

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | 1–255 characters |
| `jwt_token_hash` | yes | 64-char hex |
| `payment_id` | no | Detail for one payment |
| `invoice_id` | no | Filter |
| `customer_id` | no | Admin filter; customer ownership enforced |
| `payment_status_code` | no | e.g. `PAY_RECORDED` |
| `active_ind` | no | Boolean filter |

## Codes

- 200 success (empty `payments` array valid)
- 400 validation
- 401 authentication required
- 403 cannot view / ownership mismatch
- 404 payment not found (or not visible)
- 500 unexpected failure

## Response `data` (200)

- Detail: `{ "payment": { ... } }`
- List: `{ "payments": [ ... ] }`

Includes method/status codes, amounts, instrument, paid_on, invoice_id, customer_id. No gateway fields.

Source: `DB-Objects/SQLFunctions/solar_app.fn_get_payment_details.sql`. Loader line in `SQLScripts/02_functions.sql`. Do not install until approved.
