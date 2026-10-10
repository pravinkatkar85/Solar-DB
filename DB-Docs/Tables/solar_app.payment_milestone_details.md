# Table: `solar_app.payment_milestone_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Agreed offline instalment split recorded after collection (not an EMI gateway).

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `payment_milestone_id` | `bigint` | NO | `` | Surrogate primary key. |
| `invoice_id` | `bigint` | NO | `` | Parent offline bill. |
| `sequence_no` | `integer` | NO | `` | Instalment sequence (e.g. 1=20%, 2=70%, 3=10%). |
| `percent_share` | `numeric(5,2)` | YES | `` | Agreed percent of the bill for this split. |
| `due_amount` | `numeric(14,2)` | NO | `` | Amount expected for this split. |
| `paid_amount` | `numeric(14,2)` | NO | `0` | Amount recorded against this split. |
| `due_on` | `date` | YES | `` | Agreed due date; not an in-app collection date. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
