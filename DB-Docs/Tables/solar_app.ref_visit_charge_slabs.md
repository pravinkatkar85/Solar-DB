# Table: `solar_app.ref_visit_charge_slabs`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Effective-dated site-visit charges by non-overlapping half-open distance band. A purpose-specific row takes precedence over a NULL-purpose default; free entitlement can override the configured amount.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `visit_charge_slab_id` | `bigint` | NO | `` | Surrogate primary key. |
| `visit_purpose_ref_data_id` | `bigint` | YES | `` | Optional SITE_VISIT_PURPOSES override; NULL applies to every purpose unless a more specific slab exists. |
| `min_distance_km` | `numeric(8,2)` | NO | `` | Inclusive lower km of this band. |
| `max_distance_km` | `numeric(8,2)` | YES | `` | Exclusive upper km of this band; NULL means the final open-ended band. |
| `charge_amount` | `numeric(12,2)` | NO | `` | Configured offline visit fee in currency_code. |
| `currency_code` | `character(3)` | NO | `` | Currency of charge_amount. |
| `is_free_ind` | `boolean` | NO | `` | TRUE identifies an explicitly zero-priced configured band. |
| `effective_from` | `date` | NO | `` | Inclusive rule-version start date. |
| `effective_to` | `date` | YES | `` | Inclusive rule-version end date; NULL means open-ended. |
| `sort_order` | `integer` | NO | `0` | Admin display order. |
| `distance_range` | `numrange` | YES | `numrange(min_distance_km, max_distance_km, '[)'::text)` | Generated half-open distance range used for overlap protection. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
