# SolarDB — Database Design Document

**Database:** `SolarDB`  
**Schema:** `solar_app`  
**Owner:** `solar_app_user`  
**Engine:** PostgreSQL 16+  
**Architecture:** Database-centric (business logic in PL/pgSQL functions; Node.js is a thin JSON proxy; Flutter is the client)  
**Related specs:** `.cursorrules`, `DB_REQUIREMENTS.md`, `Solar-Docs/BRD.md`  
**DDL for review:** `Solar-DB/DDL_SCHEMA.md`  
**Physical execute script (after approval):** `Solar-DB/01_schema.sql`

This document describes **why** each table exists, **what** it stores, whether it is **reference, transaction, or log** data, and **how** it relates to other tables. Column-level SQL comments live in the DDL; this file is the business-facing design map.

---

## 1. Design principles

| Rule | Implementation |
| --- | --- |
| Schema | All objects live in `solar_app`. Session `search_path` is `solar_app, public`. |
| Transaction tables | Suffix `_details` (operational records that grow over time). |
| Generic dropdowns | Normalized pair `ref_data_categories` + `ref_data`, served by one function `fn_get_dropdown_data`. |
| Standalone masters | Prefix `ref_` when the entity has extra attributes or geo hierarchy that does not fit generic `ref_data`. |
| Logs | Prefix `log_`. Sessions are `log_user_sessions` (not `user_session_details`) to keep the `log_` convention. |
| Primary keys | `BIGINT GENERATED ALWAYS AS IDENTITY`. |
| Soft delete | `active_ind BOOLEAN NOT NULL DEFAULT TRUE` on **every** table. Unique keys that must survive re-create use **partial unique indexes** (`WHERE active_ind = TRUE`). |
| Audit | Every table has `created_by`, `updated_by` (`VARCHAR(50)`, default `'SYSTEM'`), `created_on`, `updated_on` (`TIMESTAMPTZ`). These are **not** FKs to `user_details` — they match the JSON envelope `logged_in_user_id`. |
| No triggers | `updated_on` / `updated_by`, OTP lockout, free-service lapse, ticket numbers, and invoice balances are updated **only** inside SQL functions. |
| FK delete policy | `RESTRICT` on masters and operational parents; `CASCADE` on owned children (lines, media, history); `SET NULL` on optional audit/conversion links. |
| Status / type codes | Stored as FK to `ref_data.ref_data_id`, not as free-text enums, except a few tightly constrained workflow flags (`job_type`, `contract_status`) where a CHECK is safer than a seed-order dependency. |

### 1.1 Data class legend

| Class | Meaning |
| --- | --- |
| **Reference** | Seeded or admin-maintained lookup. Relatively static. Feeds dropdowns and validations. |
| **Transaction** | Business events and entities created by users/operations (leads, tickets, invoices). |
| **Log** | Observability / security audit. Append-heavy; rarely updated except session/OTP consume flags. |

### 1.2 Intended `ref_data` categories (seeded later in `03_seed_data.sql`)

`USER_ROLES`, `APP_LANGUAGES`, `CONNECTION_TYPES`, `LEAD_STATUSES`, `QUOTE_STATUSES`, `SITE_VISIT_STATUSES`, `SITE_VISIT_PURPOSES`, `DOCUMENT_TYPES`, `DOCUMENT_VERIFICATION_STATUSES`, `EQUIPMENT_TYPES`, `EQUIPMENT_BRANDS`, `PHASE_TYPES`, `STRUCTURE_TYPES`, `WARRANTY_TYPES`, `SERVICE_TYPES`, `SERVICE_SLOT_WINDOWS`, `SERVICE_REQUEST_STATUSES`, `MILESTONE_STATUSES`, `COMPLAINT_CATEGORIES`, `COMPLAINT_SEVERITIES`, `TICKET_STATUSES`, `JOB_STATUSES`, `INVOICE_CATEGORIES`, `INVOICE_STATUSES`, `PAYMENT_METHODS`, `PAYMENT_STATUSES`, `INSTALLATION_STATUSES`, `SITE_ACCESS_ROLES`, `PRODUCT_CATEGORIES`, `PRODUCT_ENQUIRY_STATUSES`, `USER_ACCOUNT_STATUSES`, `ORDER_STATUSES`, `FOLLOWUP_TYPES`, `FOLLOWUP_STATUSES`, `REGISTRATION_SOURCES`, `NOTIFICATION_TYPES`, `NOTIFICATION_CHANNELS`, `NOTIFICATION_DELIVERY_STATUSES`.

---

## 2. Module-wise table inventory

Implementation order follows the BRD roadmap. **Physical CREATE order** is 9 → 1 → 10 → 2 → **11** → 3–8 so foreign keys compile.

### Phase 1 — Foundation

| Module | Table | Class |
| --- | --- | --- |
| **9 — Dynamic master & dropdowns** | `ref_data_categories` | Reference |
| | `ref_data` | Reference |
| | `ref_dropdown_config` | Reference (metadata engine) |
| | `ref_countries` | Reference |
| | `ref_states` | Reference |
| | `ref_districts` | Reference |
| | `ref_cities` | Reference |
| | `ref_pincodes` | Reference |
| | `ref_discoms` | Reference |
| | `ref_calculator_params` | Reference |
| | `ref_subsidy_slabs` | Reference |
| | `ref_amc_plans` | Reference |
| | `ref_checklist_items` | Reference |
| | `ref_office_locations` | Reference |
| | `ref_visit_charge_slabs` | Reference |
| **1 — Auth & profile** | `user_details` | Transaction |
| | `technician_details` | Transaction |
| **10 — Logging & sessions** | `log_api_execution` | Log |
| | `log_sql_functions` | Log |
| | `log_user_sessions` | Log |
| | `log_otp_attempts` | Log |
| **13 — Notifications** | `notification_details` | Transaction (in-app inbox) |
| | `log_notification_delivery` | Log (push send attempts) |

