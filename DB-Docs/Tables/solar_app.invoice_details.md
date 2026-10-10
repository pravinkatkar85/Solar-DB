# Table: `solar_app.invoice_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Offline bill header transcribed by admin. Not a payment gateway or electronic tax-invoice integration. Customers may view only.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `invoice_id` | `bigint` | NO | `` | Surrogate primary key. |
| `invoice_no` | `character varying(40)` | NO | `` | Offline bill number (manual or generated). Unique. |
| `customer_id` | `bigint` | NO | `` | Customer this bill is recorded against. |
| `site_id` | `bigint` | YES | `` | Optional site. |
| `related_order_id` | `bigint` | YES | `` | Optional fulfilment order; FK added after order_details exists. |
| `invoice_category_ref_data_id` | `bigint` | NO | `` | FK to INVOICE_CATEGORIES (installation, AMC, spares, cleaning). |
| `invoice_status_ref_data_id` | `bigint` | NO | `` | FK to INVOICE_STATUSES (draft, unpaid, partial, paid, cancelled). |
| `invoice_date` | `date` | NO | `` | Bill date as transcribed by admin. |
| `currency_code` | `character(3)` | NO | `` | Currency snapshot for every invoice, line, tax, and balance amount. |
| `taxable_amount` | `numeric(14,2)` | NO | `0` | Total taxable base transcribed or calculated for this invoice. |
| `tax_amount` | `numeric(14,2)` | NO | `0` | Total of generic component snapshots in invoice_tax_details. |
| `total_amount` | `numeric(14,2)` | NO | `` | Total amount on the paper/bank bill. |
| `paid_amount` | `numeric(14,2)` | NO | `0` | Running sum of offline receipts; maintained in functions. |
| `balance_amount` | `numeric(14,2)` | NO | `0` | total_amount minus paid_amount; maintained in functions. |
| `related_amc_contract_id` | `bigint` | YES | `` | Optional AMC this bill covers. |
| `related_service_request_id` | `bigint` | YES | `` | Optional service visit this bill covers. |
| `related_spare_part_request_id` | `bigint` | YES | `` | Optional spare-part request this bill covers. |
| `remarks` | `character varying(500)` | YES | `` | Admin transcription notes. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
