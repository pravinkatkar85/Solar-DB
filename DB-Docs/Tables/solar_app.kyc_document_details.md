# Table: `solar_app.kyc_document_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: KYC and DISCOM document uploads with verification status. Reject comment is mandatory in functions when rejected.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `kyc_document_id` | `bigint` | NO | `` | Surrogate primary key. |
| `customer_id` | `bigint` | NO | `` | Customer who owns the document. |
| `site_id` | `bigint` | YES | `` | Optional site this document belongs to (roof photos, bill). |
| `document_type_ref_data_id` | `bigint` | NO | `` | FK to DOCUMENT_TYPES (Aadhaar, bill, NOC, photos). |
| `file_url` | `character varying(500)` | NO | `` | Object-storage URL of the upload. |
| `mime_type` | `character varying(100)` | YES | `` | MIME type of the file. |
| `file_size_bytes` | `integer` | NO | `` | Size in bytes; the effective upload limit is resolved from business parameters. |
| `verification_status_ref_data_id` | `bigint` | NO | `` | FK to DOCUMENT_VERIFICATION_STATUSES. |
| `verified_by_user_id` | `bigint` | YES | `` | Admin who approved or rejected. |
| `rejection_comment` | `character varying(500)` | YES | `` | Mandatory in functions when status is Action Required / Rejected. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