### Phase 2 — Customer & onboarding

| Module | Table | Class |
| --- | --- | --- |
| **2 — Calculator & leads** | `calculator_estimate_details` | Transaction |
| | `lead_details` | Transaction |
| | `quote_details` | Transaction |
| | `quote_line_details` | Transaction (child) |
| | `site_visit_details` | Transaction |
| **11 — Product catalogue & enquiry** | `product_details` | Transaction |
| | `product_media_details` | Transaction (child) |
| | `product_enquiry_details` | Transaction |
| **3 — KYC & sites** | `customer_details` | Transaction |
| | `site_details` | Transaction |
| | `user_site_access_details` | Transaction |
| | `kyc_document_details` | Transaction |
| **4 — Assets** | `equipment_details` | Transaction |
| | `warranty_details` | Transaction (child) |

### Phase 3 — Service engine & field work

| Module | Table | Class |
| --- | --- | --- |
| **5 — AMC & preventive service** | `amc_contract_details` | Transaction |
| | `service_milestone_details` | Transaction |
| | `service_request_details` | Transaction |
| **6 — Complaints** | `complaint_ticket_details` | Transaction |
| | `ticket_status_history_details` | Transaction (audit child) |
| | `ticket_media_details` | Transaction (child) |
| | `ticket_message_details` | Transaction (child) |
| **7 — Technician workspace** | `job_assignment_details` | Transaction |
| | `job_checklist_response_details` | Transaction (child) |
| | `job_media_details` | Transaction (child) |
| | `job_signoff_details` | Transaction (child) |
| | `spare_part_request_details` | Transaction |

### Phase 4 — Admin (offline money + console)

| Module | Table | Class |
| --- | --- | --- |
| **8 — Offline billing & payment register** | `invoice_details` | Transaction (admin-entered bill) |
| | `invoice_line_details` | Transaction (child, optional) |
| | `payment_details` | Transaction (offline receipt) |
| | `payment_milestone_details` | Transaction (child, optional instalments) |
| **12 — Admin console** | `order_details` | Transaction |
| | `order_line_details` | Transaction (child) |
| | `followup_details` | Transaction |

**Total: 56 tables** (15 reference + 36 transaction + 5 log).

Admin **reuses** existing tables for users, catalogue, KYC, service requests, tickets, jobs, invoices, and `ref_*`. Dedicated tables: **orders**, **follow-up tasks**, **notification inbox**, **notification delivery log**.

---

## 3. Relationship overview

```text
ref_countries
  └── ref_states
        ├── ref_districts
        │     ├── ref_cities ──► ref_pincodes
        │     └── ref_discoms (optional district = local circle)
        └── ref_discoms (statewide when district_id IS NULL)
        └── ref_subsidy_slabs (NULL state_id = central scheme)

ref_data_categories ──► ref_data ──► ref_data (parent_ref_data_id, in-list cascade)
ref_dropdown_config  (points at REF_DATA category_code OR a TABLE name)

user_details ──► technician_details (mandatory 1:1 when role = technician; same person, extra job fields)
user_details ──► customer_details (1:1 when role = customer)
customer_details ──► site_details (1:N, optional order_id)  ──► equipment_details (optional product_id) ──► warranty_details
                 └── kyc_document_details
user_details ◄──► site_details  via user_site_access_details  (multi-property selector)

calculator_estimate_details ──► lead_details ──► quote_details ──► quote_line_details
                             └── site_visit_details
lead_details.converted_customer_id ──► customer_details  (deferred FK)

product_details ──► product_media_details
user_details + product_details ──► product_enquiry_details
product_enquiry_details.converted_lead_id ──► lead_details  (optional)

site_details ──► amc_contract_details
             └── service_milestone_details ◄──► service_request_details
             └── complaint_ticket_details
                    ├── ticket_status_history_details
                    ├── ticket_media_details
                    └── ticket_message_details

service_request_details + complaint_ticket_details
        └── job_assignment_details
                ├── job_checklist_response_details
                ├── job_media_details
                ├── job_signoff_details
                └── spare_part_request_details

customer_details / site_details ──► invoice_details
                                      ├── invoice_line_details
                                      ├── payment_details
                                      └── payment_milestone_details
amc_contract_details.invoice_id ──► invoice_details  (deferred FK)

quote / enquiry / lead / admin ──► order_details ──► order_line_details
order_details.invoice optional later via invoice.related keys
followup_details ──► lead | enquiry | order | ticket | service_request | customer | user

user_details ──► notification_details ──► log_notification_delivery
business events call fn_create_notification_details (no triggers)

log_* optionally reference user_details (ON DELETE SET NULL)
```

---

## 4. Module 9 — Dynamic master & dropdown engine

**BRD need:** Every dropdown in Flutter comes from **one** API / **one** SQL function (`fn_get_dropdown_data`), including State → District → City and District → DISCOM cascades, without app releases.

### 4.1 `ref_data_categories`

| | |
| --- | --- |
| **Class** | Reference |
| **Why it exists** | Groups generic lookup lists (roles, ticket statuses, brands, GST payment methods, etc.) so the UI asks for a *category*, not a table name. |
| **Typical data** | One row per list: `USER_ROLES`, `COMPLAINT_CATEGORIES`, `INVOICE_STATUSES`. Code, display name, sort order. |
| **Relations** | Parent of `ref_data`. Referenced logically by `ref_dropdown_config.category_code`. |

