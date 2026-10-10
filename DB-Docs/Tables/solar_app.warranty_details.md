# Table: `solar_app.warranty_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Warranty card vault for an equipment row (type, dates, document URL).

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `warranty_id` | `bigint` | NO | `` | Surrogate primary key. |
| `equipment_id` | `bigint` | NO | `` | Parent installed asset. |
| `warranty_type_ref_data_id` | `bigint` | NO | `` | FK to WARRANTY_TYPES (panel performance, inverter, …). |
| `start_on` | `date` | NO | `` | Warranty start date. |
| `end_on` | `date` | NO | `` | Warranty end date. |
| `terms_summary` | `character varying(500)` | YES | `` | Short terms text. |
| `document_url` | `character varying(500)` | YES | `` | Scanned warranty card URL. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
