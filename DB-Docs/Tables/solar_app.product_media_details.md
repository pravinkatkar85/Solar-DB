# Table: `solar_app.product_media_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Product gallery photos, videos, and spec-sheet documents.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `product_media_id` | `bigint` | NO | `` | Surrogate primary key. |
| `product_id` | `bigint` | NO | `` | Parent catalogue product. |
| `media_type` | `character varying(20)` | NO | `` | PHOTO, VIDEO, or DOCUMENT. |
| `file_url` | `character varying(500)` | NO | `` | Object-storage URL. |
| `caption` | `character varying(255)` | YES | `` | Optional alt text or caption. |
| `sort_order` | `integer` | NO | `0` | Gallery order. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