### 4.2 `ref_data`

| | |
| --- | --- |
| **Class** | Reference |
| **Why it exists** | Stores the actual dropdown options. `parent_ref_data_id` supports **in-list** cascade (child options under a parent option in the same or another category). Extra attributes (icon, SLA hours, color) go in `extra_json` so we do not add columns per list. |
| **Typical data** | `ROLE_CUSTOMER` / Customer; `SEV_EMERGENCY` / Emergency; `SVC_PANEL_CLEANING` / Routine Panel Cleaning. |
| **Relations** | FK `category_id` → `ref_data_categories`. Self-FK `parent_ref_data_id` → `ref_data`. **Consumed by almost every transaction table** as `*_ref_data_id` status/type columns. |

### 4.3 `ref_dropdown_config`

| | |
| --- | --- |
| **Class** | Reference (configuration metadata) |
| **Why it exists** | Tells `fn_get_dropdown_data` *how* to build a list: generic `ref_data`, a dedicated `ref_*` table, parent filter column, sort, and Flutter cache TTL. Cascading geo lists cannot live only in `ref_data` because cities have `state_id` / `district_id` columns. |
| **Typical data** | `dropdown_code = STATES`, `source_type = TABLE`, `source_table = ref_states`, `value_column = state_id`, `label_column = state_name`. Child `CITIES` with `parent_dropdown_code = DISTRICTS`, `parent_filter_column = district_id`. |
| **Relations** | Logical only (codes, not FKs) to categories and tables. `extra_where_sql` is **DBA-maintained**; never concatenated from client JSON. |

### 4.4 `ref_countries`

| | |
| --- | --- |
| **Class** | Reference |
| **Why it exists** | Login screen country code (+91) and future multi-country address. Not generic `ref_data` because of ISO code and phone prefix. |
| **Typical data** | `IN`, India, `+91`. |
| **Relations** | Parent of `ref_states`, `user_details.country_id`. |

### 4.5 `ref_states`

| | |
| --- | --- |
| **Class** | Reference |
| **Why it exists** | First geo cascade parent; GST place-of-supply; subsidy slab overlay. |
| **Typical data** | Maharashtra (`MH`), GST state code `27`. |
| **Relations** | FK → `ref_countries`. Parent of `ref_districts`, `ref_cities`, `ref_pincodes`, `ref_discoms`, `ref_subsidy_slabs`, `site_details`, invoices. |

### 4.6 `ref_districts`

| | |
| --- | --- |
| **Class** | Reference |
| **Why it exists** | BRD cascade: State → District → City / DISCOM branch (e.g. Pune vs Mumbai circles). |
| **Typical data** | Pune, Nashik under Maharashtra. |
| **Relations** | FK → `ref_states`. Parent of `ref_cities`, `ref_pincodes`, optional `ref_discoms.district_id`. |

### 4.7 `ref_cities`

| | |
| --- | --- |
| **Class** | Reference |
| **Why it exists** | Address and lead location labels. `state_id` is denormalized so State → City queries skip district when the UI needs that shortcut. |
| **Typical data** | Pune, Pimpri-Chinchwad. |
| **Relations** | FK → `ref_districts`, `ref_states`. Parent of `ref_pincodes`. Used by `site_details`. |

### 4.8 `ref_pincodes`

| | |
| --- | --- |
| **Class** | Reference |
| **Why it exists** | Lead form “installation pincode” and technician routing. PIN format CHECK `^[1-9][0-9]{5}$`. |
| **Typical data** | `411001` → Pune / Pune district / Maharashtra. |
| **Relations** | FK → city, district, state. Used by `lead_details`, `site_details`. |

### 4.9 `ref_discoms`

| | |
| --- | --- |
| **Class** | Reference |
| **Why it exists** | Customer onboarding “Electricity Provider” dropdown. Statewide utility when `district_id` is NULL; circle/branch when set (MSEDCL vs Tata Power). |
| **Typical data** | `MSEDCL`, Maharashtra State Electricity Distribution Co. Ltd. |
| **Relations** | FK → `ref_states`, optional `ref_districts`. Used by `site_details.discom_id`. |

### 4.10 `ref_calculator_params`

| | |
| --- | --- |
| **Class** | Reference |
| **Why it exists** | Feasibility engine constants without code deploys: bill slider min/max, sq.ft per kW (100), tariff, CO₂ factor. |
| **Typical data** | `BILL_MIN = 500`, `SQFT_PER_KW = 100`. |
| **Relations** | None (standalone). Read by calculator SQL functions. |

### 4.11 `ref_subsidy_slabs`

| | |
| --- | --- |
| **Class** | Reference |
| **Why it exists** | PM Surya Ghar / state DBT rules (e.g. 3 kW residential cap). Dated slabs so old quotes stay explainable. |
| **Typical data** | Central residential 0–3 kW fixed amount; state_id NULL = nationwide. |
| **Relations** | Optional FK → `ref_states`. FK → `ref_data` (connection type). Referenced by `calculator_estimate_details.subsidy_slab_id`. |

### 4.12 `ref_amc_plans`

| | |
| --- | --- |
| **Class** | Reference |
| **Why it exists** | Catalog of sellable AMC products. Also configures how many site visits are free and out to what km from the office. |
| **Typical data** | Plan code, duration months, cleaning/breakdown flags, `free_visit_count`, `free_visit_radius_km`, annual list price. |
| **Relations** | Parent of `amc_contract_details`. |

### 4.13 `ref_checklist_items`

