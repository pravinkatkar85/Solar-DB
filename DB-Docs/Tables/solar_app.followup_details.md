# Table: `solar_app.followup_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Scheduled admin/sales follow-up against exactly one parent entity (lead, enquiry, order, ticket, etc.).

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `followup_id` | `bigint` | NO | `` | Surrogate primary key. |
| `entity_type` | `character varying(30)` | NO | `` | Which parent FK is populated: LEAD, ENQUIRY, ORDER, TICKET, SERVICE_REQUEST, CUSTOMER, USER. |
| `lead_id` | `bigint` | YES | `` | Parent lead when entity_type is LEAD. |
| `product_enquiry_id` | `bigint` | YES | `` | Parent enquiry when entity_type is ENQUIRY. |
| `order_id` | `bigint` | YES | `` | Parent order when entity_type is ORDER. |
| `complaint_ticket_id` | `bigint` | YES | `` | Parent ticket when entity_type is TICKET. |
| `service_request_id` | `bigint` | YES | `` | Parent service request when entity_type is SERVICE_REQUEST. |
| `customer_id` | `bigint` | YES | `` | Parent customer when entity_type is CUSTOMER. |
| `user_id` | `bigint` | YES | `` | Parent user when entity_type is USER. |
| `followup_type_ref_data_id` | `bigint` | NO | `` | FK to FOLLOWUP_TYPES (call, visit, WhatsApp, email). |
| `status_ref_data_id` | `bigint` | NO | `` | FK to FOLLOWUP_STATUSES (open, done, cancelled). |
| `assigned_to_user_id` | `bigint` | NO | `` | Admin or sales owner of the task. |
| `due_on` | `timestamp with time zone` | NO | `` | When the follow-up is due. |
| `completed_on` | `timestamp with time zone` | YES | `` | When the task was completed. |
| `notes` | `character varying(1000)` | YES | `` | Instructions for the assignee. |
| `outcome_notes` | `character varying(1000)` | YES | `` | Result logged when completing the task. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
