# solar_app.fn_update_site_details

Updates Module 3.1 KYC profile fields on one active `site_details` row owned by the session customer's 1:1 customer record. The user is the single active session for `jwt_token_hash`. A payload `user_id` is not trusted.

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | API route string |
| `jwt_token_hash` | yes | 64-char hex session hash |
| `site_id` | yes | Owned active site |
| `address_line1` | yes | Max 255 |
| `address_line2` | no | Max 255 |
| `latitude` / `longitude` | pair | Both empty or both valid GPS values |
| `discom_id` | no | Active `ref_discoms` row |
| `consumer_number` | no | Max 50 |
| `meter_number` | no | Max 50 |
| `sanctioned_load_kw` | no | `>= 0` |
| `connection_type_ref_data_id` | no | `CONNECTION_TYPES` |

Installation status, commissioning date, geo FKs (pincode/city/district/state), and order links are not changed.

## Codes

- 200 site profile updated
- 400 validation
- 401 authentication is required
- 403 inactive/suspended account or missing customer
- 404 site not owned
- 500 unexpected failure

Source: `DB-Objects/SQLFunctions/solar_app.fn_update_site_details.sql`. Loader line in `SQLScripts/02_functions.sql`. Do not install until approved.
