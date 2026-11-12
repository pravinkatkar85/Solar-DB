# solar_app.fn_update_payment_details

Admin updates one offline payment and recalculates the parent invoice balances/status.

Session identity and `ROLE_ADMIN` come only from `jwt_token_hash` → `log_user_sessions`. Client-supplied invoice totals/paid/balance/invoice status and `is_offline_ind` are not trusted. `invoice_id` / `customer_id` cannot change.

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | 1–255 characters |
| `jwt_token_hash` | yes | 64-char hex |
| `payment_id` | yes | Existing payment |
| `amount` | no | `> 0`; overpayment rejected after recalc |
| `payment_method_code` | no | Same allowlist as create |
| `paid_on` | no | Date |
| `instrument_ref` | no | Max 100; empty clears |
| `remarks` | no | Max 500; empty clears |
| `payment_status_code` | no | `PAY_RECORDED` or `PAY_CANCELLED` |
| `currency_code` | no | Must match invoice if supplied |
| `active_ind` | no | Soft-delete; inactive rows excluded from paid sum |

## Recalculation

Same rules as create: sum active `PAY_RECORDED` amounts → invoice paid/balance/status. When no active recorded payment remains, status becomes `INV_UNPAID`. Invoice row locked with `FOR UPDATE`.

## Codes

- 200 updated
- 400 validation
- 401 authentication required
- 403 not an active admin
- 404 payment not found
- 409 overpayment / ownership conflict
- 500 unexpected / notification failure

On success enqueues `NTF_BILLING_UPDATE` (`related_entity_type` `PAYMENT`).

Source: `DB-Objects/SQLFunctions/solar_app.fn_update_payment_details.sql`. Loader line in `SQLScripts/02_functions.sql`. Do not install until approved.
