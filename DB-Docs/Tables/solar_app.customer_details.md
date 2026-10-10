# Table: `solar_app.customer_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Legal/billing party with optional country-specific tax registration, linked 1:1 to a user and separate from physical sites.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `customer_id` | `bigint` | NO | `` | Surrogate primary key. |
| `user_id` | `bigint` | NO | `` | 1:1 FK to the login user for this legal/billing party. |
| `customer_code` | `character varying(30)` | NO | `` | Business customer code unique in the register. |
| `billing_name` | `character varying(150)` | YES | `` | Name printed on offline bills. |
| `tax_registration_no` | `character varying(50)` | YES | `` | Optional country-specific tax registration number validated from country metadata. |
| `billing_address_line1` | `character varying(255)` | YES | `` | Billing address line 1. |
| `billing_address_line2` | `character varying(255)` | YES | `` | Billing address line 2. |
| `billing_pincode_id` | `bigint` | YES | `` | FK to billing postal code. |
| `originating_lead_id` | `bigint` | YES | `` | Lead this customer was converted from, if Path A. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
