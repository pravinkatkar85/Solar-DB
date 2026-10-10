# Table: `solar_app.quote_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Formal quotation header with PDF URL and validity date.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `quote_id` | `bigint` | NO | `` | Surrogate primary key. |
| `quote_no` | `character varying(30)` | NO | `` | Public unique quotation number. |
| `lead_id` | `bigint` | NO | `` | Parent lead. |
| `estimate_id` | `bigint` | YES | `` | Calculator estimate copied into this quote. |
| `quote_status_ref_data_id` | `bigint` | NO | `` | FK to QUOTE_STATUSES. |
| `subsidy_slab_id` | `bigint` | YES | `` | Source subsidy slab copied from the estimate for traceability. |
| `gross_amount` | `numeric(14,2)` | NO | `` | Quoted gross amount. |
| `subsidy_amount` | `numeric(14,2)` | NO | `0` | Quoted subsidy. |
| `net_amount` | `numeric(14,2)` | NO | `` | Quoted net payable (collected offline). |
| `currency_code` | `character(3)` | NO | `` | Currency snapshot for all quote monetary columns. |
| `rule_snapshot_json` | `jsonb` | NO | `'{}'::jsonb` | Immutable snapshot of applied pricing, calculator, and subsidy rule outcomes. |
| `pdf_url` | `character varying(500)` | YES | `` | Generated branded PDF URL. |
| `valid_until` | `date` | YES | `` | Quote validity date. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
