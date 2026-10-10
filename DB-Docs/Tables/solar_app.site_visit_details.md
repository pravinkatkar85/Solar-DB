# Table: `solar_app.site_visit_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: All field visits: enquiry/feasibility, installation, free or paid servicing, complaints. Charge vs free is decided in functions from AMC/subscription entitlement and distance slabs from the office. Assignee is any app user (technician, sales, or other authorised role). Money collected offline.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `site_visit_id` | `bigint` | NO | `` | Surrogate primary key. |
| `visit_no` | `character varying(30)` | NO | `` | Public unique visit number generated in fn_create_site_visit_details. |
| `visit_purpose_ref_data_id` | `bigint` | NO | `` | FK to SITE_VISIT_PURPOSES (enquiry, installation, service, complaint, commissioning). |
| `lead_id` | `bigint` | YES | `` | Optional lead for pre-customer feasibility/enquiry visits. |
| `product_enquiry_id` | `bigint` | YES | `` | Optional catalogue enquiry this visit follows up. FK added after product_enquiry_details exists. |
| `customer_id` | `bigint` | YES | `` | Optional customer. FK added after customer_details exists. |
| `site_id` | `bigint` | YES | `` | Optional installed/planned site. FK added after site_details exists. |
| `order_id` | `bigint` | YES | `` | Optional fulfilment order (installation visit). FK added after order_details exists. |
| `service_request_id` | `bigint` | YES | `` | Optional preventive service booking. FK added after service_request_details exists. |
| `service_milestone_id` | `bigint` | YES | `` | Optional free-service milestone consumed by this visit. |
| `complaint_ticket_id` | `bigint` | YES | `` | Optional complaint this visit is for. FK added after complaint_ticket_details exists. |
| `amc_contract_id` | `bigint` | YES | `` | Optional AMC used to mark the visit free. FK added after amc_contract_details exists. |
| `office_location_id` | `bigint` | NO | `` | Office used as distance origin. |
| `assigned_to_user_id` | `bigint` | YES | `` | Assigned technician, sales agent, or other authorised user (user_details). Not limited to technician_details. |
| `slot_window_ref_data_id` | `bigint` | YES | `` | FK to SERVICE_SLOT_WINDOWS (morning/afternoon). |
| `visit_status_ref_data_id` | `bigint` | NO | `` | FK to SITE_VISIT_STATUSES (scheduled, assigned, in progress, completed, cancelled, no-show). |
| `scheduled_on` | `date` | NO | `` | Planned visit date. |
| `started_on` | `timestamp with time zone` | YES | `` | When the assignee started on-site work. |
| `completed_on` | `timestamp with time zone` | YES | `` | When the visit was marked done. |
| `distance_from_office_km` | `numeric(8,2)` | YES | `` | Haversine km from office to site/pincode, computed in functions. |
| `visit_charge_slab_id` | `bigint` | YES | `` | Distance slab used to price this visit. |
| `is_chargeable_ind` | `boolean` | NO | `true` | FALSE when a free servicing entitlement or explicitly free slab applies. |
| `is_free_entitlement_ind` | `boolean` | NO | `false` | TRUE if this visit consumed an AMC or free-milestone credit. |
| `charge_amount` | `numeric(12,2)` | NO | `0` | Visit fee to collect offline (0 when free). |
| `currency_code` | `character(3)` | NO | `` | Currency snapshot for charge_amount. |
| `charge_rule_snapshot_json` | `jsonb` | NO | `'{}'::jsonb` | Immutable snapshot of distance, purpose, slab, pricing precedence, entitlement, and applied rule values. |
| `charges_received_ind` | `boolean` | NO | `false` | TRUE after admin records that the visit fee was collected offline. |
| `charges_received_on` | `date` | YES | `` | Date the visit fee was collected. |
| `invoice_id` | `bigint` | YES | `` | Optional offline bill for this visit fee. FK added after invoice_details exists. |
| `payment_id` | `bigint` | YES | `` | Optional offline receipt. FK added after payment_details exists. |
| `remarks` | `character varying(500)` | YES | `` | Planning notes. |
| `outcome_notes` | `character varying(1000)` | YES | `` | What was done on site. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
