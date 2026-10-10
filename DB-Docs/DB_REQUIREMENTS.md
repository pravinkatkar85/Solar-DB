# Software Requirements Specification (SRS) & Database Architecture
## Project Name: Solar Service Management Mobile Application (Solar-DB)

---

## 1. Executive Overview & Architectural Principles

### 1.1 Architecture & Design Pattern
- **Pattern:** Database-Centric Architecture (Smart DB, Thin API Proxy).
- **Core Engine:** PostgreSQL 16+.
- **Business Logic Layer:** All business logic MUST be defined entirely within SQL functions (PL/pgSQL).
- **Interface Protocol:** Every SQL function MUST accept JSON data as input (`p_payload JSONB`) for processing. Along with business attributes, the **API Endpoint** and **Logged-in User ID** MUST be mandatorily passed inside `p_payload`.
- **API Role:** Node.js (Express) acts purely as a thin intermediary route handler passing request metadata and body JSON directly into SQL functions.

---

## 2. Table Creation & Audit Standards

### 2.1 Standard Audit Columns
EVERY table created within the schema MUST include the following 5 mandatory audit columns without exception:
1. `active_ind` (BOOLEAN, DEFAULT `TRUE`, NOT NULL) — Soft-delete flag.
2. `created_by` (VARCHAR(50), DEFAULT `'SYSTEM'`, NOT NULL) — User/Actor who created the record.
3. `updated_by` (VARCHAR(50), DEFAULT `'SYSTEM'`, NOT NULL) — User/Actor who last updated the record.
4. `created_on` (TIMESTAMP WITH TIME ZONE, DEFAULT `CURRENT_TIMESTAMP`, NOT NULL) — Creation timestamp.
5. `updated_on` (TIMESTAMP WITH TIME ZONE, DEFAULT `CURRENT_TIMESTAMP`, NOT NULL) — Last updated timestamp.
6. Add comments to each column. table and all other DB objects

### 2.2 Constraints, Keys & Triggers Rule
- **No Triggers:** Database triggers MUST NOT be used for any operations (audit updates or business logic). All `updated_on` and `updated_by` updates must be explicitly handled inside SQL functions.
- **Keys & Constraints:** Tables MUST have appropriate Primary Keys, Foreign Keys, Unique, Check, and NOT NULL constraints.
- **Identity Columns:** Primary keys and auto-incrementing IDs MUST be defined appropriately using `GENERATED ALWAYS AS IDENTITY` (or `SERIAL` / `BIGSERIAL`).

---

## 3. Naming Conventions

### 3.1 Tables Naming Rules
- **Transaction Tables:** Use `_details` suffix for all transaction entities (e.g., `user_details`, `product_details`, `product_enquiry_details`, `customer_details`).
- Catalogue products (`product_details`) are admin-maintained transactional masters, not `ref_*` rows, because they carry price, media, publish flag, and long descriptions.
- **Master Reference Table:** All general reference data MUST be maintained in a normalized pair: `ref_data_categories` and `ref_data`.
- **Other Reference Tables:** Any standalone reference table names MUST start with `ref_` prefix (e.g., `ref_states`, `ref_cities`).
- **Logging Tables:** All logging table names MUST start with `log_` prefix (e.g., `log_api_execution`, `log_sql_functions`).

### 3.2 SQL Functions Naming Rules
Function names MUST strictly follow action-based prefixes:
- Creation Functions: `fn_create_<entity>` (e.g., `fn_create_user_details`)
- Update Functions: `fn_update_<entity>` (e.g., `fn_update_customer_details`)
- Logging Functions: `fn_get_<entity>` (e.g., `fn_get_user_details`)
- Logging Functions: `fn_log_<entity>` (e.g., `fn_log_api_execution`)
- Master/Generic Dropdown Functions: `fn_get_dropdown_data`

---

## 4. Logging & Audit Architecture

