# solar_app.fn_create_user_details

Path B admin registration wizard. Creates one customer login (`user_details`), legal party (`customer_details`), one or more sites with equipment, one MANUAL order in Installed/Commissioned status, `user_site_access_details` rows, and enqueues `NTF_ACCOUNT_READY`.

Session identity and role come only from `jwt_token_hash` → `log_user_sessions` → `user_details`. Payload role, `logged_in_user_id`, and ownership fields are not trusted. `ROLE_ADMIN` is required.

`pin_hash` is always inserted as SQL `NULL`. A non-empty payload `pin` or `pin_hash` is rejected. This is not `fn_create_pin_user`.

## Payload

| Field | Required | Notes |
| --- | --- | --- |
| `api_endpoint` | yes | 1–255 characters |
| `jwt_token_hash` | yes | 64-char hex of the admin session JWT |
| `logged_in_user_id` / `user_id` | no | If present must match session user id |
| `country_id` | yes | Active `ref_countries.country_id` |
| `national_number` | yes | Digits; length/regex from that country |
| `full_name` | yes | 1–150 characters |
| `customer_code` | yes | 1–30 characters; unique among customers |
| `billing_name` | no | Max 150; defaults to `full_name` when blank |
| `tax_registration_no` | no | Max 50 |
| `billing_address_line1` / `billing_address_line2` | no | Max 255 |
| `billing_pincode_id` | no | Active `ref_pincodes` |
| `order_no` | yes | 1–30 characters; unique |
| `order_status_code` | yes | `ORD_INSTALLED` or `ORD_COMMISSIONED` |
| `currency_code` | yes | Active `ref_currencies.currency_code` |
| `gross_amount` | no | `>= 0`; default `0` |
| `remarks` | no | Max 500 |
| `order_lines` | no | Array of line objects (see below) |
| `sites` | yes | Non-empty array (see below) |
| `pin` / `pin_hash` | forbidden | Must be absent or blank |

### Site object

| Field | Required | Notes |
| --- | --- | --- |
| `site_name` | yes | Max 150 |
| `address_line1` | yes | Max 255 |
| `address_line2` | no | Max 255 |
| `pincode_id` / `city_id` / `district_id` / `state_id` | no | Active geo FKs when provided |
| `latitude` / `longitude` | pair | Both empty or both valid |
| `discom_id` | no | Active `ref_discoms` |
| `consumer_number` / `meter_number` | no | Max 50 |
| `sanctioned_load_kw` | no | `>= 0` |
| `connection_type_ref_data_id` | no | `CONNECTION_TYPES` |
| `installation_status_code` | yes | `INST_INSTALLED` or `INST_COMMISSIONED` |
| `commissioning_on` | yes | `YYYY-MM-DD` |
| `is_default` | no | At most one `true`; otherwise first site is default |
| `equipment` | yes | Non-empty array |

### Equipment object

| Field | Required | Notes |
| --- | --- | --- |
| `equipment_type_code` | yes | Active `EQUIPMENT_TYPES` code (e.g. `EQ_PANEL`) |
| `product_id` | no | Active catalogue product |
| `brand_ref_data_id` | no | `EQUIPMENT_BRANDS` |
| `model_name` | no | Max 150 |
| `serial_no` / `barcode` / `monitoring_dongle_id` | no | Max 80 |
| `quantity` | no | `> 0`; default `1` |
| `panel_wattage` / `inverter_capacity_kw` / `battery_capacity_ah` | no | Numeric |
| `phase_type_ref_data_id` | no | `PHASE_TYPES` |
| `structure_type_ref_data_id` | no | `STRUCTURE_TYPES` |
| `commissioned_on` | no | `YYYY-MM-DD`; defaults to site `commissioning_on` |

### Order line object

| Field | Required | Notes |
| --- | --- | --- |
| `line_no` | yes | Positive integer; unique per order |
| `line_desc` | yes | Max 255 |
| `product_id` | no | Active catalogue product |
| `quantity` | no | `> 0`; default `1` |
| `unit_rate` | no | Default `0` |
| `line_amount` | yes | Numeric |
| `tax_classification_code` | no | Max 30 |

## Fixed server values

- Role `ROLE_CUSTOMER`
- Account `ACCT_ACTIVE`
- `admin_registered = TRUE`
- Registration source `REG_ADMIN_POST_INSTALL`
- `pin_hash = NULL`
- Order source `MANUAL`
- Site access role `ACCESS_OWNER`
- Notification type `NTF_ACCOUNT_READY` via `fn_create_notification_details`

## Codes

- 200 created
- 400 validation (including forbidden PIN)
- 401 authentication required / invalid session
- 403 not an active admin
- 409 duplicate mobile, customer code, or order number
- 500 unexpected failure / missing reference data / notification enqueue failure

## Response `data` (200)

`user_id`, `customer_id`, `customer_code`, `order_id`, `order_no`, `site_ids` (array), `equipment_ids` (array), `notification_id`.

Source: `DB-Objects/SQLFunctions/solar_app.fn_create_user_details.sql`. Loader line in `SQLScripts/02_functions.sql`. Do not install until approved.
