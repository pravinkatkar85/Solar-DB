# Table: `solar_app.log_notification_delivery`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Push (FCM) send queue and delivery audit. OTP SMS is stored in log_otp_attempts, not here.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `delivery_id` | `bigint` | NO | `` | Surrogate primary key. |
| `notification_id` | `bigint` | NO | `` | FK to the inbox row being pushed. |
| `session_id` | `bigint` | YES | `` | Session whose push_token was used, if any. |
| `channel_ref_data_id` | `bigint` | NO | `` | FK to NOTIFICATION_CHANNELS (typically PUSH). |
| `delivery_status_ref_data_id` | `bigint` | NO | `` | FK to PENDING / SENT / FAILED. |
| `provider_message_id` | `character varying(200)` | YES | `` | FCM (or provider) message id when sent. |
| `error_message` | `character varying(1000)` | YES | `` | Provider error text when FAILED. |
| `sent_on` | `timestamp with time zone` | YES | `` | When the worker marked SENT. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
