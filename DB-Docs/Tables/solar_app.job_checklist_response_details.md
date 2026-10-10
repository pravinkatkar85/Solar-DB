# Table: `solar_app.job_checklist_response_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Technician answers against ref_checklist_items for one job.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `job_checklist_response_id` | `bigint` | NO | `` | Surrogate primary key. |
| `job_id` | `bigint` | NO | `` | Parent job. |
| `checklist_item_id` | `bigint` | NO | `` | FK to ref_checklist_items template line. |
| `is_pass` | `boolean` | YES | `` | BOOLEAN result when expected_value_type is BOOLEAN. |
| `measured_value` | `character varying(100)` | YES | `` | Numeric or text measurement (VOC/ISC, remarks). |
| `remarks` | `character varying(500)` | YES | `` | Optional technician note for this item. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
