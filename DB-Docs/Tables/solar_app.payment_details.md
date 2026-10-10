# Table: `solar_app.payment_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Offline payment/receipt register. is_offline_ind is TRUE in v1; no in-app checkout.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `payment_id` | `bigint` | NO | `` | Surrogate primary key. |
| `invoice_id` | `bigint` | NO | `` | Offline bill this receipt is applied to. |
| `customer_id` | `bigint` | NO | `` | Paying customer (denormalized for queries). |
| `amount` | `numeric(14,2)` | NO | `` | Amount received outside the app. |
| `currency_code` | `character(3)` | NO | `` | Currency snapshot for amount; it must match the associated invoice under transaction validation. |
| `payment_method_ref_data_id` | `bigint` | NO | `` | FK to PAYMENT_METHODS (cash, cheque, NEFT, UPI-offline, other). |
| `payment_status_ref_data_id` | `bigint` | NO | `` | FK to PAYMENT_STATUSES (recorded, cancelled). |
| `is_offline_ind` | `boolean` | NO | `true` | Always TRUE in v1. There is no in-app payment gateway. |
| `instrument_ref` | `character varying(100)` | YES | `` | Cheque number, UTR, or paper receipt number. |
| `paid_on` | `date` | NO | `` | Date money was collected offline. |
| `remarks` | `character varying(500)` | YES | `` | Admin notes. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
