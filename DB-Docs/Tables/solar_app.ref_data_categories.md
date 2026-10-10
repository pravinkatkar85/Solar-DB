# Table: `solar_app.ref_data_categories`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Master list of dropdown categories used by fn_get_dropdown_data (roles, statuses, notification types, etc.).

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `category_id` | `bigint` | NO | `` | Surrogate primary key (GENERATED ALWAYS AS IDENTITY). |
| `category_code` | `character varying(50)` | NO | `` | Stable API code such as USER_ROLES, PRODUCT_CATEGORIES, NOTIFICATION_TYPES. |
| `category_name` | `character varying(150)` | NO | `` | Admin and UI title for the category. |
| `category_desc` | `character varying(500)` | YES | `` | When and why this dropdown list is used. |
| `sort_order` | `integer` | NO | `0` | Display order in admin master screens. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