| | |
| --- | --- |
| **Class** | Reference |
| **Why it exists** | Digital job sheet template: VOC/ISC, AC/DC DB & earthing, panel cleaning, inverter firmware/Wi-Fi logger. Admin can add items without an app release. |
| **Typical data** | `job_type` SERVICE_REQUEST / COMPLAINT / COMMISSIONING; expected BOOLEAN / NUMERIC / TEXT; mandatory flag. |
| **Relations** | Parent of `job_checklist_response_details`. |

### 4.14 `ref_office_locations`

| | |
| --- | --- |
| **Class** | Reference |
| **Why it exists** | Origin point for site-visit distance (haversine in functions) and therefore visit charges. |
| **Typical data** | Code, name, address, lat/long, `is_default`. |
| **Relations** | Optional city/pincode. Parent of `site_visit_details.office_location_id`. |

### 4.15 `ref_visit_charge_slabs`

| | |
| --- | --- |
| **Class** | Reference |
| **Why it exists** | Admin-configurable INR bands by km from office. Optional purpose override (enquiry vs service vs complaint). |
| **Typical data** | min/max km, `charge_amount`, `is_free_ind` for a ₹0 inner band. |
| **Relations** | Optional FK → `SITE_VISIT_PURPOSES`. Used by `fn_get_site_visit_charge`. |

---

## 5. Module 1 — Authentication & user profile

**BRD need:** Passwordless OTP login, 3-fail/hour lockout, PIN/biometric, role-based personas, language and notification preferences.

### 5.1 `user_details`

| | |
| --- | --- |
| **Class** | Transaction (identity master for all personas) |
| **Why it exists** | Single login identity for **every** persona: Customer, Field Technician, Sales/Survey Agent, and Administrator. A technician is an app user: they OTP-login on this table with `ROLE_TECHNICIAN`. Path A unregistered mobiles (`admin_registered = FALSE`) go to the lead/enquiry pipeline. Path B and admin-created staff are `admin_registered = TRUE` so they skip that funnel. |
| **Typical data** | 10-digit mobile, country dial code, name, email, secondary/emergency contacts, role FK, language FK, **hashed** PIN (never plaintext), biometric and push flags, OTP fail counter and `lockout_until`, `account_status_ref_data_id` (ACTIVE / SUSPENDED), `registration_source_ref_data_id` (`SELF_APP` Path A vs `ADMIN_POST_INSTALL` Path B), `admin_registered`. |
| **Relations** | FK → `ref_countries`, `ref_data` (role, language, account status, **registration source**). **Parent of `technician_details` (1:1)** and `customer_details` (1:1). Also parent of sessions, KYC verifier, ticket raiser, messages, jobs’ customer sign-off, orders, follow-ups, notifications. `user_id` is stored as `logged_in_user_id` in function payloads. |

### 5.2 `technician_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | A technician **is** an app user. Login, OTP, name, mobile, photo, language, and push stay on `user_details`. This table only stores field-job attributes that other roles do not need: employee code, availability, last GPS, service radius. |
| **Typical data** | Exactly one row per field engineer user; `is_available`; lat/long for live arrival. |
| **Relations** | **Mandatory unique FK → `user_details.user_id`** (`ON DELETE RESTRICT`). That user must have role `ROLE_TECHNICIAN`. Jobs, service requests, and tickets point here (`technician_id`); UI still shows name/phone/photo from `user_details`. |

---

## 6. Module 10 — System logging, sessions & OTP

**BRD need:** Every API passes `api_endpoint` + `logged_in_user_id`; SQL functions log success/error; sessions capture device and hashed tokens; OTP cooldown and lockout.

### 6.1 `log_api_execution`

| | |
| --- | --- |
| **Class** | Log |
| **Why it exists** | One row per API hit (proxy or SQL entry). Ops can see endpoint, latency, HTTP/business code, and redacted payload. |
| **Typical data** | Endpoint, method, IP, request/response JSONB, `SUCCESS`/`ERROR`, `execution_time_ms`. |
| **Relations** | Optional FK → `user_details` (`ON DELETE SET NULL`). |

### 6.2 `log_sql_functions`

| | |
| --- | --- |
| **Class** | Log |
| **Why it exists** | Written by `fn_log_function_execution` from every `fn_*` `EXCEPTION` and success path. Separated from API logs because one HTTP call may invoke nested functions. |
| **Typical data** | `function_name`, payload snapshot, `SQLSTATE`, error message. |
| **Relations** | Optional FK → `user_details`. |

### 6.3 `log_user_sessions`

| | |
| --- | --- |
| **Class** | Log |
| **Why it exists** | BRD “user session auditing”: login history, device model, IP, hashed JWT, session lifecycle. Named `log_*` (not `user_session_details`) to satisfy logging naming rules. `user_id` is nullable until OTP succeeds. |
| **Typical data** | Status `PENDING_OTP` → `ACTIVE` → `LOGGED_OUT` / `EXPIRED` / `LOCKED`; `push_token` for FCM on the active session. |
| **Relations** | Optional FK → `user_details`. Parent of `log_otp_attempts`. |

### 6.4 `log_otp_attempts`

| | |
| --- | --- |
| **Class** | Log |
| **Why it exists** | OTP dispatch/verify with **hashed OTP**, expiry, consume flag, 60-second `resend_available_on`, and attempt numbering for the 3-per-hour lockout (functions also update `user_details.lockout_until`). |
| **Typical data** | Mobile, `otp_hash`, expiry, `is_consumed`. |
| **Relations** | Optional FK → `log_user_sessions`. |

### 6.5 `notification_details`

| | |
| --- | --- |
| **Class** | Transaction (inbox) |
| **Why it exists** | One row per recipient per event: catalogue publish, enquiry, service reminder, complaint, order, KYC, billing record, Path B welcome, follow-up due, spares. In-app list + unread badge. |
| **Typical data** | Recipient user, type FK, title/body, `payload_json` deep-link, optional entity type/id, `is_read_ind`, `read_on`. |
| **Relations** | FK → `user_details` (`RESTRICT`), `ref_data` type. Parent of `log_notification_delivery`. |

