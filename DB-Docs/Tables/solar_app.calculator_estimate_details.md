# Table: `solar_app.calculator_estimate_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Persisted feasibility calculator runs so quotes can reproduce subsidy and savings.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `estimate_id` | `bigint` | NO | `` | Surrogate primary key. |
| `user_id` | `bigint` | YES | `` | Logged-in user; NULL for anonymous calculator runs. |
| `monthly_bill_amount` | `numeric(12,2)` | NO | `` | Monthly electricity bill input in currency_code. |
| `rooftop_area` | `numeric(12,2)` | NO | `` | Shade-free rooftop area entered by the user. |
| `area_unit` | `character varying(10)` | NO | `` | SQFT or SQM. |
| `connection_type_ref_data_id` | `bigint` | NO | `` | FK to CONNECTION_TYPES. |
| `state_id` | `bigint` | YES | `` | State used to pick subsidy overlay. |
| `recommended_capacity_kw` | `numeric(8,3)` | NO | `` | Engine recommended system size. |
| `estimated_gross_cost` | `numeric(14,2)` | NO | `` | Estimated project cost before subsidy. |
| `estimated_subsidy_amount` | `numeric(14,2)` | NO | `0` | Estimated DBT subsidy. |
| `net_investment_cost` | `numeric(14,2)` | NO | `` | Gross minus subsidy. |
| `estimated_monthly_savings` | `numeric(12,2)` | YES | `` | Estimated monthly bill savings. |
| `estimated_annual_savings` | `numeric(12,2)` | YES | `` | Estimated annual savings. |
| `payback_months` | `integer` | YES | `` | Simple payback in months. |
| `co2_reduction_tons_year` | `numeric(10,3)` | YES | `` | Estimated CO₂ reduction (tons/year). |
| `area_insufficient_ind` | `boolean` | NO | `false` | TRUE if rooftop area is below the effective configured area rule. |
| `subsidy_slab_id` | `bigint` | YES | `` | Slab used so historical quotes stay explainable. |
| `currency_code` | `character(3)` | NO | `` | Currency snapshot used for every monetary estimate column. |
| `applied_parameters_json` | `jsonb` | NO | `'{}'::jsonb` | Immutable snapshot of effective business parameter codes and values used for the estimate. |
| `subsidy_rule_snapshot_json` | `jsonb` | NO | `'{}'::jsonb` | Immutable snapshot of the applied subsidy scheme, slab, method, rate, cap, and eligibility outcome. |
| `estimate_json` | `jsonb` | NO | `'{}'::jsonb` | Full breakdown JSON for PDF quote rendering. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
