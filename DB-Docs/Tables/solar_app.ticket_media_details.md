# Table: `solar_app.ticket_media_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Complaint photo/video attachments; the effective attachment-count limit comes from business parameters.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `ticket_media_id` | `bigint` | NO | `` | Surrogate primary key. |
| `complaint_ticket_id` | `bigint` | NO | `` | Parent ticket. |
| `media_type` | `character varying(20)` | NO | `` | PHOTO or VIDEO. |
| `file_url` | `character varying(500)` | NO | `` | Object-storage URL. |
| `file_size_bytes` | `integer` | YES | `` | File size in bytes. |
| `sort_order` | `integer` | NO | `0` | Gallery order; count limits are resolved from effective business parameters. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
