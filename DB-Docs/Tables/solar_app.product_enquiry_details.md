# Table: `solar_app.product_enquiry_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Registered-user enquiry against one catalogue product; may convert to a lead without deleting history.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `product_enquiry_id` | `bigint` | NO | `` | Surrogate primary key. |
| `enquiry_no` | `character varying(30)` | NO | `` | Public tracking number generated in fn_create_product_enquiry_details. |
| `product_id` | `bigint` | NO | `` | Catalogue product of interest. |
| `user_id` | `bigint` | NO | `` | Logged-in registered user who submitted the enquiry. |
| `customer_id` | `bigint` | YES | `` | Set when the user already has a customer_details row. |
| `pincode_id` | `bigint` | YES | `` | Optional installation postal code. |
| `message_text` | `character varying(2000)` | NO | `` | Requirement or questions from the user. |
| `preferred_contact_window` | `character varying(50)` | YES | `` | Preferred callback window. |
| `status_ref_data_id` | `bigint` | NO | `` | FK to PRODUCT_ENQUIRY_STATUSES. |
| `assigned_agent_user_id` | `bigint` | YES | `` | Sales follow-up owner. |
| `admin_remarks` | `character varying(500)` | YES | `` | Internal notes. |
| `converted_lead_id` | `bigint` | YES | `` | Lead created or linked on conversion; enquiry row is retained. |
| `converted_on` | `timestamp with time zone` | YES | `` | Conversion timestamp. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
