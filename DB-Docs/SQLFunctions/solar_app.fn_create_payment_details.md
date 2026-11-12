# solar_app.fn_create_payment_details

Admin records one offline payment against an existing invoice and recalculates invoice `paid_amount`, `balance_amount`, and status.

Session identity and `ROLE_ADMIN` come only from `jwt_token_hash` → `log_user_sessions` → `user_details`. Client-supplied invoice totals, `paid_amount`, `balance_amount`, invoice status, and `is_offline_ind` are not trusted. `is_offline_ind` is always `TRUE`.

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | 1–255 characters |
| `jwt_token_hash` | yes | 64-char hex |
| `invoice_id` | yes | Active invoice; not `INV_DRAFT` or `INV_CANCELLED` |
| `amount` | yes | `> 0`; must not make recorded payments exceed invoice `total_amount` |
| `payment_method_code` | yes | `PAY_CASH`, `PAY_CHEQUE`, `PAY_NEFT`, `PAY_UPI_OFFLINE`, `PAY_OTHER` |
| `paid_on` | yes | `YYYY-MM-DD` |
| `currency_code` | no | If present must match invoice currency |
| `customer_id` | no | If present must match invoice customer |
| `instrument_ref` | no | Max 100 |
| `remarks` | no | Max 500 |
| `payment_status_code` | no | Only `PAY_RECORDED` (default) |

## Invoice recalculation

After insert, with invoice row locked:

- `paid_amount` = sum of active `PAY_RECORDED` payments
- `balance_amount` = `total_amount - paid_amount`
- status: `0` → `INV_UNPAID`; `0 < paid < total` → `INV_PARTIAL`; `paid = total` → `INV_PAID`

Overpayment is rejected (`409`). No gateway fields.

## Codes

- 200 created
- 400 validation
- 401 authentication required
- 403 not an active admin
- 404 invoice not found
- 409 overpayment / cancelled invoice conflict
- 500 unexpected / notification failure (work rolled back)

On success enqueues `NTF_BILLING_UPDATE` for the invoice customer (`related_entity_type` `PAYMENT`).

Source: `DB-Objects/SQLFunctions/solar_app.fn_create_payment_details.sql`. Loader line in `SQLScripts/02_functions.sql`. Do not install until approved.
