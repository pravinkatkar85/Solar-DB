# Table: `solar_app.job_assignment_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Technician field job linked to a site visit, service request, complaint, or commissioning. Sales/other assignees use site_visit_details.assigned_to_user_id without a job row.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `job_id` | `bigint` | NO | `` | Surrogate primary key. |
| `job_type` | `character varying(30)` | NO | `` | SERVICE_REQUEST, COMPLAINT, SITE_VISIT, or COMMISSIONING. |
| `site_id` | `bigint` | NO | `` | Site the technician must visit. |
| `technician_id` | `bigint` | NO | `` | Assigned field engineer. |
| `service_request_id` | `bigint` | YES | `` | Parent SR when job_type is SERVICE_REQUEST. |
| `complaint_ticket_id` | `bigint` | YES | `` | Parent ticket when job_type is COMPLAINT. |
| `site_visit_id` | `bigint` | YES | `` | Parent site_visit_details when this job is the technician execution of that visit. |
| `job_status_ref_data_id` | `bigint` | NO | `` | FK to JOB_STATUSES. |
| `scheduled_on` | `date` | NO | `` | Job date for the technician queue. |
| `sequence_no` | `integer` | YES | `` | Route order for the day. |
| `travel_distance_km` | `numeric(8,2)` | YES | `` | Route distance for the day queue; visit billing uses site_visit_details.distance_from_office_km. |
| `accept_reject_reason` | `character varying(500)` | YES | `` | Reason when the technician reschedules or rejects. |
| `eta_on` | `timestamp with time zone` | YES | `` | Estimated arrival instant. |
| `started_on` | `timestamp with time zone` | YES | `` | When on-site work started. |
| `completed_on` | `timestamp with time zone` | YES | `` | When the job was completed. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
