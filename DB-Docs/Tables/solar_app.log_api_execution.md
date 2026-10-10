# Table: `solar_app.log_api_execution`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: One audit row per API invocation (endpoint, latency, payload snapshot, SUCCESS/ERROR).

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `api_log_id` | `bigint` | NO | `` | Surrogate primary key. |
| `api_endpoint` | `character varying(255)` | NO | `` | HTTP path or logical endpoint name from the payload. |
| `http_method` | `character varying(10)` | YES | `` | GET, POST, PUT, DELETE, etc. |
| `logged_in_user_id` | `character varying(50)` | YES | `` | String actor id from the JSON envelope. |
| `user_id` | `bigint` | YES | `` | Optional FK to user_details when the actor is a known user. |
| `client_ip` | `character varying(45)` | YES | `` | Client IP captured by the API proxy. |
| `request_payload` | `jsonb` | YES | `` | Request JSON snapshot (redact secrets in functions). |
| `response_payload` | `jsonb` | YES | `` | Response JSON snapshot. |
| `http_status` | `integer` | YES | `` | HTTP status returned to the client. |
| `execution_status` | `character varying(20)` | NO | `` | SUCCESS or ERROR at the API layer. |
| `error_message` | `text` | YES | `` | Error text when execution_status is ERROR. |
| `execution_time_ms` | `integer` | YES | `` | Elapsed milliseconds for the call. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
