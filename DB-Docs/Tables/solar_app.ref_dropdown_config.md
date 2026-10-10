# Table: `solar_app.ref_dropdown_config`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Allowlisted metadata for dynamic REF_DATA or TABLE dropdowns. It contains no executable SQL.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `dropdown_config_id` | `bigint` | NO | `` | Surrogate primary key. |
| `dropdown_code` | `character varying(50)` | NO | `` | UI/API key such as STATES or PRODUCT_CATEGORIES. |
| `display_name` | `character varying(150)` | NO | `` | Admin-facing name of this dropdown. |
| `source_type` | `character varying(20)` | NO | `` | How options are loaded: REF_DATA or allowlisted TABLE. |
| `category_code` | `character varying(50)` | YES | `` | ref_data_categories.category_code when source_type is REF_DATA. |
| `source_table` | `character varying(100)` | YES | `` | Physical table name when source_type is TABLE. |
| `value_column` | `character varying(100)` | YES | `` | Column used as option value (id). |
| `label_column` | `character varying(100)` | YES | `` | Column used as option label. |
| `parent_dropdown_code` | `character varying(50)` | YES | `` | Parent dropdown_code for cascading refresh. |
| `parent_filter_column` | `character varying(100)` | YES | `` | Child table column compared to the selected parent value. |
| `include_null_parent` | `boolean` | NO | `false` | When TRUE, a cascading TABLE dropdown also includes rows whose parent filter column is NULL, such as statewide utilities. |
| `sort_column` | `character varying(100)` | YES | `` | ORDER BY column for options. |
| `cache_ttl_seconds` | `integer` | NO | `` | Hint for Flutter local cache TTL. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
