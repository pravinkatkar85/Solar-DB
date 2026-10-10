# Table: `solar_app.ref_data`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Generic dropdown values belonging to a category, including nested parent values for in-list cascades.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `ref_data_id` | `bigint` | NO | `` | Surrogate primary key; used as dropdown value_id in the app. |
| `category_id` | `bigint` | NO | `` | FK to ref_data_categories; which list this value belongs to. |
| `data_code` | `character varying(50)` | NO | `` | Stable machine code (ROLE_ADMIN, NTF_ENQUIRY_NEW, PAY_CASH, …). |
| `data_value` | `character varying(255)` | NO | `` | Human-readable label shown in the UI. |
| `data_desc` | `character varying(500)` | YES | `` | Optional help text or audience notes. |
| `parent_ref_data_id` | `bigint` | YES | `` | Optional parent value for in-list cascading dropdowns. |
| `sort_order` | `integer` | NO | `0` | Order of options inside the category. |
| `extra_json` | `jsonb` | NO | `'{}'::jsonb` | Optional extra attributes (icon, SLA hours, audience flags). |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
