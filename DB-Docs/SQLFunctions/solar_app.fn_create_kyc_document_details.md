# solar_app.fn_create_kyc_document_details

Creates one active KYC upload for the session customer at `KYC_PENDING`. Client-supplied verification status, verifier, and rejection comment are ignored.

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | |
| `jwt_token_hash` | yes | |
| `document_type_ref_data_id` | yes | `DOCUMENT_TYPES` |
| `file_url` | yes | Max 500 |
| `file_size_bytes` | yes | `> 0` and `<=` BRD 2 MB (`2097152`), optionally lowered by active `DEV_KYC_UPLOAD_MAX_BYTES` |
| `mime_type` | no | Max 100 |
| `site_id` | no | Owned active site |

An approved non-development upload-limit parameter code is not defined yet; only the BRD ceiling and the documented development fixture are used.

## Codes

- 200 uploaded
- 400 validation / size
- 401 authentication is required
- 403 inactive account or missing customer
- 404 site not owned
- 500 unexpected failure

Source: `DB-Objects/SQLFunctions/solar_app.fn_create_kyc_document_details.sql`. Do not install until approved.
