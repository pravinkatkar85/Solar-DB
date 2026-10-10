# Table: `solar_app.ref_subsidy_slabs`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Non-overlapping capacity tiers belonging to an effective-dated subsidy scheme.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `subsidy_slab_id` | `bigint` | NO | `` | Surrogate primary key. |
| `subsidy_scheme_id` | `bigint` | NO | `` | Effective-dated parent scheme that defines calculation method, jurisdiction, currency, and cap. |
| `connection_type_ref_data_id` | `bigint` | NO | `` | FK to CONNECTION_TYPES (residential, society, commercial). |
| `min_capacity_kw` | `numeric(8,3)` | NO | `` | Inclusive lower capacity bound. |
| `max_capacity_kw` | `numeric(8,3)` | YES | `` | Exclusive upper capacity bound; NULL means open-ended. |
| `rate_amount` | `numeric(14,2)` | YES | `` | Monetary rate interpreted according to the parent calculation_method. |
| `rate_percent` | `numeric(7,4)` | YES | `` | Percentage rate interpreted according to the parent calculation_method. |
| `sort_order` | `integer` | NO | `0` | Administrative display and calculation-tier order. |
| `capacity_range` | `numrange` | YES | `numrange(min_capacity_kw, max_capacity_kw, '[)'::text)` | Generated half-open capacity range used to prevent active overlaps. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
