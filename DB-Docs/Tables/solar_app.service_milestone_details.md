# Table: `solar_app.service_milestone_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Configured free-service milestones per site after commissioning; count and claim window come from the applied business-rule version.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `service_milestone_id` | `bigint` | NO | `` | Surrogate primary key. |
| `site_id` | `bigint` | NO | `` | Site whose free-service clock this milestone belongs to. |
| `milestone_no` | `integer` | NO | `` | Sequence of free servicing visits for the site. How many are created is configurable (FREE_SVC_VISIT_COUNT / AMC free_visit_count), not hard-coded to 4. |
| `due_on` | `date` | NO | `` | Planned visit date. |
| `claim_window_end_on` | `date` | NO | `` | Final claim date calculated from the effective claim-window parameter and stored as a historical outcome. |
| `status_ref_data_id` | `bigint` | NO | `` | FK to MILESTONE_STATUSES. |
| `service_request_id` | `bigint` | YES | `` | Linked booking when the visit is claimed; deferred FK. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
