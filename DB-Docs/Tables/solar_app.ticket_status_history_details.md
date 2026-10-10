# Table: `solar_app.ticket_status_history_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Ticket stepper history. Functions insert a row on each status change (no triggers).

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `ticket_status_history_id` | `bigint` | NO | `` | Surrogate primary key. |
| `complaint_ticket_id` | `bigint` | NO | `` | Parent ticket. |
| `from_status_ref_data_id` | `bigint` | YES | `` | Previous stepper status; NULL on first insert. |
| `to_status_ref_data_id` | `bigint` | NO | `` | New stepper status. |
| `changed_by_user_id` | `bigint` | YES | `` | Actor who changed status. |
| `remarks` | `character varying(500)` | YES | `` | Optional reason for the transition. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
