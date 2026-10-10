# Table: `solar_app.ref_cities`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Cities and towns. state_id is denormalized so State→City queries do not always require district.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `city_id` | `bigint` | NO | `` | Surrogate primary key. |
| `district_id` | `bigint` | NO | `` | FK to parent district. |
| `state_id` | `bigint` | NO | `` | Denormalized FK to state for faster State→City lists. |
| `city_name` | `character varying(100)` | NO | `` | City or town name (includes district-HQ placeholder rows). |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
