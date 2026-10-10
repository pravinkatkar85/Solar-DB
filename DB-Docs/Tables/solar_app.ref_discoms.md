# Table: `solar_app.ref_discoms`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Electricity distribution companies. NULL district_id means statewide; set district_id for a local circle.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `discom_id` | `bigint` | NO | `` | Surrogate primary key. |
| `state_id` | `bigint` | NO | `` | FK to state this utility operates in. |
| `district_id` | `bigint` | YES | `` | Optional local circle; NULL means statewide utility. |
| `discom_code` | `character varying(30)` | NO | `` | Stable deployment-defined utility code. |
| `discom_name` | `character varying(150)` | NO | `` | Legal or trading name of the utility. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
