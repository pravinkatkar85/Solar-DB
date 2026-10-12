# Function: `solar_app.fn_create_pin_session(p_payload JSONB)`

- Schema: `solar_app`
- Source: `DB-Objects/SQLFunctions/solar_app.fn_create_pin_session.sql`
- Loader: `SQLScripts/02_functions.sql`
- Requires: `pgcrypto` installed in schema `public`

Verifies a national mobile number and 4-digit PIN against `user_details.pin_hash`. On success it inserts `log_user_sessions` with `session_status = ACTIVE` and the supplied `jwt_token_hash`.

The API creates the raw session token and sends only its SHA-256 hex digest. This function never receives or stores the raw token or the plaintext PIN. Both are omitted from `log_sql_functions`.

## Input

| Field | Required | Rule |
| --- | --- | --- |
| `api_endpoint` | yes | String, 1 to 255 characters |
| `country_id` | yes | Digits. Active country |
| `national_number` | yes | Digits, validated with that country's phone metadata |
| `pin` | yes | Exactly 4 digits |
| `jwt_token_hash` | yes | 64 lowercase hex characters |

## Output

Unknown mobile, wrong PIN, inactive user, suspended account, missing PIN hash, and an unexpired `lockout_until` all return the same message.

| Case | `code` | `data` |
| --- | --- | --- |
| Signed in | 200 | `user_id`, `full_name`, `role_code`, `role_name`, `session_id` |
| Country or token hash is not valid | 400 | `null` |
| Credentials or account cannot sign in | 401 | `null` |
| Unexpected failure | 500 | `null` |

`data` does not include the PIN, `pin_hash`, or session token.
