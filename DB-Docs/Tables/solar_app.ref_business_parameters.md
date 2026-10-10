# Table: `solar_app.ref_business_parameters`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Typed, effective-dated business and operational configuration, including calculator settings and approved feature flags. Credentials and endpoints are prohibited.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `parameter_id` | `bigint` | NO | `` | Surrogate primary key. |
| `parameter_code` | `character varying(50)` | NO | `` | Stable internal code consumed by application contracts. |
| `parameter_name` | `character varying(150)` | NO | `` | Configurable administrator-facing label. |
| `value_type` | `character varying(20)` | NO | `` | Selects the single populated value column: NUMERIC, TEXT, BOOLEAN, or JSON. |
| `numeric_value` | `numeric(18,6)` | YES | `` | Numeric value when value_type is NUMERIC. |
| `text_value` | `text` | YES | `` | Text value when value_type is TEXT. |
| `boolean_value` | `boolean` | YES | `` | Boolean value, including an approved feature flag, when value_type is BOOLEAN. |
| `json_value` | `jsonb` | YES | `` | Structured value when value_type is JSON and a scalar is insufficient. |
| `parameter_unit` | `character varying(30)` | YES | `` | Configurable unit code or display hint. |
| `parameter_desc` | `character varying(500)` | YES | `` | Purpose, scope, and approved usage of the parameter. |
| `admin_manageable_ind` | `boolean` | NO | `true` | TRUE when an authorized business administrator may maintain this parameter. |
| `effective_from` | `date` | NO | `` | Inclusive date from which this version applies. |
| `effective_to` | `date` | YES | `` | Inclusive final date; NULL means open-ended. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE excludes the version from rule resolution. |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
