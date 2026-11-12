# solar_app.fn_create_invoice_details

Admin creates one offline invoice header, optional line items, and optional transcribed tax snapshots.

Session identity and role come only from `jwt_token_hash` → `log_user_sessions` → `user_details`. Payload role, `paid_amount`, `balance_amount`, and payment-derived statuses are not trusted. `ROLE_ADMIN` is required.

Tax is transcription-only: snapshots are stored as supplied. `source_tax_rule_id` is always NULL. No GST calculation and no use of unapproved `ref_tax_rules`.

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | 1–255 characters |
| `jwt_token_hash` | yes | 64-char hex of the admin session JWT |
| `logged_in_user_id` / `user_id` | no | If present must match session user id |
| `invoice_no` | yes | Manual bill number; 1–40; unique |
| `customer_id` | yes | Active customer |
| `invoice_date` | yes | `YYYY-MM-DD` |
| `currency_code` | yes | Active `ref_currencies.currency_code` |
| `invoice_category_code` | yes | `INVOICE_CATEGORIES` code (`INV_INSTALL`, `INV_AMC`, `INV_SPARE`, `INV_CLEANING`) |
| `invoice_status_code` | no | Only `INV_DRAFT` or `INV_UNPAID` (default `INV_UNPAID`) |
| `taxable_amount` | no | Default `0`; `>= 0` |
| `tax_amount` | no | Default `0`; `>= 0` |
| `total_amount` | yes | `>= 0` |
| `site_id` | no | Must belong to `customer_id` |
| `related_order_id` | no | Must belong to `customer_id` |
| `related_amc_contract_id` | no | AMC site must belong to `customer_id` |
| `related_service_request_id` | no | Must belong to `customer_id` |
| `related_spare_part_request_id` | no | Job site must belong to `customer_id` |
| `remarks` | no | Max 500 |
| `lines` | no | JSON array of line objects |
| `tax_snapshots` | no | JSON array of tax snapshot objects |
| `paid_amount` / `balance_amount` | ignored | Always `0` / `total_amount` |

### Line object

| Field | Required | Notes |
| --- | --- | --- |
| `line_no` | yes | Positive integer; unique within payload |
| `line_desc` | yes | 1–255 |
| `quantity` | no | Default `1`; `> 0` |
| `unit_rate` | no | Default `0` |
| `line_amount` | yes | |
| `tax_classification_code` | no | Max 30 |

### Tax snapshot object

| Field | Required | Notes |
| --- | --- | --- |
| `tax_group_code` | yes | Max 50 |
| `tax_component_code` | yes | Max 50 |
| `tax_display_name` | yes | Max 150 |
| `calculation_method` | yes | `PERCENTAGE` or `FIXED_AMOUNT` |
| `rate_percent` | if PERCENTAGE | 0–100; forbidden for FIXED_AMOUNT |
| `configured_rate_amount` | if FIXED_AMOUNT | `>= 0`; forbidden for PERCENTAGE |
| `taxable_amount` | yes | `>= 0` |
| `tax_amount` | yes | `>= 0` |
| `jurisdiction_json` | no | Object; default `{}` |
| `line_no` | no | Attach to a line created in the same request |

When `tax_snapshots` is present and non-empty, the sum of snapshot `tax_amount` must equal header `tax_amount`.

## Codes

- 200 created
- 400 validation
- 401 authentication required
- 403 not an active admin
- 404 linked entity not found for customer
- 409 duplicate `invoice_no`
- 500 unexpected failure / notification enqueue failure (work rolled back)

## Response `data` (200)

`invoice_id`, `invoice_no`, `customer_id`, `invoice_status_code`, `currency_code`, `taxable_amount`, `tax_amount`, `total_amount`, `paid_amount`, `balance_amount`, `notification_id`.

On success enqueues `NTF_BILLING_UPDATE` to the customer’s `user_id`.

Source: `DB-Objects/SQLFunctions/solar_app.fn_create_invoice_details.sql`. Loader line in `SQLScripts/02_functions.sql`. Do not install until approved.
