# Table: `solar_app.log_otp_attempts`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Hashed OTP dispatch and verification audit. Cooldown, expiry, and lockout limits come from effective-dated business parameters. Not used for ticket OTP.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `otp_attempt_id` | `bigint` | NO | `` | Surrogate primary key. |
| `mobile_e164` | `character varying(16)` | NO | `` | Normalized E.164 mobile to which the OTP was sent. |
| `session_id` | `bigint` | YES | `` | FK to the login session this OTP belongs to. |
| `otp_hash` | `character varying(255)` | NO | `` | Hashed OTP; never store plaintext OTP. |
| `otp_expires_on` | `timestamp with time zone` | NO | `` | OTP expiry instant. |
| `is_consumed` | `boolean` | NO | `false` | TRUE after successful verify; blocks replay. |
| `attempt_no` | `integer` | NO | `1` | Nth send/verify in this window. |
| `resend_available_on` | `timestamp with time zone` | YES | `` | Earliest time another OTP may be sent under the applied parameter version. |
| `ip_address` | `character varying(45)` | YES | `` | IP of the dispatch/verify request. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
