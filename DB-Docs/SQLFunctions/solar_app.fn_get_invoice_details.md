# solar_app.fn_get_invoice_details

Lists or returns offline invoices with active line items and tax snapshots.

Session identity and role come only from `jwt_token_hash` → `log_user_sessions` → `user_details`. Payload role and ownership fields are not trusted.

- `ROLE_ADMIN`: may list all invoices; optional `customer_id` filter; optional `invoice_id` detail; optional `active_ind` filter.
- Customer (session user with an active `customer_details` row): only that customer’s invoices. By default customers do not see `INV_DRAFT`, `INV_CANCELLED`, or inactive invoices (list or detail). Mismatched `customer_id` returns 403.

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | 1–255 characters |
| `jwt_token_hash` | yes | 64-char hex |
| `invoice_id` | no | Detail for one invoice |
| `customer_id` | no | Admin filter only |
| `active_ind` | no | Boolean filter on invoice header |

## Codes

- 200 success (empty `invoices` array is valid)
- 400 validation
- 401 authentication required
- 403 account cannot view / customer ownership mismatch
- 404 invoice not found (or not visible to caller)
- 500 unexpected failure

## Response `data` (200)

- Detail (`invoice_id` supplied): `{ "invoice": { ...header..., "lines": [...], "tax_snapshots": [...] } }`
- List: `{ "invoices": [ { ...header..., "lines": [...], "tax_snapshots": [...] }, ... ] }`

Never returns payment gateway fields. `paid_amount` / `balance_amount` are SQL-maintained values only.

Source: `DB-Objects/SQLFunctions/solar_app.fn_get_invoice_details.sql`. Loader line in `SQLScripts/02_functions.sql`. Do not install until approved.
