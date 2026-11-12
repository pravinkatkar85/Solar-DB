\set ON_ERROR_STOP on
SELECT current_database() AS db;
DO $$ BEGIN IF current_database() IS DISTINCT FROM 'SolarDB' THEN RAISE EXCEPTION 'Refuse install on %', current_database(); END IF; END $$;
BEGIN;
\i DB-Objects/SQLFunctions/solar_app.fn_create_technician_details.sql
\i DB-Objects/SQLFunctions/solar_app.fn_update_technician_details.sql
\i DB-Objects/SQLFunctions/solar_app.fn_get_technician_details.sql
\i DB-Objects/SQLFunctions/solar_app.fn_create_job_assignment_details.sql
\i DB-Objects/SQLFunctions/solar_app.fn_get_job_assignment_details.sql
\i DB-Objects/SQLFunctions/solar_app.fn_update_job_assignment_details.sql
COMMIT;
SELECT
  to_regprocedure('solar_app.fn_create_technician_details(jsonb)') IS NOT NULL AS create_tech,
  to_regprocedure('solar_app.fn_update_technician_details(jsonb)') IS NOT NULL AS update_tech,
  to_regprocedure('solar_app.fn_get_technician_details(jsonb)') IS NOT NULL AS get_tech,
  to_regprocedure('solar_app.fn_create_job_assignment_details(jsonb)') IS NOT NULL AS create_job,
  to_regprocedure('solar_app.fn_get_job_assignment_details(jsonb)') IS NOT NULL AS get_job,
  to_regprocedure('solar_app.fn_update_job_assignment_details(jsonb)') IS NOT NULL AS update_job;
