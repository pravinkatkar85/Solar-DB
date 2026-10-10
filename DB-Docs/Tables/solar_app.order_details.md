# Table: `solar_app.order_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Commercial fulfilment order through installation (Path A) or already-commissioned (Path B). Distinct from bills and equipment.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `order_id` | `bigint` | NO | `` | Surrogate primary key. |
| `order_no` | `character varying(30)` | NO | `` | Human-readable unique order number. |
| `order_source` | `character varying(20)` | NO | `` | QUOTE, ENQUIRY, LEAD, or MANUAL (Path B / admin). |
| `customer_id` | `bigint` | NO | `` | Fulfilment customer. |
| `site_id` | `bigint` | YES | `` | Install site when known. |
| `user_id` | `bigint` | YES | `` | End user who originated demand, if any. |
| `quote_id` | `bigint` | YES | `` | Accepted quote, if any. |
| `product_enquiry_id` | `bigint` | YES | `` | Source catalogue enquiry, if any. |
| `lead_id` | `bigint` | YES | `` | Source lead, if any. |
| `order_status_ref_data_id` | `bigint` | NO | `` | FK to ORDER_STATUSES through installation/commissioning. |
| `assigned_admin_user_id` | `bigint` | YES | `` | Back-office owner. |
| `gross_amount` | `numeric(14,2)` | NO | `0` | Sum of lines as computed in functions. |
| `currency_code` | `character(3)` | NO | `` | Currency snapshot for order amounts and lines. |
| `remarks` | `character varying(500)` | YES | `` | Admin notes. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
