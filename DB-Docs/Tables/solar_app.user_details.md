# Table: `solar_app.user_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Single login table for every app persona: customer, technician, sales, and admin. Technicians and customers are users; extra tables only hold role-specific fields.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `user_id` | `bigint` | NO | `` | Surrogate primary key; stored as logged_in_user_id in function payloads. |
| `country_id` | `bigint` | NO | `` | FK to ref_countries for country-specific display and validation metadata. |
| `mobile_e164` | `character varying(16)` | NO | `` | Normalized E.164 mobile number; unique among active users and used as the OTP login key. |
| `full_name` | `character varying(150)` | YES | `` | Display name on profile and tickets. |
| `email` | `character varying(150)` | YES | `` | Optional communication email. |
| `secondary_mobile_e164` | `character varying(16)` | YES | `` | Optional second contact in normalized E.164 format. |
| `emergency_contact_name` | `character varying(150)` | YES | `` | Emergency contact person name. |
| `emergency_contact_mobile_e164` | `character varying(16)` | YES | `` | Emergency contact number in normalized E.164 format. |
| `role_ref_data_id` | `bigint` | NO | `` | FK to USER_ROLES (customer, technician, sales, admin). |
| `preferred_language_ref_data_id` | `bigint` | YES | `` | FK to APP_LANGUAGES (EN/MR/HI). |
| `pin_hash` | `character varying(255)` | YES | `` | Hashed 4-digit PIN for quick login; never store plaintext PIN. |
| `biometric_enabled` | `boolean` | NO | `false` | TRUE if device biometric quick-login is allowed. |
| `push_notifications_enabled` | `boolean` | NO | `true` | Master push toggle. Inbox rows are still written when FALSE. |
| `profile_photo_url` | `character varying(500)` | YES | `` | Profile photo; for technicians this is the assigned-engineer card photo. |
| `admin_registered` | `boolean` | NO | `false` | TRUE when admin created/activated this login (Path B post-install, or admin-created staff). FALSE = Path A self-app / lead funnel until they complete self-registration (functions then set TRUE). |
| `account_status_ref_data_id` | `bigint` | YES | `` | ACTIVE vs SUSPENDED. Suspend blocks login without soft-delete. |
| `registration_source_ref_data_id` | `bigint` | YES | `` | REG_SELF_APP (Path A) vs REG_ADMIN_POST_INSTALL (Path B). |
| `last_login_on` | `timestamp with time zone` | YES | `` | Last successful OTP/PIN login timestamp. |
| `failed_otp_count` | `integer` | NO | `0` | Failed OTP attempts in the current lockout window. |
| `otp_window_started_on` | `timestamp with time zone` | YES | `` | Start of the current 3-fail-per-hour window. |
| `lockout_until` | `timestamp with time zone` | YES | `` | Login blocked until this instant after too many OTP failures. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
