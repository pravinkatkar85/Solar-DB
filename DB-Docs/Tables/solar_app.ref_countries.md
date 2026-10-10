# Table: `solar_app.ref_countries`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: ISO country master with configurable national phone, postal-code, and tax-registration validation metadata.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `country_id` | `bigint` | NO | `` | Surrogate primary key. |
| `country_code` | `character(2)` | NO | `` | ISO 3166-1 alpha-2 code. |
| `country_name` | `character varying(100)` | NO | `` | Configurable display name. |
| `phone_code` | `character varying(8)` | NO | `` | International dialing prefix including the plus sign. |
| `national_phone_min_length` | `smallint` | NO | `` | Minimum national-number digit count used by validation functions. |
| `national_phone_max_length` | `smallint` | NO | `` | Maximum national-number digit count, capped by the E.164 technical limit. |
| `national_phone_regex` | `character varying(255)` | YES | `` | Optional deployment-approved regular expression for the national number. |
| `postal_code_regex` | `character varying(255)` | YES | `` | Optional deployment-approved regular expression for postal codes. |
| `tax_registration_label` | `character varying(100)` | YES | `` | Country-specific display label for a customer tax registration number. |
| `tax_registration_regex` | `character varying(255)` | YES | `` | Optional deployment-approved tax registration validation expression. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
