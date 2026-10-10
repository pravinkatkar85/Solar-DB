# Table: `solar_app.organization_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Single-company deployment profile for runtime branding and non-secret regional defaults. Native package identity, endpoints, and credentials remain deployment configuration.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `organization_id` | `bigint` | NO | `` | Surrogate primary key. |
| `legal_name` | `character varying(200)` | NO | `` | Legal company name used on business documents. |
| `display_name` | `character varying(200)` | NO | `` | Customer-facing company name. |
| `runtime_app_name` | `character varying(150)` | NO | `` | Runtime application title shown inside the app; launcher name is build configuration. |
| `primary_logo_url` | `character varying(500)` | YES | `` | Managed URL for the primary runtime logo. |
| `secondary_logo_url` | `character varying(500)` | YES | `` | Optional managed URL for an alternate logo. |
| `primary_theme_color` | `character varying(9)` | YES | `` | Runtime primary theme color in hexadecimal RGB or RGBA notation. |
| `secondary_theme_color` | `character varying(9)` | YES | `` | Runtime secondary theme color in hexadecimal RGB or RGBA notation. |
| `support_email` | `character varying(255)` | YES | `` | Customer-support email displayed at runtime. |
| `support_phone_e164` | `character varying(16)` | YES | `` | Optional customer-support phone in normalized E.164 format. |
| `default_country_id` | `bigint` | NO | `` | Deployment default country for country-dependent configuration. |
| `default_currency_code` | `character(3)` | NO | `` | Deployment default ISO currency code. |
| `locale_code` | `character varying(20)` | YES | `` | Optional default locale code for formatting and labels. |
| `time_zone_name` | `character varying(100)` | NO | `` | Deployment IANA time-zone name. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. A partial unique index permits only one active deployment profile. |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
