# Table: `solar_app.ref_amc_plans`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Effective-dated AMC plan catalogue. Each price covers the full configured duration; collection remains offline.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `amc_plan_id` | `bigint` | NO | `` | Surrogate primary key. |
| `plan_code` | `character varying(30)` | NO | `` | Stable plan code shared by effective-dated versions. |
| `plan_name` | `character varying(150)` | NO | `` | Customer-facing plan name (Basic Cleaning, Comprehensive, …). |
| `plan_desc` | `character varying(500)` | YES | `` | What the plan includes. |
| `duration_months` | `integer` | NO | `` | Contract length in months. |
| `includes_breakdown` | `boolean` | NO | `` | TRUE if breakdown visits are included. |
| `includes_cleaning` | `boolean` | NO | `` | TRUE if routine cleaning is included. |
| `free_visit_count` | `integer` | NO | `` | How many site visits this subscription covers at no charge (configurable per plan). 0 = none free. |
| `free_visit_radius_km` | `numeric(8,2)` | YES | `` | Optional km cap from office for a free entitlement visit; beyond this the visit becomes chargeable even on AMC. |
| `plan_price` | `numeric(12,2)` | NO | `` | List price for the complete duration_months term. |
| `currency_code` | `character(3)` | NO | `` | Currency of plan_price. |
| `effective_from` | `date` | NO | `` | Inclusive plan-version start date. |
| `effective_to` | `date` | YES | `` | Inclusive plan-version end date; NULL means open-ended. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
