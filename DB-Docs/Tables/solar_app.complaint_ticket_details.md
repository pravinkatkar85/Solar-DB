# Table: `solar_app.complaint_ticket_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Breakdown complaint header with unique ticket number and hashed resolution OTP.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `complaint_ticket_id` | `bigint` | NO | `` | Surrogate primary key. |
| `ticket_no` | `character varying(30)` | NO | `` | Public unique ticket number (TKT-YYYY-nnnn). |
| `site_id` | `bigint` | NO | `` | Site the complaint is about. |
| `customer_id` | `bigint` | NO | `` | Customer who owns the site. |
| `raised_by_user_id` | `bigint` | NO | `` | User who raised the ticket. |
| `assigned_technician_id` | `bigint` | YES | `` | Assigned field engineer. |
| `category_ref_data_id` | `bigint` | NO | `` | FK to COMPLAINT_CATEGORIES. |
| `severity_ref_data_id` | `bigint` | NO | `` | FK to COMPLAINT_SEVERITIES (including Emergency). |
| `status_ref_data_id` | `bigint` | NO | `` | FK to TICKET_STATUSES stepper. |
| `description` | `character varying(2000)` | NO | `` | Fault description from the customer or admin. |
| `resolution_otp_hash` | `character varying(255)` | YES | `` | Hashed 4-digit OTP required to mark Resolved; never plaintext. |
| `otp_expires_on` | `timestamp with time zone` | YES | `` | Resolution OTP expiry. |
| `resolved_on` | `timestamp with time zone` | YES | `` | When the ticket was marked Resolved. |
| `closed_on` | `timestamp with time zone` | YES | `` | When the ticket was closed. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
