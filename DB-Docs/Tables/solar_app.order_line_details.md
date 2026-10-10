# Table: `solar_app.order_line_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Order line: catalogue product and/or free-text kit description.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `order_line_id` | `bigint` | NO | `` | Surrogate primary key. |
| `order_id` | `bigint` | NO | `` | Parent order. |
| `line_no` | `integer` | NO | `` | Line sequence unique per order. |
| `product_id` | `bigint` | YES | `` | Optional catalogue SKU. |
| `line_desc` | `character varying(255)` | NO | `` | Line description (required even when product_id is set). |
| `tax_classification_code` | `character varying(30)` | YES | `` | Optional country-specific tax classification code snapshot. |
| `quantity` | `numeric(12,3)` | NO | `1` | Quantity (must be > 0). |
| `unit_rate` | `numeric(12,2)` | NO | `0` | Rate per unit. |
| `line_amount` | `numeric(14,2)` | NO | `` | Line amount. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
