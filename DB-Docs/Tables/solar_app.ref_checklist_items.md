# Table: `solar_app.ref_checklist_items`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Field job-sheet template lines (VOC/ISC, earthing, cleaning, inverter logger) by job type.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `checklist_item_id` | `bigint` | NO | `` | Surrogate primary key. |
| `job_type` | `character varying(30)` | NO | `` | SERVICE_REQUEST, COMPLAINT, or COMMISSIONING template set. |
| `item_code` | `character varying(50)` | NO | `` | Stable item code unique per job_type while active. |
| `item_label` | `character varying(255)` | NO | `` | Prompt shown on the technician job sheet. |
| `expected_value_type` | `character varying(20)` | NO | `'BOOLEAN'::character varying` | BOOLEAN, NUMERIC, or TEXT answer. |
| `is_mandatory` | `boolean` | NO | `true` | TRUE if the technician must complete this item. |
| `sort_order` | `integer` | NO | `0` | Display order on the job sheet. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
