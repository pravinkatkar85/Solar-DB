# Table: `solar_app.ticket_message_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: In-app ticket chat. is_internal hides dispatcher notes from the customer.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `ticket_message_id` | `bigint` | NO | `` | Surrogate primary key. |
| `complaint_ticket_id` | `bigint` | NO | `` | Parent ticket. |
| `sender_user_id` | `bigint` | NO | `` | User who sent the chat message. |
| `message_text` | `character varying(2000)` | NO | `` | Chat body. |
| `is_internal` | `boolean` | NO | `false` | TRUE hides the note from the customer (dispatcher only). |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
