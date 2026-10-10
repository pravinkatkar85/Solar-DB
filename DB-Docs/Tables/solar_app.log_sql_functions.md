# Table: `solar_app.log_sql_functions`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: PL/pgSQL function execution audit written by fn_log_function_execution.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `function_log_id` | `bigint` | NO | `` | Surrogate primary key. |
| `api_endpoint` | `character varying(255)` | YES | `` | Calling API endpoint for correlation. |
| `function_name` | `character varying(150)` | NO | `` | PL/pgSQL function name (fn_*). |
| `logged_in_user_id` | `character varying(50)` | YES | `` | String actor id from the JSON envelope. |
| `user_id` | `bigint` | YES | `` | Optional FK to user_details. |
| `request_payload` | `jsonb` | YES | `` | p_payload snapshot passed into the function. |
| `execution_status` | `character varying(20)` | NO | `` | SUCCESS or ERROR from the function. |
| `error_message` | `text` | YES | `` | SQLERRM when the function hit EXCEPTION. |
| `sql_state` | `character varying(10)` | YES | `` | PostgreSQL SQLSTATE of the exception. |
| `execution_time_ms` | `integer` | YES | `` | Elapsed milliseconds inside the function. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
