# solar_app.fn_update_invoice_details

Admin updates one offline invoice header and optionally replaces line items and/or tax snapshots.

Session identity and role come only from `jwt_token_hash` → `log_user_sessions` → `user_details`. Payload role, `paid_amount`, and `balance_amount` are not trusted. `ROLE_ADMIN` is required.

After amounts are applied, invoice status is synchronized from `paid_amount` / `total_amount` (`INV_UNPAID` / `INV_PARTIAL` / `INV_PAID`), except `INV_DRAFT` (only when paid is zero) and `INV_CANCELLED` (only when no payment history exists). `currency_code` cannot change once any `payment_details` row exists for the invoice (including cancelled).

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | 1–255 characters |
| `jwt_token_hash` | yes | 64-char hex |
| `invoice_id` | yes | Existing invoice |
| Header fields | no | Same shapes as create when present: `invoice_no`, `invoice_date`, `currency_code` (blocked once payment history exists), `invoice_category_code`, `invoice_status_code` (client may send `INV_DRAFT`/`INV_UNPAID`/`INV_CANCELLED` only; money statuses are derived), amounts, links, `remarks` |
| `lines` | no | If present, soft-deactivates existing lines and inserts the new set |
| `tax_snapshots` | no | If present, soft-deactivates existing tax rows and inserts the new set |
| `paid_amount` / `balance_amount` | ignored | `paid_amount` unchanged; `balance_amount` recomputed as `total_amount - paid_amount` |

## Payment relationship guards

If any `payment_details` row exists for the invoice (including cancelled) or `paid_amount > 0`:

- `customer_id` cannot change
- `total_amount` cannot be set below `paid_amount`
- `invoice_status_code` cannot be set to `INV_CANCELLED`
- `active_ind` cannot be set to `false`
- `currency_code` cannot change

`INV_PARTIAL` / `INV_PAID` are never accepted from the client; they are derived from paid/total after update.

## Codes

- 200 updated
- 400 validation
- 401 authentication required
- 403 not an active admin
- 404 invoice or linked entity not found
- 409 duplicate `invoice_no` or payment-relationship conflict
- 500 unexpected failure / notification enqueue failure

On success enqueues `NTF_BILLING_UPDATE` to the owning customer.

Source: `DB-Objects/SQLFunctions/solar_app.fn_update_invoice_details.sql`. Loader line in `SQLScripts/02_functions.sql`. Do not install until approved.
