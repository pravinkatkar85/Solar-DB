-- ==============================================================================
-- 1. DATABASE & USER CREATION
-- Execute these statements while connected as a superuser (e.g., postgres)
-- ==============================================================================

-- Create the application database owner/user
CREATE USER solar_app_user WITH PASSWORD 'solar_app_user@123';

-- Create the database with solar_app_user as the owner
CREATE DATABASE "SolarDB" OWNER solar_app_user;

-- Grant all database-level privileges
GRANT ALL PRIVILEGES ON DATABASE "SolarDB" TO solar_app_user;

-- ==============================================================================
-- 2. SCHEMA & PRIVILEGES CONFIGURATION
-- Connect to the newly created "SolarDB" database before running the rest:
-- \c SolarDB (in psql) or switch database connection in DBeaver
-- ==============================================================================

-- Create the application schema
CREATE SCHEMA IF NOT EXISTS solar_app AUTHORIZATION solar_app_user;

-- Set search path for solar_app_user
ALTER USER solar_app_user SET search_path TO solar_app, public;

-- Grant full schema access
GRANT ALL ON SCHEMA solar_app TO solar_app_user;

-- Ensure all future tables, sequences, and functions created in this schema are owned/accessible by solar_app_user
ALTER DEFAULT PRIVILEGES IN SCHEMA solar_app GRANT ALL ON TABLES TO solar_app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA solar_app GRANT ALL ON FUNCTIONS TO solar_app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA solar_app GRANT ALL ON SEQUENCES TO solar_app_user;