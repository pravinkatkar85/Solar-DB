-- Application function loader.
--
-- Each application function is authored as its own file in
-- DB-Objects/SQLFunctions, with a matching document in DB-Docs/SQLFunctions.
-- Add a new \ir line here, in dependency order, when a function is added.
-- This loader does not create tables, triggers, seed data, or grants.
--
-- Run with psql from Solar-DB:
--   psql -U solar_app_user -d SolarDB -v ON_ERROR_STOP=1 -f SQLScripts/02_functions.sql

\ir ../DB-Objects/SQLFunctions/solar_app.fn_get_dropdown_data.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_create_pin_user.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_create_pin_session.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_update_user_pin.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_get_product_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_create_product_enquiry_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_get_product_enquiry_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_update_product_enquiry_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_get_site_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_update_site_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_get_service_request_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_get_site_visit_charge.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_create_service_request_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_update_service_request_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_update_site_visit_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_get_amc_contract_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_create_notification_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_get_notification_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_update_notification_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_get_kyc_document_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_create_kyc_document_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_update_kyc_document_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_get_user_profile.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_update_user_profile.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_create_user_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_create_technician_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_update_technician_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_get_technician_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_create_job_assignment_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_get_job_assignment_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_update_job_assignment_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_create_invoice_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_update_invoice_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_get_invoice_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_create_payment_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_update_payment_details.sql
\ir ../DB-Objects/SQLFunctions/solar_app.fn_get_payment_details.sql

