# Table: `solar_app.job_signoff_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Customer signature pad image; otp_verified_ind records complaint resolution OTP success.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `job_signoff_id` | `bigint` | NO | `` | Surrogate primary key. |
| `job_id` | `bigint` | NO | `` | Parent job (one active sign-off per job in functions). |
| `signature_url` | `character varying(500)` | NO | `` | Signature-pad image URL. |
| `signer_name` | `character varying(150)` | YES | `` | Name captured with the signature. |
| `signed_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | When the customer signed. |
| `otp_verified_ind` | `boolean` | NO | `false` | TRUE when complaint resolution OTP succeeded. |
| `customer_user_id` | `bigint` | YES | `` | Customer user who signed, if known. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
