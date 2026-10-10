# Table: `solar_app.service_request_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Preventive service booking or admin-entered historical visit (Path B), linked to site/product/order when known.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `service_request_id` | `bigint` | NO | `` | Surrogate primary key. |
| `service_request_no` | `character varying(30)` | NO | `` | Public unique service request number. |
| `site_id` | `bigint` | NO | `` | Site to be serviced. |
| `customer_id` | `bigint` | NO | `` | Customer who owns the site. |
| `technician_id` | `bigint` | YES | `` | Assigned field engineer, if any. |
| `service_type_ref_data_id` | `bigint` | NO | `` | FK to SERVICE_TYPES (cleaning, inspection, inverter check). |
| `slot_window_ref_data_id` | `bigint` | YES | `` | FK to SERVICE_SLOT_WINDOWS. |
| `status_ref_data_id` | `bigint` | NO | `` | FK to SERVICE_REQUEST_STATUSES. |
| `preferred_on` | `date` | YES | `` | Customer preferred date. |
| `milestone_id` | `bigint` | YES | `` | Free-service milestone being claimed, if any. |
| `amc_contract_id` | `bigint` | YES | `` | AMC this visit is billed/covered under, if any. |
| `order_id` | `bigint` | YES | `` | Optional related fulfilment order. |
| `product_id` | `bigint` | YES | `` | Optional catalogue product this visit relates to. |
| `arrival_status` | `character varying(30)` | YES | `` | Technician arrival state for the customer tracker. |
| `completion_notes` | `character varying(1000)` | YES | `` | Work done / historical Path B notes. |
| `report_url` | `character varying(500)` | YES | `` | Downloadable service report URL. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
