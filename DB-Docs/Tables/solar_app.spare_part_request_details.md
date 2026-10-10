# Table: `solar_app.spare_part_request_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Technician spare-part request from site. Not a warehouse SKU ledger in v1.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `spare_part_request_id` | `bigint` | NO | `` | Surrogate primary key. |
| `job_id` | `bigint` | NO | `` | Job during which parts were requested. |
| `complaint_ticket_id` | `bigint` | YES | `` | Optional related complaint. |
| `part_code` | `character varying(50)` | YES | `` | Optional part code (not a warehouse SKU master). |
| `part_name` | `character varying(150)` | NO | `` | Part description. |
| `quantity` | `numeric(12,3)` | NO | `` | Requested quantity. |
| `request_status` | `character varying(20)` | NO | `'REQUESTED'::character varying` | REQUESTED, APPROVED, ISSUED, USED, or REJECTED. |
| `remarks` | `character varying(500)` | YES | `` | Technician or admin notes. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
