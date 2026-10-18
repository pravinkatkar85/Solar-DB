# Function: `solar_app.fn_update_user_pin(p_payload JSONB)`

- Schema: `solar_app`
- Source: `DB-Objects/SQLFunctions/solar_app.fn_update_user_pin.sql`
- Loader: `SQLScripts/02_functions.sql`
- Requires: `pgcrypto` installed in schema `public`

Changes the PIN for the user bound to one active session. The session is found with `log_user_sessions.jwt_token_hash`. A `user_id` or `logged_in_user_id` in the payload is not the identity. If either value is present and differs from the session user, the call is rejected.

The current PIN is checked with `public.crypt(old_pin, pin_hash)`. The new value is stored with `public.crypt(new_pin, public.gen_salt('bf', 10))`. Plaintext PINs and the session hash are not written to `log_sql_functions`.

This is self-service change PIN. It is not an administrator reset and it does not accept a mobile number alone.

## Input

| Field | Required | Rule |
| --- | --- | --- |
| `api_endpoint` | yes | String, 1 to 255 characters |
| `jwt_token_hash` | yes | 64 lowercase hex characters. Must match exactly one `ACTIVE` session with a user |
| `old_pin` | yes | Exactly 4 digits. Checked against the session user's `pin_hash` |
| `new_pin` | yes | Exactly 4 digits |
| `confirm_pin` | yes | Must equal `new_pin` |
| `logged_in_user_id` | no | If present, must equal the session user id. It is not used to find the user |
| `user_id` | no | If present, must equal the session user id. It is not used to find the user |

The future API must derive `jwt_token_hash` from a signature-checked bearer token. The client must not choose this hash or the user id.

## Output

| Case | `code` | `message` | `data` |
| --- | --- | --- | --- |
| Updated | 200 | `PIN updated` | `{ "user_id" }` |
| Payload, token format, or PIN format is not valid | 400 | Validation message | `null` |
| New PIN and confirmation differ | 400 | `PIN entries do not match` | `null` |
| No single active session, identity fields disagree, or the current PIN is wrong | 401 | `Authentication is required` or `The current PIN is incorrect` | `null` |
| Inactive or `ACCT_SUSPENDED` account | 403 | `This account cannot change its PIN` | `null` |
| Unexpected failure | 500 | `PIN could not be updated` | `null` |

`data` never includes a PIN or `pin_hash`. Failed attempts are not counted and `lockout_until` is not changed.

## Not in this function

Administrator reset and forgot-PIN are not implemented. There is no database check that can prove an administrator is calling, because a caller-supplied role or user id is not authorization and this database cannot verify the JWT signature.