### 6.6 `log_notification_delivery`

| | |
| --- | --- |
| **Class** | Log |
| **Why it exists** | Push send queue/audit (`PENDING` → `SENT` / `FAILED`). In-app does not need a row; the inbox row is the record. OTP SMS is **not** stored here. |
| **Typical data** | Channel PUSH, status FK, provider id, error, optional session. |
| **Relations** | FK → `notification_details` (`ON DELETE CASCADE`), optional `log_user_sessions`. |

---

## 7. Module 2 — Interactive solar calculator & lead capture

**BRD need:** Bill/area/connection-type estimate, subsidy, payback, CO₂, area warning; convert to PDF quote + lead; schedule feasibility visit.

### 7.1 `calculator_estimate_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | Persists each calculator run so quotes are reproducible and subsidy slab used is auditable. Anonymous users may have `user_id` NULL. |
| **Typical data** | Monthly bill, rooftop area + unit, recommended kW, gross/subsidy/net cost, savings, payback months, CO₂ tons, `area_insufficient_ind`, `estimate_json` breakdown for PDF. |
| **Relations** | Optional FK → `user_details`, `ref_states`, `ref_subsidy_slabs`, `ref_data` (connection type). Parent of leads/quotes. |

### 7.2 `lead_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | Sales pipeline after “Get quote”: name, pincode, preferred contact window. Status in `ref_data`. |
| **Typical data** | `lead_no`, mobile, pincode (FK + raw fallback), agent assignment, `converted_customer_id` after onboarding. |
| **Relations** | FK → estimate, user, pincode, status, agent user. Deferred FK → `customer_details`. Parent of quotes and site visits. |

### 7.3 `quote_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | Formal quotation header and PDF URL. |
| **Typical data** | `quote_no`, gross/subsidy/net, validity date, status. |
| **Relations** | FK → `lead_details`, optional estimate, status `ref_data`. Parent of `quote_line_details` (`ON DELETE CASCADE`). |

### 7.4 `quote_line_details`

| | |
| --- | --- |
| **Class** | Transaction (owned child) |
| **Why it exists** | Itemized components: Panels, Inverter, Structure, BOS, Battery. |
| **Typical data** | Line no, component type CHECK, HSN/SAC, qty, rate, amount. |
| **Relations** | FK → `quote_details`. |

### 7.5 `site_visit_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | One register for **all** field visits (enquiry/feasibility, installation, servicing, complaint, commissioning). Not only lead feasibility. Charge vs free comes from AMC/free-milestone credits and office-distance slabs. Assignee is any `user_details` row (technician, sales, or other authorised person). |
| **Typical data** | `visit_no`, purpose, optional lead/site/customer/order/SR/ticket/AMC, office, `assigned_to_user_id`, schedule/start/complete, `distance_from_office_km`, slab, `is_chargeable_ind`, `is_free_entitlement_ind`, `charge_amount`, `charges_received_ind` + optional offline invoice/payment. |
| **Relations** | FK → office, charge slab, `ref_data` purpose/status/slot, optional lead. Deferred FKs to customer, site, enquiry, order, SR, milestone, ticket, AMC, invoice, payment. Technician jobs may point here. |

---

## 7A. Module 11 — Product catalogue & product enquiry

**BRD need:** Admin publishes related solar products; registered users browse details and place an enquiry that sales can convert to a lead. Distinct from `equipment_details` (installed site assets) and from `quote_line_details` (one-off quote BOM).

### 7A.1 `product_details`

| | |
| --- | --- |
| **Class** | Transaction (admin-maintained catalogue master) |
| **Why it exists** | Sellable / related SKUs shown in the app catalogue. `is_published` controls customer visibility without deleting the row. |
| **Typical data** | Unique `product_code`, name, category FK, short/long description, `specs_json`, list price INR, HSN/SAC, thumbnail URL, sort order, `published_on`. |
| **Relations** | FK → `ref_data` (`PRODUCT_CATEGORIES`). Parent of media and enquiries. |

### 7A.2 `product_media_details`

| | |
| --- | --- |
| **Class** | Transaction (owned child) |
| **Why it exists** | Gallery and spec-sheets on the product detail screen. |
| **Typical data** | PHOTO / VIDEO / DOCUMENT, URL, sort order, optional caption. |
| **Relations** | FK → `product_details` (`ON DELETE CASCADE`). |

### 7A.3 `product_enquiry_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | Registered-user interest against one catalogue product. Preserved after conversion to a sales lead. |
| **Typical data** | `enquiry_no`, message, preferred contact window, optional pincode, status FK, assigned agent, admin remarks, `converted_lead_id`. |
| **Relations** | FK → `product_details` (`RESTRICT`), `user_details` (`RESTRICT`), status `ref_data`, optional `lead_details` (`SET NULL`), optional `customer_details` and `pincode`. |

**Catalogue vs other tables**

| Table | Purpose |
| --- | --- |
| `product_details` | What the company *sells / promotes* |
| `equipment_details` | What is *installed* at a customer site |
| `quote_line_details` | Priced BOM on a specific quote |
| `ref_amc_plans` | AMC plan catalog (contracts), not SKU gallery |

---

## 8. Module 3 — Customer onboarding & site KYC

**BRD need:** DISCOM/consumer/meter/sanctioned load, GPS address, multi-site selector, document checklist and admin verification with mandatory reject comments.