### 4.1 System Logging Tables
- **API & SQL Function Logs:** All API requests and their associated SQL function execution logs (including request payload, endpoint, execution time, error message, and Success/Error status) MUST be captured at the database level in `log_api_execution` and `log_sql_functions`.
- **User Sessions:** User login sessions, device information, and active JWT/OTP states MUST be maintained in the `log_user_sessions` or `user_session_details` table.

### 4.2 Error & Exception Handling
- All SQL functions MUST wrap execution blocks in `BEGIN ... EXCEPTION WHEN OTHERS THEN` blocks.
- Every function execution log along with Error/Success status MUST be recorded in the logging tables.
- All exceptions MUST be handled properly and returned to the API as a structured JSON error response so that errors can be smoothly managed at the UI level.

---

## 5. Dynamic Dropdown Configuration Engine

### 5.1 Single API & Single SQL Function Pattern
- ALL dropdowns across the entire application MUST be populated via **one single API endpoint** and **one single SQL function** (`fn_get_dropdown_data`).
- The dropdown system MUST be completely dynamic and generic based on table column configuration or SQL query configuration stored in reference metadata.

### 5.2 Cascading & Dependent Dropdowns
- Dropdowns MUST be configured to support dependent cascading refreshes based on a parent dropdown selection (e.g., refreshing `City` dropdown based on the selected value in `State` or `Country` dropdown).
- Filter criteria, parent-child mappings, and dynamic SQL generation MUST be fully configurable in the database metadata without requiring hardcoded UI or API changes.

---

## 6. SQL Function Input/Output Contract

All database functions created in `02_functions.sql` MUST adhere to this exact signature and output contract:

```sql
CREATE OR REPLACE FUNCTION fn_create_sample_entity(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_api_endpoint VARCHAR(255);
    v_logged_in_user VARCHAR(50);
    v_result_id INT;
    v_status VARCHAR(20) := 'SUCCESS';
    v_error_msg TEXT;
BEGIN
    -- Extract mandatory envelope attributes
    v_api_endpoint   := p_payload->>'api_endpoint';
    v_logged_in_user := COALESCE(p_payload->>'logged_in_user_id', 'SYSTEM');

    -- Core Transaction Logic --
    INSERT INTO sample_details (
        entity_name,
        created_by,
        updated_by
    ) VALUES (
        p_payload->>'entity_name',
        v_logged_in_user,
        v_logged_in_user
    ) RETURNING sample_id INTO v_result_id;

    -- Capture Success Log
    PERFORM fn_log_function_execution(v_api_endpoint, 'fn_create_sample_entity', p_payload, v_status, NULL);

    RETURN jsonb_build_object(
        'status', 'SUCCESS',
        'code', 200,
        'message', 'Record created successfully',
        'data', jsonb_build_object('sample_id', v_result_id)
    );

EXCEPTION WHEN OTHERS THEN
    v_status := 'ERROR';
    v_error_msg := SQLERRM;
    
    -- Capture Error Log
    PERFORM fn_log_function_execution(v_api_endpoint, 'fn_create_sample_entity', p_payload, v_status, v_error_msg);

    RETURN jsonb_build_object(
        'status', 'ERROR',
        'code', 500,
        'message', v_error_msg
    );
END;
$$;

---

## 7. Domain constraints (billing & onboarding)

- Do **not** implement an in-app payment gateway or customer checkout. `invoice_*` and `payment_*` store **offline** bills/receipts entered by admin; customers only read them.
- Support two onboarding paths in functions: self-app (`REG_SELF_APP`) via catalogue enquiry → order → install, then admin money later; and admin post-install (`REG_ADMIN_POST_INSTALL`) creating user/customer/site/equipment/order then billing and service rows.
- Admin may create/update AMC, milestones, and service history per customer, linked to product/installation/order.
- Notifications: `fn_create_notification_details` is called from other `fn_*` (no triggers). Inbox is `notification_details`; push attempts are `log_notification_delivery`. OTP SMS remains `log_otp_attempts`.
- Site visits: `fn_get_site_visit_charge` uses office lat/long, distance slabs, and remaining free AMC/milestone credits. Collection of visit fees is offline (`charges_received_ind`).