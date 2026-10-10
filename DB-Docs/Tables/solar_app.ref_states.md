# Table: `solar_app.ref_states`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Administrative states or regions used for tax jurisdiction, geo cascade, utilities, and subsidy overlays.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `state_id` | `bigint` | NO | `` | Surrogate primary key. |
| `country_id` | `bigint` | NO | `` | FK to ref_countries. |
| `state_code` | `character varying(10)` | NO | `` | Short state/UT code unique within country. |
| `state_name` | `character varying(100)` | NO | `` | Official state or region name. |
| `tax_region_code` | `character varying(20)` | YES | `` | Optional country-specific tax or place-of-supply region code. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