### 8.1 `customer_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | Legal/billing party (GSTIN, billing name/address) separate from login and from physical sites. One customer per registered user in v1. |
| **Typical data** | `customer_code`, GSTIN, billing lines, originating `lead_id`. |
| **Relations** | Unique FK → `user_details`. Optional FK → `lead_details`. Parent of sites, KYC, invoices, service requests, tickets. |

### 8.2 `site_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | Multi-property selector (“Home - 5kW” vs “Factory - 50kW”). Holds DISCOM account, GPS for routing, commissioning date (starts free-service clock). |
| **Typical data** | Address, geo FKs, lat/long, consumer/meter numbers, sanctioned load kW, installation status, commissioning date, optional `order_id` (Path A fulfilment or Path B post-install). |
| **Relations** | FK → customer, pincode/city/district/state, discom, connection type, installation status, optional `order_details`. Parent of equipment, AMC, milestones, service requests, tickets, jobs, bills. |

### 8.3 `user_site_access_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | Which sites a user may switch into (owner vs family later). `is_default` drives last-selected site; partial unique index allows only one default per user. |
| **Typical data** | user_id + site_id + default flag + optional access role. |
| **Relations** | FK → `user_details`, `site_details` (`ON DELETE CASCADE`). |

### 8.4 `kyc_document_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | Aadhaar/PAN, electricity bill, ownership/NOC, roof photos. File size CHECK ≤ 2 MB. Verification badge via `ref_data`. **Reject comment is mandatory in SQL functions** when status code is `ACTION_REQUIRED` (not a brittle CHECK on a numeric id). |
| **Typical data** | File URL, MIME, size, status, verifier, `rejection_comment`. |
| **Relations** | FK → customer, optional site, document type, verification status, verifier user. |

---

## 9. Module 4 — Asset & installation tracking

**BRD need:** Digital twin of panels (serial/QR, wattage, qty), inverter (serial, kW, phase, dongle), structure and battery, warranty vault.

### 9.1 `equipment_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | One flexible asset row per type instead of four nearly identical tables. Type-specific fields (wattage, dongle, structure type, battery Ah) are nullable; `extra_json` absorbs rare attributes. |
| **Typical data** | Brand/model from `ref_data`, optional **catalogue `product_id`**, serial (partial unique when present), barcode, quantity. |
| **Relations** | FK → `site_details`, optional `product_details`, several `ref_data` types. Parent of `warranty_details`. |

### 9.2 `warranty_details`

| | |
| --- | --- |
| **Class** | Transaction (child) |
| **Why it exists** | 25-year panel performance and 5–10 year inverter cards, with document URL. |
| **Typical data** | Type FK, start/end dates, terms summary. |
| **Relations** | FK → `equipment_details` (`ON DELETE CASCADE`). |

---

## 10. Module 5 — Preventive service & AMC

**BRD need:** Four free quarterly services; AMC banner; customer booking; **admin maintains service master/history per customer, product, and installation** (especially Path B).

### 10.1 `amc_contract_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | Sold contract instance (not the catalog). Expiry drives a customer **renewal request** (follow-up/SR); money is recorded later by admin (Module 8). |
| **Typical data** | Site, plan, start/expiry, status, sold amount, optional `order_id` / `product_id`, optional bill id. |
| **Relations** | FK → site, `ref_amc_plans`, optional order, optional catalogue product, optional `invoice_details`. |

### 10.2 `service_milestone_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | Timeline of exactly four free visits (`milestone_no` 1–4, unique per site). `claim_window_end_on` = due + 30 days; functions set status `LAPSED`. |
| **Typical data** | Due date, window end, status FK, optional linked request. |
| **Relations** | FK → site, status `ref_data`. Bidirectional optional link to `service_request_details` (deferred FK on milestone). |

### 10.3 `service_request_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | Customer-initiated **or admin-entered** (offline/historical Path B) work: type, slot, technician, report. |
| **Typical data** | `service_request_no`, type/slot/status FKs, optional `order_id` / `product_id`, `arrival_status`. |
| **Relations** | FK → site, customer, technician, optional milestone, AMC, order, catalogue product. Parent of jobs. |

---

## 11. Module 6 — Complaint ticketing

**BRD need:** Category, severity, media (max 4), ticket number `TKT-YYYY-nnnn`, stepper, in-app chat/call, 4-digit OTP to mark resolved.

### 11.1 `complaint_ticket_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | Header for breakdowns (zero generation, damage, leakage, under-generation, billing/app). Ticket number unique globally. Resolution OTP stored **hashed**. |
| **Typical data** | Category/severity/status FKs, description, assignee, OTP expiry, resolved/closed timestamps. |
| **Relations** | FK → site, customer, raiser user, technician, `ref_data`. Parent of history, media, messages, jobs, spare requests. |

### 11.2 `ticket_status_history_details`

| | |
| --- | --- |
| **Class** | Transaction (lifecycle audit) |
| **Why it exists** | Stepper trail: Raised → Assigned → En-Route → On-Site → Parts Replaced → Resolved. No triggers — functions insert a history row on each status change. |
| **Typical data** | from/to status FKs, actor, remarks. |
| **Relations** | FK → ticket (`ON DELETE CASCADE`), `ref_data`, optional user. |

### 11.3 `ticket_media_details`

| | |
| --- | --- |
| **Class** | Transaction (child) |
| **Why it exists** | Up to 4 photos/videos of inverter error screens. Count enforced in `fn_create_*`, not a table CHECK. |
| **Typical data** | URL, PHOTO/VIDEO, size, sort. |
| **Relations** | FK → ticket (`ON DELETE CASCADE`). |

### 11.4 `ticket_message_details`

