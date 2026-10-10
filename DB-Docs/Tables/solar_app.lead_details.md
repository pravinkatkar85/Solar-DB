# Table: `solar_app.lead_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Sales lead after Get quote or after converting a product enquiry.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `lead_id` | `bigint` | NO | `` | Surrogate primary key. |
| `lead_no` | `character varying(30)` | NO | `` | Public unique lead number. |
| `estimate_id` | `bigint` | YES | `` | Calculator run this lead was created from, if any. |
| `user_id` | `bigint` | YES | `` | App user who became a lead, if already registered. |
| `full_name` | `character varying(150)` | NO | `` | Lead contact name. |
| `country_id` | `bigint` | NO | `` | Country used for address and country-dependent validation metadata. |
| `mobile_e164` | `character varying(16)` | NO | `` | Lead contact number in normalized E.164 format. |
| `pincode_id` | `bigint` | YES | `` | FK to installation postal code when known. |
| `pincode` | `character varying(20)` | YES | `` | Raw postal code if a master row is unavailable. |
| `preferred_contact_window` | `character varying(50)` | YES | `` | Preferred callback window. |
| `lead_status_ref_data_id` | `bigint` | NO | `` | FK to LEAD_STATUSES. |
| `converted_customer_id` | `bigint` | YES | `` | Customer created after onboarding; deferred FK. |
| `assigned_agent_user_id` | `bigint` | YES | `` | Sales agent owner. |
| `remarks` | `character varying(500)` | YES | `` | Internal sales notes. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
