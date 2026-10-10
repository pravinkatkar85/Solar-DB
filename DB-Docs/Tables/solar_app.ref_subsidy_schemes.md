# Table: `solar_app.ref_subsidy_schemes`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Effective-dated subsidy scheme definitions. Deployment-approved eligibility and caps are configuration, not schema constants.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `subsidy_scheme_id` | `bigint` | NO | `` | Surrogate primary key. |
| `scheme_code` | `character varying(50)` | NO | `` | Stable internal scheme code; versioned by effective date. |
| `scheme_name` | `character varying(150)` | NO | `` | Configurable display name. |
| `country_id` | `bigint` | NO | `` | Country whose rules authorize the scheme. |
| `state_id` | `bigint` | YES | `` | Optional state or region restriction; NULL means country-level. |
| `calculation_method` | `character varying(30)` | NO | `` | Approved calculation family; formulas and rates are supplied as configuration. |
| `maximum_benefit_amount` | `numeric(14,2)` | YES | `` | Optional maximum benefit for this scheme version. |
| `currency_code` | `character(3)` | NO | `` | Currency of configured monetary rates and cap. |
| `eligibility_json` | `jsonb` | NO | `'{}'::jsonb` | Deployment-approved structured eligibility criteria; no production criteria are embedded in DDL. |
| `effective_from` | `date` | NO | `` | Inclusive scheme-version start date. |
| `effective_to` | `date` | YES | `` | Inclusive scheme-version end date; NULL means open-ended. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE excludes the version from rule resolution. |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