| | |
| --- | --- |
| **Class** | Transaction (child) |
| **Why it exists** | In-app chat. Call uses `user_details.mobile_no` of the assigned technician; no separate call table in v1. `is_internal` hides dispatcher notes from the customer. |
| **Typical data** | Sender user, message text. |
| **Relations** | FK → ticket (`ON DELETE CASCADE`), sender `user_details`. |

---

## 12. Module 7 — Field technician workspace

**BRD need:** Daily job queue with route order, accept/reschedule with reason, checklist, before/after photos, signature pad, spare-part requests.

### 12.1 `job_assignment_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | Unified queue for preventive jobs and emergency tickets (and optional site visits). `sequence_no` + `travel_distance_km` support map ordering. CHECK ensures the correct parent id is set for `job_type`. |
| **Typical data** | Technician, date, status, accept/reject/reschedule + reason, ETA, start/complete times. |
| **Relations** | FK → site, technician, status `ref_data`; optional service request or ticket (`ON DELETE CASCADE`). Parent of checklist, media, sign-off, spares. |

### 12.2 `job_checklist_response_details`

| | |
| --- | --- |
| **Class** | Transaction (child) |
| **Why it exists** | Answers against `ref_checklist_items` (boolean, numeric VOC/ISC, text). Partial unique (job, item) while active. |
| **Typical data** | Pass flag, measured value, remarks. |
| **Relations** | FK → job (`ON DELETE CASCADE`), checklist template (`RESTRICT`). |

### 12.3 `job_media_details`

| | |
| --- | --- |
| **Class** | Transaction (child) |
| **Why it exists** | Mandatory before/after clean panel and inverter running-status photos (`media_purpose`). |
| **Typical data** | Purpose enum, URL, captured_on. |
| **Relations** | FK → job (`ON DELETE CASCADE`). |

### 12.4 `job_signoff_details`

| | |
| --- | --- |
| **Class** | Transaction (child) |
| **Why it exists** | Signature pad image. For complaints, `otp_verified_ind` records that the customer OTP on the ticket succeeded. One active sign-off per job. |
| **Typical data** | Signature URL, signer name, signed_on. |
| **Relations** | FK → job (`ON DELETE CASCADE`), optional customer user. |

### 12.5 `spare_part_request_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | Technician requests parts from site (BRD). Lightweight — not a full warehouse SKU master in v1. Status REQUESTED → APPROVED → ISSUED → USED / REJECTED. Can drive a spare-parts invoice. |
| **Typical data** | Part name/code, qty, remarks. |
| **Relations** | FK → job (`ON DELETE CASCADE`), optional ticket. Referenced by `invoice_details.related_spare_part_request_id`. |

---

## 13. Module 8 — Offline billing & payment register

**BRD need:** No payment gateway. Admin transcribes offline bills/payments; customer **views** only. Path A: money recorded **after** installation. Path B: admin enters money when registering the post-install customer.

### 13.1 `invoice_details`

| | |
| --- | --- |
| **Class** | Transaction (offline **bill** header; name kept for compatibility) |
| **Why it exists** | Store amounts admin collected on paper/bank, not a live GST e-invoice or checkout. GST columns optional. |
| **Typical data** | `invoice_no`, category/status FKs, totals, optional tax split, `related_order_id`, optional AMC/SR/spare links. |
| **Relations** | FK → customer, optional site, order, `ref_data`. Parent of lines, payments, milestones. |

### 13.2 `invoice_line_details`

| | |
| --- | --- |
| **Class** | Transaction (child, optional) |
| **Why it exists** | Transcribe paper invoice lines when admin has them; a bill may have header totals only. |
| **Typical data** | Description, qty, rate, optional HSN/GST. |
| **Relations** | FK → invoice (`ON DELETE CASCADE`). |

### 13.3 `payment_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | One row per **offline** receipt. `is_offline_ind` always TRUE in v1. Gateway columns unused (nullable, reserved). |
| **Typical data** | Amount, method (cash/cheque/NEFT/UPI-outside-app), `instrument_ref`, `paid_on`, remarks. |
| **Relations** | FK → invoice (`RESTRICT`), customer, `ref_data`. Partial payments update bill balances in functions. |

### 13.4 `payment_milestone_details`

| | |
| --- | --- |
| **Class** | Transaction (child, optional) |
| **Why it exists** | Record an agreed offline split (e.g. 20/70/10) **after** collection, not an in-app EMI gateway. |
| **Typical data** | Percent, due/paid amounts, sequence. |
| **Relations** | FK → invoice (`ON DELETE CASCADE`). |

---

## 13A. Module 12 — Back-office admin console

**BRD need:** Path A and Path B onboarding; catalogue; orders through install; **offline billing**; **service master per customer/product/installation**; tickets; follow-ups.

### Admin → existing tables (no duplicate “admin_*” copies)

| Admin screen | Tables |
| --- | --- |
| Users (incl. Path B) | `user_details` (`registration_source`), `technician_details`, customer/site/equipment |
| Catalogue | `product_details`, `product_media_details` |
| Leads / enquiries / KYC | `lead_details`, `product_enquiry_details`, `kyc_document_details` |
| Orders → installation | `order_details`, `order_line_details`, `site_details`, `equipment_details` |
| Service per customer | `amc_contract_details`, `service_milestone_details`, `service_request_details` (product/order FKs) |
| Complaints / tickets / spares | `complaint_ticket_details`, history/media, `spare_part_request_details` |
| Offline billing & payment | `invoice_details`, `payment_details` (admin write; customer read) |
| Notifications inbox | `notification_details` (same table as customers; filtered by recipient) |
| Site visits | `site_visit_details` (assign any user; charge vs free) |
| Masters | `ref_data*`, geo, DISCOM, AMC plans, checklist, office locations, visit charge slabs |

