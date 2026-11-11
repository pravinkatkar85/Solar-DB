# solar_app.fn_get_kyc_document_details

Lists active `DOCUMENT_TYPES` checklist rows and active `kyc_document_details`.

## Authorization

Session is resolved from `jwt_token_hash` only. Payload `user_id` / role values are not trusted. Role comes from `user_details.role_ref_data_id` → `ref_data.data_code`.

| Session role | Documents returned |
| --- | --- |
| `ROLE_ADMIN` | Active documents across customers. Admin may have no `customer_details` row. |
| Other active roles | Only documents for the session user's active `customer_details` row. Empty list when the user has no customer record. |

## Optional filters

| Field | Notes |
| --- | --- |
| `site_id` | Non-admin: must be owned. Admin: any active site. Matching site rows plus customer-level rows with null `site_id` are included. |
| `status_code` | One of `KYC_PENDING`, `KYC_APPROVED`, `ACTION_REQUIRED` (must exist in `DOCUMENT_VERIFICATION_STATUSES`). |

## Response `data`

- `document_types` — active `DOCUMENT_TYPES` checklist
- `documents` — newest first (`created_on` DESC). Each item includes existing fields plus schema-backed `customer_id`, `customer_code`, and `billing_name` from `customer_details`.

Status codes remain `KYC_PENDING`, `KYC_APPROVED`, and `ACTION_REQUIRED`.

## Codes

- 200 documents loaded (including empty)
- 400 payload / site id / status code
- 401 authentication is required
- 403 inactive or suspended account
- 404 site not found / not owned
- 500 unexpected failure

Source: `DB-Objects/SQLFunctions/solar_app.fn_get_kyc_document_details.sql`. Do not install until approved.
