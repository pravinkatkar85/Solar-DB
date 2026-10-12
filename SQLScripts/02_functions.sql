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
