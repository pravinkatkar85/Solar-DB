# Table: `solar_app.ref_tax_rules`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Effective-dated tax-rule components grouped by tax_group_code. Rates are deployment configuration; transaction rows preserve applied snapshots.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `tax_rule_id` | `bigint` | NO | `` | Surrogate primary key. |
| `tax_rule_code` | `character varying(50)` | NO | `` | Stable code for one versioned tax component rule. |
| `tax_group_code` | `character varying(50)` | NO | `` | Groups components that apply together to a transaction. |
| `tax_component_code` | `character varying(50)` | NO | `` | Stable component identifier used by calculation contracts. |
| `tax_display_name` | `character varying(150)` | NO | `` | Configurable customer-facing component label. |
| `country_id` | `bigint` | NO | `` | Country jurisdiction. |
| `state_id` | `bigint` | YES | `` | Optional state or region jurisdiction. |
| `tax_classification_code` | `character varying(30)` | YES | `` | Optional product or service tax classification matched by the rule. |
| `calculation_method` | `character varying(20)` | NO | `` | PERCENTAGE or FIXED_AMOUNT; application and compounding policy remains deployment configuration. |
| `rate_percent` | `numeric(7,4)` | YES | `` | Configured percentage when calculation_method is PERCENTAGE. |
| `rate_amount` | `numeric(14,2)` | YES | `` | Configured amount when calculation_method is FIXED_AMOUNT. |
| `currency_code` | `character(3)` | YES | `` | Currency of a fixed rate amount; NULL for percentage rules. |
| `priority` | `integer` | NO | `` | Precedence when multiple applicable rules are configured. |
| `effective_from` | `date` | NO | `` | Inclusive rule-version start date. |
| `effective_to` | `date` | YES | `` | Inclusive rule-version end date; NULL means open-ended. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE excludes the version from rule resolution. |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
