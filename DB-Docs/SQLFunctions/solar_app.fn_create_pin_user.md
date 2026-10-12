# Function: `solar_app.fn_create_pin_user(p_payload JSONB)`

- Schema: `solar_app`
- Source: `DB-Objects/SQLFunctions/solar_app.fn_create_pin_user.sql`
- Loader: `SQLScripts/02_functions.sql`
- Requires: `pgcrypto` installed in schema `public`

Creates one active customer in `user_details`. The 4-digit PIN is hashed with bcrypt (`public.crypt` / `gen_salt('bf', 10)`). The plaintext PIN is not stored and is not written to `log_sql_functions`.

This is self-registration for PIN login. It is not `fn_create_user_details`, which remains the Path B wizard.

## Input

| Field | Required | Rule |
| --- | --- | --- |
| `api_endpoint` | yes | String, 1 to 255 characters |
| `logged_in_user_id` | no | Blank becomes `SYSTEM` |
| `country_id` | yes | Digits. Active `ref_countries.country_id` |
| `national_number` | yes | Digits. Length and `national_phone_regex` come from that country |
| `full_name` | yes | Trimmed, 1 to 150 characters |
| `pin` | yes | Exactly 4 digits |

The mobile number stored is `phone_code || national_number`. Role is `ROLE_CUSTOMER`, account status is `ACCT_ACTIVE`, and registration source is `REG_SELF_APP`. `admin_registered` is set TRUE because this call completes self-registration.

## Output

| Case | `code` | `data` |
| --- | --- | --- |
| Created | 200 | `{ "user_id", "full_name" }` |
| Invalid input | 400 | `null` |
| Active mobile already exists | 409 | `null` |
| Reference data or unexpected failure | 500 | `null` |

`data` never includes the PIN or `pin_hash`.
