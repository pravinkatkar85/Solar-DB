# Table: `solar_app.site_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Installed or planned solar site (address, DISCOM account, GPS, commissioning). Multi-property selector parent.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `site_id` | `bigint` | NO | `` | Surrogate primary key. |
| `customer_id` | `bigint` | NO | `` | Owner customer of this installation site. |
| `site_name` | `character varying(150)` | NO | `` | Selector label such as Home - 5kW. |
| `address_line1` | `character varying(255)` | NO | `` | Site street address line 1. |
| `address_line2` | `character varying(255)` | YES | `` | Site street address line 2. |
| `pincode_id` | `bigint` | YES | `` | FK to site postal code. |
| `city_id` | `bigint` | YES | `` | FK to city. |
| `district_id` | `bigint` | YES | `` | FK to district. |
| `state_id` | `bigint` | YES | `` | FK to state. |
| `latitude` | `numeric(10,7)` | YES | `` | GPS latitude for technician routing. |
| `longitude` | `numeric(10,7)` | YES | `` | GPS longitude for technician routing. |
| `discom_id` | `bigint` | YES | `` | Electricity provider for this connection. |
| `consumer_number` | `character varying(50)` | YES | `` | DISCOM consumer account number. |
| `meter_number` | `character varying(50)` | YES | `` | Electricity meter number. |
| `sanctioned_load_kw` | `numeric(8,3)` | YES | `` | Sanctioned load in kW from the bill/KYC. |
| `connection_type_ref_data_id` | `bigint` | YES | `` | FK to CONNECTION_TYPES. |
| `installation_status_ref_data_id` | `bigint` | YES | `` | FK to INSTALLATION_STATUSES. |
| `commissioning_on` | `date` | YES | `` | Commissioning date; starts the configured free-service milestone schedule. |
| `order_id` | `bigint` | YES | `` | Order fulfilled at this site (Path A) or recorded at Path B registration. FK added after order_details exists. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
