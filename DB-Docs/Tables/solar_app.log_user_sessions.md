# Table: `solar_app.log_user_sessions`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Login session, device, hashed JWT, and FCM push token. Named log_* per project logging rules.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `session_id` | `bigint` | NO | `` | Surrogate primary key. |
| `user_id` | `bigint` | YES | `` | Set after OTP succeeds; NULL while PENDING_OTP. |
| `mobile_e164` | `character varying(16)` | NO | `` | Normalized E.164 mobile used to start this login. |
| `device_id` | `character varying(100)` | YES | `` | Client device identifier. |
| `device_model` | `character varying(100)` | YES | `` | Device model string for audit. |
| `device_os` | `character varying(50)` | YES | `` | Android/iOS version string. |
| `ip_address` | `character varying(45)` | YES | `` | Login IP address. |
| `jwt_token_hash` | `character varying(255)` | YES | `` | Hash of the issued JWT; never store the raw token. |
| `push_token` | `character varying(512)` | YES | `` | FCM (or equivalent) device token for Module 13 push. |
| `session_status` | `character varying(20)` | NO | `'ACTIVE'::character varying` | PENDING_OTP, ACTIVE, EXPIRED, LOGGED_OUT, or LOCKED. |
| `login_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | When the session was created. |
| `last_seen_on` | `timestamp with time zone` | YES | `` | Last authenticated activity. |
| `logout_on` | `timestamp with time zone` | YES | `` | When the user logged out, if applicable. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
