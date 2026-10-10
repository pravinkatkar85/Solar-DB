# Table: `solar_app.invoice_tax_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Immutable transaction-level tax component snapshots for an invoice or optional invoice line.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `invoice_tax_id` | `bigint` | NO | `` | Surrogate primary key. |
| `invoice_id` | `bigint` | NO | `` | Parent offline invoice. |
| `invoice_line_id` | `bigint` | YES | `` | Optional invoice line to which this component applies; NULL means invoice-level. |
| `source_tax_rule_id` | `bigint` | YES | `` | Optional source rule retained for traceability; snapshot columns remain authoritative for history. |
| `tax_group_code` | `character varying(50)` | NO | `` | Applied tax group code snapshot. |
| `tax_component_code` | `character varying(50)` | NO | `` | Applied component code snapshot. |
| `tax_display_name` | `character varying(150)` | NO | `` | Customer-facing component label snapshot. |
| `calculation_method` | `character varying(20)` | NO | `` | Applied calculation method snapshot. |
| `rate_percent` | `numeric(7,4)` | YES | `` | Applied percentage snapshot for a percentage rule. |
| `configured_rate_amount` | `numeric(14,2)` | YES | `` | Applied configured amount snapshot for a fixed-amount rule. |
| `taxable_amount` | `numeric(14,2)` | NO | `` | Taxable base used for this component. |
| `tax_amount` | `numeric(14,2)` | NO | `` | Calculated or transcribed component amount. |
| `jurisdiction_json` | `jsonb` | NO | `'{}'::jsonb` | Snapshot of applicable country, region, place-of-supply, and classification context. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
