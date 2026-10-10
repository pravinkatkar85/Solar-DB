# Table: `solar_app.amc_contract_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Sold AMC contract instance for a site. Expiry drives a renewal request, not in-app payment.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `amc_contract_id` | `bigint` | NO | `` | Surrogate primary key. |
| `site_id` | `bigint` | NO | `` | Site covered by this contract. |
| `amc_plan_id` | `bigint` | NO | `` | FK to ref_amc_plans catalogue. |
| `order_id` | `bigint` | YES | `` | Optional order this AMC was sold with. |
| `product_id` | `bigint` | YES | `` | Optional catalogue AMC/product SKU. |
| `invoice_id` | `bigint` | YES | `` | Optional offline bill for this contract; FK added after invoice_details exists. |
| `start_on` | `date` | NO | `` | Contract start date. |
| `expiry_on` | `date` | NO | `` | Contract end date; drives AMC expiry notifications. |
| `contract_status` | `character varying(20)` | NO | `'ACTIVE'::character varying` | ACTIVE, EXPIRED, or CANCELLED (CHECK, not ref_data, to avoid seed-order coupling). |
| `sold_amount` | `numeric(12,2)` | NO | `0` | Contract value recorded for reference; money still collected offline. |
| `currency_code` | `character(3)` | NO | `` | Currency snapshot for sold_amount. |
| `plan_snapshot_json` | `jsonb` | NO | `'{}'::jsonb` | Immutable snapshot of plan duration, price, included services, visit count, radius, and other sold terms. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