### 13A.1 `order_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | Fulfilment through installation (Path A) or already-commissioned order (Path B). Not a payment gateway object. |
| **Typical data** | `order_no`, source (`QUOTE` / `ENQUIRY` / `LEAD` / `MANUAL`), status FK, customer, optional site, quote/enquiry/lead FKs, assigned admin, amounts, remarks. |
| **Relations** | FK → customer (`RESTRICT`), optional site, quote, enquiry, lead, `ref_data` status, assigned `user_details`. Parent of `order_line_details`. Optional `invoice_details.related_order_id`. |

### 13A.2 `order_line_details`

| | |
| --- | --- |
| **Class** | Transaction (child) |
| **Why it exists** | What was sold: catalogue `product_id` and/or free-text line (custom kit). |
| **Typical data** | Line no, description, optional product FK, qty, rate, amount, HSN. |
| **Relations** | FK → order (`ON DELETE CASCADE`), optional `product_details`. |

### 13A.3 `followup_details`

| | |
| --- | --- |
| **Class** | Transaction |
| **Why it exists** | Scheduled call/visit/WhatsApp/email against one parent entity so admin “My tasks” is queryable. |
| **Typical data** | `entity_type` CHECK, exactly one parent FK, due_on, type/status FKs, assigned user, notes, outcome, completed_on. |
| **Relations** | Optional FKs → lead, enquiry, order, ticket, service request, customer, user. Assigned → `user_details`. |

---

## 14. Cross-cutting behaviours (functions, not tables)

These rules are **not** triggers. They will live in `02_functions.sql`:

| Rule | Where |
| --- | --- |
| Stamp `updated_by` / `updated_on` | Every `fn_update_*` |
| OTP: 60s resend, 3 fails/hour, 15 min lockout | `log_otp_attempts` + `user_details.lockout_until` |
| Unregistered mobile → lead pipeline | Auth functions + `user_details.admin_registered` |
| Area warning: &lt; 100 sq.ft per kW | Calculator function + `area_insufficient_ind` |
| KYC reject requires comment | `fn_update_kyc_document_details` |
| Free service lapse after due + 30 days | Batch/read path on `service_milestone_details` |
| Max 4 ticket media | `fn_create_ticket_media_details` |
| Ticket number `TKT-YYYY-nnnn` | `fn_create_complaint_ticket_details` |
| Catalogue list only if `admin_registered` and `is_published` | `fn_get_product_details` |
| Create technician (admin) | `fn_create_user_details` + `fn_create_technician_details` in one call (same `user_id`) |
| Site visit schedule/assign/complete | `fn_create_site_visit_details` / `fn_update_site_visit_details` |
| Visit fee from office km + AMC/free credits | `fn_get_site_visit_charge` |
| Path B admin register after install | `fn_create_user_details` + customer/site/equipment/order |
| Offline bill/payment (admin write) | `fn_create`/`fn_update` invoice & payment; customer `fn_get` only |
| Admin service master per customer | `fn_create`/`fn_update` AMC, milestones, service_request |
| Enquiry number + convert to lead | `fn_create_product_enquiry_details` / `fn_update_product_enquiry_details` |
| Admin suspend/activate user | `fn_update_user_details` (`account_status_ref_data_id`) |
| Create/update order + lines | `fn_create_order_details` / `fn_update_order_details` |
| Follow-up due/complete | `fn_create_followup_details` / `fn_update_followup_details` |
| Resolution OTP to close ticket | Ticket + `job_signoff_details.otp_verified_ind` |
| Invoice paid/partial/paid-in-full | Offline payment functions (no gateway) |
| Enqueue inbox + optional push | `fn_create_notification_details` (called from other `fn_*`; **no triggers**) |
| Inbox list / mark read | `fn_get_notification_details` / `fn_update_notification_details` |
| Service / AMC / follow-up reminders | `fn_create_service_reminder_notifications`, `fn_create_followup_due_notifications` (scheduler) |
| Push send result | `fn_log_notification_delivery` |
| Standard JSON envelope | All functions: `status`, `code`, `message`, `data` |
| Function logging | `log_sql_functions` via `fn_log_function_execution` |

---

## 15. Explicitly out of v1 schema

These are valid future modules; they are **not** in the 55-table design so we do not over-build:

- In-app **payment gateway** (UPI/cards/net-banking/EMI checkout) and GST e-invoice IRN.
- Warehouse SKU / bin / stock ledger.
- Generation telemetry / time-series (dongle ID stored; readings are not).
- Full HR roster beyond `technician_details`.
- Email/WhatsApp marketing campaigns (transactional **in-app + push** is in v1).

---

## 16. Review checklist vs project rules

| Requirement | Status |
| --- | --- |
| Schema `solar_app`, owner `solar_app_user` | Yes |
| `_details` / `ref_` / `log_` naming | Yes |
| `ref_data_categories` + `ref_data` + `fn_get_dropdown_data` metadata | Yes (`ref_dropdown_config`) |
| Five audit columns on every table | Yes |
| `GENERATED ALWAYS AS IDENTITY` PKs | Yes |
| No triggers | Yes |
| All 13 BRD modules covered | Yes |
| Cascading geo + DISCOM | Yes (`ref_states` … `ref_discoms`) |
| Sessions as log table | Yes (`log_user_sessions`) |
| Notifications inbox + push log | Yes (`notification_details`, `log_notification_delivery`) |
| Site visits free/chargeable + office distance | Yes (`site_visit_details`, `ref_office_locations`, `ref_visit_charge_slabs`) |

---

*Document version: 1.4 — Notifications (catalogue, service reminders, enquiry, complaints, and related events).*
