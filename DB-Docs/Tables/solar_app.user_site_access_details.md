# Table: `solar_app.user_site_access_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Which users may switch into which sites (owner/family/operator) including default site.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `user_site_access_id` | `bigint` | NO | `` | Surrogate primary key. |
| `user_id` | `bigint` | NO | `` | User who may switch into the site. |
| `site_id` | `bigint` | NO | `` | Site being granted. |
| `is_default` | `boolean` | NO | `false` | TRUE is the last-selected / default site for the user (one per user via partial unique index). |
| `access_role_ref_data_id` | `bigint` | YES | `` | FK to SITE_ACCESS_ROLES (owner, family, operator). |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
