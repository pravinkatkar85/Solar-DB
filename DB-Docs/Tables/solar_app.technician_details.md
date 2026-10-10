# Table: `solar_app.technician_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Field-engineer profile for a user who already exists in user_details with ROLE_TECHNICIAN. Not a separate login: OTP, name, mobile, photo, push, and language live on user_details. This row holds only job-queue fields (employee code, availability, GPS, radius). Required 1:1 — creating a technician user must insert both rows in the same SQL function.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `technician_id` | `bigint` | NO | `` | Surrogate primary key. |
| `user_id` | `bigint` | NO | `` | Required 1:1 FK to user_details. This person logs into the app with that user_id (same OTP as any other user). UNIQUE so one user cannot have two technician profiles. |
| `employee_code` | `character varying(30)` | NO | `` | HR/employee code unique among technicians. |
| `service_radius_km` | `numeric(6,2)` | YES | `` | Optional service coverage radius in kilometres. |
| `is_available` | `boolean` | NO | `true` | FALSE hides the technician from new job allocation. |
| `current_latitude` | `numeric(10,7)` | YES | `` | Last known latitude for arrival tracking. |
| `current_longitude` | `numeric(10,7)` | YES | `` | Last known longitude for arrival tracking. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
