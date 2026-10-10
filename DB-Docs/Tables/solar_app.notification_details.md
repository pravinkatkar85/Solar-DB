# Table: `solar_app.notification_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: In-app notification inbox: one row per recipient per event. Enqueued by fn_create_notification_details (no triggers).

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `notification_id` | `bigint` | NO | `` | Surrogate primary key. |
| `recipient_user_id` | `bigint` | NO | `` | User who should see this inbox row. |
| `notification_type_ref_data_id` | `bigint` | NO | `` | FK to NOTIFICATION_TYPES (catalogue, enquiry, complaint, reminder, …). |
| `title` | `character varying(200)` | NO | `` | Short inbox/push title. |
| `body` | `character varying(1000)` | NO | `` | Inbox/push body text. |
| `payload_json` | `jsonb` | NO | `'{}'::jsonb` | Deep-link JSON: entity_type, entity_id, extras. |
| `related_entity_type` | `character varying(40)` | YES | `` | Parent entity class for navigation (PRODUCT, TICKET, …). |
| `related_entity_id` | `bigint` | YES | `` | Primary key of the related entity. |
| `is_read_ind` | `boolean` | NO | `false` | FALSE counts toward the unread badge. |
| `read_on` | `timestamp with time zone` | YES | `` | When the recipient marked the row read. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
