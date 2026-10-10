# Table: `solar_app.ref_office_locations`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Company office/branch points used as the origin for site-visit distance and charge slabs.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `office_location_id` | `bigint` | NO | `` | Surrogate primary key. |
| `office_code` | `character varying(30)` | NO | `` | Stable deployment-defined office code. |
| `office_name` | `character varying(150)` | NO | `` | Display name of the office. |
| `address_line1` | `character varying(255)` | NO | `` | Office street address line 1. |
| `address_line2` | `character varying(255)` | YES | `` | Office street address line 2. |
| `city_id` | `bigint` | YES | `` | FK to city. |
| `pincode_id` | `bigint` | YES | `` | FK to postal-code master. |
| `latitude` | `numeric(10,7)` | NO | `` | Office latitude for haversine distance in SQL functions. |
| `longitude` | `numeric(10,7)` | NO | `` | Office longitude for haversine distance in SQL functions. |
| `is_default` | `boolean` | NO | `false` | TRUE is the deployment default origin when a visit does not specify an office. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
