-- SolarDB executable schema
-- Generated from Solar-DB/DDL_SCHEMA.md v1.5.
--
-- Prerequisites:
--   1. Database SolarDB, role solar_app_user, and schema solar_app already exist.
--   2. The executing role has USAGE and CREATE privileges on schema solar_app.
--   3. A sufficiently privileged role can install btree_gist in this database,
--      or a DBA has installed it before this script is run.
--
-- This file intentionally contains no database/user/schema creation, seed data,
-- reference-data inserts, demo data, stored functions, triggers, or deployment-specific values.

-- btree_gist is required by effective-date and numeric-range exclusion constraints.
-- A role with sufficient database privileges must install it before table creation.
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;

-- pgcrypto hashes PIN values for fn_create_pin_user and fn_create_pin_session.
-- It ships with PostgreSQL. A privileged role must install it before those functions run.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

SET search_path TO solar_app, public;

-- =====================================================================
-- MODULE 9 — Dynamic masters & dropdowns
-- =====================================================================

CREATE TABLE solar_app.ref_data_categories (
    category_id     BIGINT GENERATED ALWAYS AS IDENTITY,
    category_code   VARCHAR(50)  NOT NULL,
    category_name   VARCHAR(150) NOT NULL,
    category_desc   VARCHAR(500),
    sort_order      INTEGER      NOT NULL DEFAULT 0,
    active_ind      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by      VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by      VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on      TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on      TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_data_categories PRIMARY KEY (category_id),
    CONSTRAINT uq_ref_data_categories_code UNIQUE (category_code)
);
COMMENT ON TABLE solar_app.ref_data_categories IS 'Master list of dropdown categories used by fn_get_dropdown_data (roles, statuses, notification types, etc.).';
COMMENT ON COLUMN solar_app.ref_data_categories.category_id IS 'Surrogate primary key (GENERATED ALWAYS AS IDENTITY).';
COMMENT ON COLUMN solar_app.ref_data_categories.category_code IS 'Stable API code such as USER_ROLES, PRODUCT_CATEGORIES, NOTIFICATION_TYPES.';
COMMENT ON COLUMN solar_app.ref_data_categories.category_name IS 'Admin and UI title for the category.';
COMMENT ON COLUMN solar_app.ref_data_categories.category_desc IS 'When and why this dropdown list is used.';
COMMENT ON COLUMN solar_app.ref_data_categories.sort_order IS 'Display order in admin master screens.';
COMMENT ON COLUMN solar_app.ref_data_categories.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_data_categories.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_data_categories.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_data_categories.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_data_categories.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_ref_data_categories_active ON solar_app.ref_data_categories (active_ind);

CREATE TABLE solar_app.ref_data (
    ref_data_id        BIGINT GENERATED ALWAYS AS IDENTITY,
    category_id        BIGINT       NOT NULL,
    data_code          VARCHAR(50)  NOT NULL,
    data_value         VARCHAR(255) NOT NULL,
    data_desc          VARCHAR(500),
    parent_ref_data_id BIGINT,
    sort_order         INTEGER      NOT NULL DEFAULT 0,
    extra_json         JSONB        NOT NULL DEFAULT '{}'::jsonb,
    active_ind         BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by         VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by         VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_data PRIMARY KEY (ref_data_id),
    CONSTRAINT fk_ref_data_category FOREIGN KEY (category_id) REFERENCES solar_app.ref_data_categories (category_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ref_data_parent FOREIGN KEY (parent_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT
);
COMMENT ON TABLE solar_app.ref_data IS 'Generic dropdown values belonging to a category, including nested parent values for in-list cascades.';
COMMENT ON COLUMN solar_app.ref_data.ref_data_id IS 'Surrogate primary key; used as dropdown value_id in the app.';
COMMENT ON COLUMN solar_app.ref_data.category_id IS 'FK to ref_data_categories; which list this value belongs to.';
COMMENT ON COLUMN solar_app.ref_data.data_code IS 'Stable machine code (ROLE_ADMIN, NTF_ENQUIRY_NEW, PAY_CASH, …).';
COMMENT ON COLUMN solar_app.ref_data.data_value IS 'Human-readable label shown in the UI.';
COMMENT ON COLUMN solar_app.ref_data.data_desc IS 'Optional help text or audience notes.';
COMMENT ON COLUMN solar_app.ref_data.parent_ref_data_id IS 'Optional parent value for in-list cascading dropdowns.';
COMMENT ON COLUMN solar_app.ref_data.sort_order IS 'Order of options inside the category.';
COMMENT ON COLUMN solar_app.ref_data.extra_json IS 'Optional extra attributes (icon, SLA hours, audience flags).';
COMMENT ON COLUMN solar_app.ref_data.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_data.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_data.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_data.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_data.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE UNIQUE INDEX uq_ref_data_category_code_active ON solar_app.ref_data (category_id, data_code) WHERE active_ind = TRUE;
CREATE INDEX idx_ref_data_category_id ON solar_app.ref_data (category_id);
CREATE INDEX idx_ref_data_parent_id ON solar_app.ref_data (parent_ref_data_id);
CREATE INDEX idx_ref_data_active ON solar_app.ref_data (active_ind);
CREATE INDEX idx_ref_data_extra_json ON solar_app.ref_data USING GIN (extra_json);

CREATE TABLE solar_app.ref_dropdown_config (
    dropdown_config_id   BIGINT GENERATED ALWAYS AS IDENTITY,
    dropdown_code        VARCHAR(50)  NOT NULL,
    display_name         VARCHAR(150) NOT NULL,
    source_type          VARCHAR(20)  NOT NULL,
    category_code        VARCHAR(50),
    source_table         VARCHAR(100),
    value_column         VARCHAR(100),
    label_column         VARCHAR(100),
    parent_dropdown_code VARCHAR(50),
    parent_filter_column VARCHAR(100),
    include_null_parent  BOOLEAN      NOT NULL DEFAULT FALSE,
    sort_column          VARCHAR(100),
    cache_ttl_seconds    INTEGER      NOT NULL,
    active_ind           BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by           VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by           VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on           TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on           TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_dropdown_config PRIMARY KEY (dropdown_config_id),
    CONSTRAINT uq_ref_dropdown_config_code UNIQUE (dropdown_code),
    CONSTRAINT chk_ref_dropdown_config_source CHECK (source_type IN ('REF_DATA', 'TABLE')),
    CONSTRAINT chk_ref_dropdown_config_shape CHECK (
        (source_type = 'REF_DATA' AND category_code IS NOT NULL AND source_table IS NULL)
        OR
        (source_type = 'TABLE' AND category_code IS NULL AND source_table IS NOT NULL
            AND value_column IS NOT NULL AND label_column IS NOT NULL)
    ),
    CONSTRAINT chk_ref_dropdown_config_ttl CHECK (cache_ttl_seconds >= 0)
);
COMMENT ON TABLE solar_app.ref_dropdown_config IS 'Allowlisted metadata for dynamic REF_DATA or TABLE dropdowns. It contains no executable SQL.';
COMMENT ON COLUMN solar_app.ref_dropdown_config.dropdown_config_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ref_dropdown_config.dropdown_code IS 'UI/API key such as STATES or PRODUCT_CATEGORIES.';
COMMENT ON COLUMN solar_app.ref_dropdown_config.display_name IS 'Admin-facing name of this dropdown.';
COMMENT ON COLUMN solar_app.ref_dropdown_config.source_type IS 'How options are loaded: REF_DATA or allowlisted TABLE.';
COMMENT ON COLUMN solar_app.ref_dropdown_config.category_code IS 'ref_data_categories.category_code when source_type is REF_DATA.';
COMMENT ON COLUMN solar_app.ref_dropdown_config.source_table IS 'Physical table name when source_type is TABLE.';
COMMENT ON COLUMN solar_app.ref_dropdown_config.value_column IS 'Column used as option value (id).';
COMMENT ON COLUMN solar_app.ref_dropdown_config.label_column IS 'Column used as option label.';
COMMENT ON COLUMN solar_app.ref_dropdown_config.parent_dropdown_code IS 'Parent dropdown_code for cascading refresh.';
COMMENT ON COLUMN solar_app.ref_dropdown_config.parent_filter_column IS 'Child table column compared to the selected parent value.';
COMMENT ON COLUMN solar_app.ref_dropdown_config.include_null_parent IS 'When TRUE, a cascading TABLE dropdown also includes rows whose parent filter column is NULL, such as statewide utilities.';
COMMENT ON COLUMN solar_app.ref_dropdown_config.sort_column IS 'ORDER BY column for options.';
COMMENT ON COLUMN solar_app.ref_dropdown_config.cache_ttl_seconds IS 'Hint for Flutter local cache TTL.';
COMMENT ON COLUMN solar_app.ref_dropdown_config.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_dropdown_config.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_dropdown_config.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_dropdown_config.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_dropdown_config.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_ref_dropdown_config_parent ON solar_app.ref_dropdown_config (parent_dropdown_code);
CREATE INDEX idx_ref_dropdown_config_active ON solar_app.ref_dropdown_config (active_ind);

CREATE TABLE solar_app.ref_currencies (
    currency_id    BIGINT GENERATED ALWAYS AS IDENTITY,
    currency_code  CHAR(3)      NOT NULL,
    currency_name  VARCHAR(100) NOT NULL,
    decimal_places SMALLINT     NOT NULL,
    active_ind     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by     VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by     VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on     TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on     TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_currencies PRIMARY KEY (currency_id),
    CONSTRAINT uq_ref_currencies_code UNIQUE (currency_code),
    CONSTRAINT chk_ref_currencies_code CHECK (currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT chk_ref_currencies_decimals CHECK (decimal_places BETWEEN 0 AND 6)
);
COMMENT ON TABLE solar_app.ref_currencies IS 'ISO currency metadata. The deployment default is selected by organization_details; this table does not contain company-specific rates.';
COMMENT ON COLUMN solar_app.ref_currencies.currency_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ref_currencies.currency_code IS 'ISO 4217 alphabetic currency code.';
COMMENT ON COLUMN solar_app.ref_currencies.currency_name IS 'Configurable display name.';
COMMENT ON COLUMN solar_app.ref_currencies.decimal_places IS 'Number of fractional digits used for display and rounding.';
COMMENT ON COLUMN solar_app.ref_currencies.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_currencies.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_currencies.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_currencies.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_currencies.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

CREATE TABLE solar_app.ref_countries (
    country_id                  BIGINT GENERATED ALWAYS AS IDENTITY,
    country_code                CHAR(2)      NOT NULL,
    country_name                VARCHAR(100) NOT NULL,
    phone_code                  VARCHAR(8)   NOT NULL,
    national_phone_min_length   SMALLINT     NOT NULL,
    national_phone_max_length   SMALLINT     NOT NULL,
    national_phone_regex        VARCHAR(255),
    postal_code_regex           VARCHAR(255),
    tax_registration_label      VARCHAR(100),
    tax_registration_regex      VARCHAR(255),
    active_ind                  BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by                  VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by                  VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on                  TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                  TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_countries PRIMARY KEY (country_id),
    CONSTRAINT uq_ref_countries_code UNIQUE (country_code),
    CONSTRAINT chk_ref_countries_code CHECK (country_code ~ '^[A-Z]{2}$'),
    CONSTRAINT chk_ref_countries_phone_code CHECK (phone_code ~ '^\+[1-9][0-9]{0,6}$'),
    CONSTRAINT chk_ref_countries_phone_lengths CHECK (
        national_phone_min_length BETWEEN 1 AND 15
        AND national_phone_max_length BETWEEN national_phone_min_length AND 15
    )
);
COMMENT ON TABLE solar_app.ref_countries IS 'ISO country master with configurable national phone, postal-code, and tax-registration validation metadata.';
COMMENT ON COLUMN solar_app.ref_countries.country_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ref_countries.country_code IS 'ISO 3166-1 alpha-2 code.';
COMMENT ON COLUMN solar_app.ref_countries.country_name IS 'Configurable display name.';
COMMENT ON COLUMN solar_app.ref_countries.phone_code IS 'International dialing prefix including the plus sign.';
COMMENT ON COLUMN solar_app.ref_countries.national_phone_min_length IS 'Minimum national-number digit count used by validation functions.';
COMMENT ON COLUMN solar_app.ref_countries.national_phone_max_length IS 'Maximum national-number digit count, capped by the E.164 technical limit.';
COMMENT ON COLUMN solar_app.ref_countries.national_phone_regex IS 'Optional deployment-approved regular expression for the national number.';
COMMENT ON COLUMN solar_app.ref_countries.postal_code_regex IS 'Optional deployment-approved regular expression for postal codes.';
COMMENT ON COLUMN solar_app.ref_countries.tax_registration_label IS 'Country-specific display label for a customer tax registration number.';
COMMENT ON COLUMN solar_app.ref_countries.tax_registration_regex IS 'Optional deployment-approved tax registration validation expression.';
COMMENT ON COLUMN solar_app.ref_countries.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_countries.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_countries.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_countries.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_countries.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

CREATE TABLE solar_app.ref_states (
    state_id       BIGINT GENERATED ALWAYS AS IDENTITY,
    country_id     BIGINT       NOT NULL,
    state_code     VARCHAR(10)  NOT NULL,
    state_name     VARCHAR(100) NOT NULL,
    tax_region_code VARCHAR(20),
    active_ind     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by     VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by     VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on     TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on     TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_states PRIMARY KEY (state_id),
    CONSTRAINT fk_ref_states_country FOREIGN KEY (country_id) REFERENCES solar_app.ref_countries (country_id) ON DELETE RESTRICT,
    CONSTRAINT uq_ref_states_country_code UNIQUE (country_id, state_code)
);
COMMENT ON TABLE solar_app.ref_states IS 'Administrative states or regions used for tax jurisdiction, geo cascade, utilities, and subsidy overlays.';
COMMENT ON COLUMN solar_app.ref_states.state_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ref_states.country_id IS 'FK to ref_countries.';
COMMENT ON COLUMN solar_app.ref_states.state_code IS 'Short state/UT code unique within country.';
COMMENT ON COLUMN solar_app.ref_states.state_name IS 'Official state or region name.';
COMMENT ON COLUMN solar_app.ref_states.tax_region_code IS 'Optional country-specific tax or place-of-supply region code.';
COMMENT ON COLUMN solar_app.ref_states.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_states.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_states.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_states.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_states.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_ref_states_active ON solar_app.ref_states (active_ind);

CREATE TABLE solar_app.ref_districts (
    district_id   BIGINT GENERATED ALWAYS AS IDENTITY,
    state_id      BIGINT       NOT NULL,
    district_name VARCHAR(100) NOT NULL,
    active_ind    BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by    VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by    VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on    TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on    TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_districts PRIMARY KEY (district_id),
    CONSTRAINT fk_ref_districts_state FOREIGN KEY (state_id) REFERENCES solar_app.ref_states (state_id) ON DELETE RESTRICT
);
COMMENT ON TABLE solar_app.ref_districts IS 'Districts within a state; parent of cities and optional DISCOM circles.';
COMMENT ON COLUMN solar_app.ref_districts.district_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ref_districts.state_id IS 'FK to parent state.';
COMMENT ON COLUMN solar_app.ref_districts.district_name IS 'District name as used in geo and DISCOM cascade.';
COMMENT ON COLUMN solar_app.ref_districts.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_districts.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_districts.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_districts.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_districts.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE UNIQUE INDEX uq_ref_districts_state_name_active ON solar_app.ref_districts (state_id, lower(district_name)) WHERE active_ind = TRUE;
CREATE INDEX idx_ref_districts_state_id ON solar_app.ref_districts (state_id);

CREATE TABLE solar_app.ref_cities (
    city_id     BIGINT GENERATED ALWAYS AS IDENTITY,
    district_id BIGINT       NOT NULL,
    state_id    BIGINT       NOT NULL,
    city_name   VARCHAR(100) NOT NULL,
    active_ind  BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by  VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by  VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on  TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on  TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_cities PRIMARY KEY (city_id),
    CONSTRAINT fk_ref_cities_district FOREIGN KEY (district_id) REFERENCES solar_app.ref_districts (district_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ref_cities_state FOREIGN KEY (state_id) REFERENCES solar_app.ref_states (state_id) ON DELETE RESTRICT
);
COMMENT ON TABLE solar_app.ref_cities IS 'Cities and towns. state_id is denormalized so State→City queries do not always require district.';
COMMENT ON COLUMN solar_app.ref_cities.city_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ref_cities.district_id IS 'FK to parent district.';
COMMENT ON COLUMN solar_app.ref_cities.state_id IS 'Denormalized FK to state for faster State→City lists.';
COMMENT ON COLUMN solar_app.ref_cities.city_name IS 'City or town name (includes district-HQ placeholder rows).';
COMMENT ON COLUMN solar_app.ref_cities.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_cities.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_cities.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_cities.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_cities.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_ref_cities_district_id ON solar_app.ref_cities (district_id);
CREATE INDEX idx_ref_cities_state_id ON solar_app.ref_cities (state_id);

CREATE TABLE solar_app.ref_pincodes (
    pincode_id  BIGINT GENERATED ALWAYS AS IDENTITY,
    pincode     VARCHAR(20) NOT NULL,
    city_id     BIGINT      NOT NULL,
    district_id BIGINT      NOT NULL,
    state_id    BIGINT      NOT NULL,
    active_ind  BOOLEAN     NOT NULL DEFAULT TRUE,
    created_by  VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    updated_by  VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    created_on  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_pincodes PRIMARY KEY (pincode_id),
    CONSTRAINT fk_ref_pincodes_city FOREIGN KEY (city_id) REFERENCES solar_app.ref_cities (city_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ref_pincodes_district FOREIGN KEY (district_id) REFERENCES solar_app.ref_districts (district_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ref_pincodes_state FOREIGN KEY (state_id) REFERENCES solar_app.ref_states (state_id) ON DELETE RESTRICT,
    CONSTRAINT chk_ref_pincodes_not_blank CHECK (btrim(pincode) <> '')
);
COMMENT ON TABLE solar_app.ref_pincodes IS 'Postal-code master for leads, sites, and product enquiries; country-specific format is validated from ref_countries metadata.';
COMMENT ON COLUMN solar_app.ref_pincodes.pincode_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ref_pincodes.pincode IS 'Postal code as issued by the applicable country.';
COMMENT ON COLUMN solar_app.ref_pincodes.city_id IS 'FK to city.';
COMMENT ON COLUMN solar_app.ref_pincodes.district_id IS 'Denormalized FK to district.';
COMMENT ON COLUMN solar_app.ref_pincodes.state_id IS 'Denormalized FK to state.';
COMMENT ON COLUMN solar_app.ref_pincodes.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_pincodes.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_pincodes.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_pincodes.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_pincodes.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE UNIQUE INDEX uq_ref_pincodes_active ON solar_app.ref_pincodes (pincode) WHERE active_ind = TRUE;

CREATE TABLE solar_app.ref_discoms (
    discom_id    BIGINT GENERATED ALWAYS AS IDENTITY,
    state_id     BIGINT       NOT NULL,
    district_id  BIGINT,
    discom_code  VARCHAR(30)  NOT NULL,
    discom_name  VARCHAR(150) NOT NULL,
    active_ind   BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by   VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by   VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on   TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on   TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_discoms PRIMARY KEY (discom_id),
    CONSTRAINT fk_ref_discoms_state FOREIGN KEY (state_id) REFERENCES solar_app.ref_states (state_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ref_discoms_district FOREIGN KEY (district_id) REFERENCES solar_app.ref_districts (district_id) ON DELETE RESTRICT
);
COMMENT ON TABLE solar_app.ref_discoms IS 'Electricity distribution companies. NULL district_id means statewide; set district_id for a local circle.';
COMMENT ON COLUMN solar_app.ref_discoms.discom_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ref_discoms.state_id IS 'FK to state this utility operates in.';
COMMENT ON COLUMN solar_app.ref_discoms.district_id IS 'Optional local circle; NULL means statewide utility.';
COMMENT ON COLUMN solar_app.ref_discoms.discom_code IS 'Stable deployment-defined utility code.';
COMMENT ON COLUMN solar_app.ref_discoms.discom_name IS 'Legal or trading name of the utility.';
COMMENT ON COLUMN solar_app.ref_discoms.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_discoms.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_discoms.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_discoms.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_discoms.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE UNIQUE INDEX uq_ref_discoms_code_active ON solar_app.ref_discoms (discom_code) WHERE active_ind = TRUE;
CREATE INDEX idx_ref_discoms_state_id ON solar_app.ref_discoms (state_id);

CREATE TABLE solar_app.ref_business_parameters (
    parameter_id       BIGINT GENERATED ALWAYS AS IDENTITY,
    parameter_code     VARCHAR(50)  NOT NULL,
    parameter_name     VARCHAR(150) NOT NULL,
    value_type         VARCHAR(20)  NOT NULL,
    numeric_value      NUMERIC(18,6),
    text_value         TEXT,
    boolean_value      BOOLEAN,
    json_value         JSONB,
    parameter_unit     VARCHAR(30),
    parameter_desc     VARCHAR(500),
    admin_manageable_ind BOOLEAN    NOT NULL DEFAULT TRUE,
    effective_from     DATE         NOT NULL,
    effective_to       DATE,
    active_ind         BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by         VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by         VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_business_parameters PRIMARY KEY (parameter_id),
    CONSTRAINT uq_ref_business_parameters_version UNIQUE (parameter_code, effective_from),
    CONSTRAINT chk_ref_business_parameters_type CHECK (value_type IN ('NUMERIC', 'TEXT', 'BOOLEAN', 'JSON')),
    CONSTRAINT chk_ref_business_parameters_value CHECK (
        (value_type = 'NUMERIC' AND numeric_value IS NOT NULL AND text_value IS NULL AND boolean_value IS NULL AND json_value IS NULL)
        OR (value_type = 'TEXT' AND numeric_value IS NULL AND text_value IS NOT NULL AND boolean_value IS NULL AND json_value IS NULL)
        OR (value_type = 'BOOLEAN' AND numeric_value IS NULL AND text_value IS NULL AND boolean_value IS NOT NULL AND json_value IS NULL)
        OR (value_type = 'JSON' AND numeric_value IS NULL AND text_value IS NULL AND boolean_value IS NULL AND json_value IS NOT NULL)
    ),
    CONSTRAINT chk_ref_business_parameters_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT ex_ref_business_parameters_dates EXCLUDE USING gist (
        parameter_code WITH =,
        daterange(effective_from, CASE WHEN effective_to IS NULL THEN NULL ELSE effective_to + 1 END, '[)') WITH &&
    ) WHERE (active_ind = TRUE)
);
COMMENT ON TABLE solar_app.ref_business_parameters IS 'Typed, effective-dated business and operational configuration, including calculator settings and approved feature flags. Credentials and endpoints are prohibited.';
COMMENT ON COLUMN solar_app.ref_business_parameters.parameter_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ref_business_parameters.parameter_code IS 'Stable internal code consumed by application contracts.';
COMMENT ON COLUMN solar_app.ref_business_parameters.parameter_name IS 'Configurable administrator-facing label.';
COMMENT ON COLUMN solar_app.ref_business_parameters.value_type IS 'Selects the single populated value column: NUMERIC, TEXT, BOOLEAN, or JSON.';
COMMENT ON COLUMN solar_app.ref_business_parameters.numeric_value IS 'Numeric value when value_type is NUMERIC.';
COMMENT ON COLUMN solar_app.ref_business_parameters.text_value IS 'Text value when value_type is TEXT.';
COMMENT ON COLUMN solar_app.ref_business_parameters.boolean_value IS 'Boolean value, including an approved feature flag, when value_type is BOOLEAN.';
COMMENT ON COLUMN solar_app.ref_business_parameters.json_value IS 'Structured value when value_type is JSON and a scalar is insufficient.';
COMMENT ON COLUMN solar_app.ref_business_parameters.parameter_unit IS 'Configurable unit code or display hint.';
COMMENT ON COLUMN solar_app.ref_business_parameters.parameter_desc IS 'Purpose, scope, and approved usage of the parameter.';
COMMENT ON COLUMN solar_app.ref_business_parameters.admin_manageable_ind IS 'TRUE when an authorized business administrator may maintain this parameter.';
COMMENT ON COLUMN solar_app.ref_business_parameters.effective_from IS 'Inclusive date from which this version applies.';
COMMENT ON COLUMN solar_app.ref_business_parameters.effective_to IS 'Inclusive final date; NULL means open-ended.';
COMMENT ON COLUMN solar_app.ref_business_parameters.active_ind IS 'Soft-delete flag. FALSE excludes the version from rule resolution.';
COMMENT ON COLUMN solar_app.ref_business_parameters.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_business_parameters.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_business_parameters.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_business_parameters.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_ref_business_parameters_lookup ON solar_app.ref_business_parameters (parameter_code, effective_from, effective_to) WHERE active_ind = TRUE;

CREATE TABLE solar_app.ref_subsidy_schemes (
    subsidy_scheme_id BIGINT GENERATED ALWAYS AS IDENTITY,
    scheme_code       VARCHAR(50)  NOT NULL,
    scheme_name       VARCHAR(150) NOT NULL,
    country_id        BIGINT       NOT NULL,
    state_id          BIGINT,
    calculation_method VARCHAR(30) NOT NULL,
    maximum_benefit_amount NUMERIC(14,2),
    currency_code     CHAR(3)      NOT NULL,
    eligibility_json  JSONB        NOT NULL DEFAULT '{}'::jsonb,
    effective_from    DATE         NOT NULL,
    effective_to      DATE,
    active_ind        BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by        VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by        VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on        TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on        TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_subsidy_schemes PRIMARY KEY (subsidy_scheme_id),
    CONSTRAINT fk_subsidy_scheme_country FOREIGN KEY (country_id) REFERENCES solar_app.ref_countries (country_id) ON DELETE RESTRICT,
    CONSTRAINT fk_subsidy_scheme_state FOREIGN KEY (state_id) REFERENCES solar_app.ref_states (state_id) ON DELETE RESTRICT,
    CONSTRAINT fk_subsidy_scheme_currency FOREIGN KEY (currency_code) REFERENCES solar_app.ref_currencies (currency_code) ON DELETE RESTRICT,
    CONSTRAINT uq_ref_subsidy_schemes_version UNIQUE (scheme_code, effective_from),
    CONSTRAINT chk_subsidy_scheme_method CHECK (calculation_method IN ('FIXED_AMOUNT', 'RATE_PER_CAPACITY', 'PERCENTAGE', 'TIERED_RATE')),
    CONSTRAINT chk_subsidy_scheme_cap CHECK (maximum_benefit_amount IS NULL OR maximum_benefit_amount >= 0),
    CONSTRAINT chk_subsidy_scheme_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT ex_ref_subsidy_schemes_dates EXCLUDE USING gist (
        scheme_code WITH =,
        daterange(effective_from, CASE WHEN effective_to IS NULL THEN NULL ELSE effective_to + 1 END, '[)') WITH &&
    ) WHERE (active_ind = TRUE)
);
COMMENT ON TABLE solar_app.ref_subsidy_schemes IS 'Effective-dated subsidy scheme definitions. Deployment-approved eligibility and caps are configuration, not schema constants.';
COMMENT ON COLUMN solar_app.ref_subsidy_schemes.subsidy_scheme_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ref_subsidy_schemes.scheme_code IS 'Stable internal scheme code; versioned by effective date.';
COMMENT ON COLUMN solar_app.ref_subsidy_schemes.scheme_name IS 'Configurable display name.';
COMMENT ON COLUMN solar_app.ref_subsidy_schemes.country_id IS 'Country whose rules authorize the scheme.';
COMMENT ON COLUMN solar_app.ref_subsidy_schemes.state_id IS 'Optional state or region restriction; NULL means country-level.';
COMMENT ON COLUMN solar_app.ref_subsidy_schemes.calculation_method IS 'Approved calculation family; formulas and rates are supplied as configuration.';
COMMENT ON COLUMN solar_app.ref_subsidy_schemes.maximum_benefit_amount IS 'Optional maximum benefit for this scheme version.';
COMMENT ON COLUMN solar_app.ref_subsidy_schemes.currency_code IS 'Currency of configured monetary rates and cap.';
COMMENT ON COLUMN solar_app.ref_subsidy_schemes.eligibility_json IS 'Deployment-approved structured eligibility criteria; no production criteria are embedded in DDL.';
COMMENT ON COLUMN solar_app.ref_subsidy_schemes.effective_from IS 'Inclusive scheme-version start date.';
COMMENT ON COLUMN solar_app.ref_subsidy_schemes.effective_to IS 'Inclusive scheme-version end date; NULL means open-ended.';
COMMENT ON COLUMN solar_app.ref_subsidy_schemes.active_ind IS 'Soft-delete flag. FALSE excludes the version from rule resolution.';
COMMENT ON COLUMN solar_app.ref_subsidy_schemes.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_subsidy_schemes.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_subsidy_schemes.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_subsidy_schemes.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

CREATE TABLE solar_app.ref_subsidy_slabs (
    subsidy_slab_id             BIGINT GENERATED ALWAYS AS IDENTITY,
    subsidy_scheme_id           BIGINT       NOT NULL,
    connection_type_ref_data_id BIGINT       NOT NULL,
    min_capacity_kw             NUMERIC(8,3) NOT NULL,
    max_capacity_kw             NUMERIC(8,3),
    rate_amount                 NUMERIC(14,2),
    rate_percent                NUMERIC(7,4),
    sort_order                  INTEGER      NOT NULL DEFAULT 0,
    capacity_range              NUMRANGE GENERATED ALWAYS AS
                                (numrange(min_capacity_kw, max_capacity_kw, '[)')) STORED,
    active_ind                  BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by                  VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by                  VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on                  TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                  TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_subsidy_slabs PRIMARY KEY (subsidy_slab_id),
    CONSTRAINT fk_ref_subsidy_slabs_scheme FOREIGN KEY (subsidy_scheme_id) REFERENCES solar_app.ref_subsidy_schemes (subsidy_scheme_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ref_subsidy_slabs_conn_type FOREIGN KEY (connection_type_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT chk_ref_subsidy_slabs_kw CHECK (min_capacity_kw >= 0 AND (max_capacity_kw IS NULL OR max_capacity_kw > min_capacity_kw)),
    CONSTRAINT chk_ref_subsidy_slabs_amount CHECK (rate_amount IS NULL OR rate_amount >= 0),
    CONSTRAINT chk_ref_subsidy_slabs_pct CHECK (rate_percent IS NULL OR (rate_percent >= 0 AND rate_percent <= 100)),
    CONSTRAINT chk_ref_subsidy_slabs_rate CHECK (num_nonnulls(rate_amount, rate_percent) = 1),
    CONSTRAINT ex_ref_subsidy_slabs_capacity EXCLUDE USING gist (
        subsidy_scheme_id WITH =,
        connection_type_ref_data_id WITH =,
        capacity_range WITH &&
    ) WHERE (active_ind = TRUE)
);
COMMENT ON TABLE solar_app.ref_subsidy_slabs IS 'Non-overlapping capacity tiers belonging to an effective-dated subsidy scheme.';
COMMENT ON COLUMN solar_app.ref_subsidy_slabs.subsidy_slab_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ref_subsidy_slabs.subsidy_scheme_id IS 'Effective-dated parent scheme that defines calculation method, jurisdiction, currency, and cap.';
COMMENT ON COLUMN solar_app.ref_subsidy_slabs.connection_type_ref_data_id IS 'FK to CONNECTION_TYPES (residential, society, commercial).';
COMMENT ON COLUMN solar_app.ref_subsidy_slabs.min_capacity_kw IS 'Inclusive lower capacity bound.';
COMMENT ON COLUMN solar_app.ref_subsidy_slabs.max_capacity_kw IS 'Exclusive upper capacity bound; NULL means open-ended.';
COMMENT ON COLUMN solar_app.ref_subsidy_slabs.rate_amount IS 'Monetary rate interpreted according to the parent calculation_method.';
COMMENT ON COLUMN solar_app.ref_subsidy_slabs.rate_percent IS 'Percentage rate interpreted according to the parent calculation_method.';
COMMENT ON COLUMN solar_app.ref_subsidy_slabs.sort_order IS 'Administrative display and calculation-tier order.';
COMMENT ON COLUMN solar_app.ref_subsidy_slabs.capacity_range IS 'Generated half-open capacity range used to prevent active overlaps.';
COMMENT ON COLUMN solar_app.ref_subsidy_slabs.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_subsidy_slabs.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_subsidy_slabs.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_subsidy_slabs.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_subsidy_slabs.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_ref_subsidy_slabs_lookup ON solar_app.ref_subsidy_slabs (subsidy_scheme_id, connection_type_ref_data_id) WHERE active_ind = TRUE;

CREATE TABLE solar_app.ref_amc_plans (
    amc_plan_id        BIGINT GENERATED ALWAYS AS IDENTITY,
    plan_code          VARCHAR(30)   NOT NULL,
    plan_name          VARCHAR(150)  NOT NULL,
    plan_desc          VARCHAR(500),
    duration_months    INTEGER       NOT NULL,
    includes_breakdown BOOLEAN       NOT NULL,
    includes_cleaning  BOOLEAN       NOT NULL,
    free_visit_count   INTEGER       NOT NULL,
    free_visit_radius_km NUMERIC(8,2),
    plan_price         NUMERIC(12,2) NOT NULL,
    currency_code      CHAR(3)       NOT NULL,
    effective_from     DATE          NOT NULL,
    effective_to       DATE,
    active_ind         BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by         VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by         VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on         TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on         TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_amc_plans PRIMARY KEY (amc_plan_id),
    CONSTRAINT fk_ref_amc_plans_currency FOREIGN KEY (currency_code) REFERENCES solar_app.ref_currencies (currency_code) ON DELETE RESTRICT,
    CONSTRAINT uq_ref_amc_plans_version UNIQUE (plan_code, effective_from),
    CONSTRAINT chk_ref_amc_plans_duration CHECK (duration_months > 0),
    CONSTRAINT chk_ref_amc_plans_price CHECK (plan_price >= 0),
    CONSTRAINT chk_ref_amc_plans_free_visits CHECK (free_visit_count >= 0),
    CONSTRAINT chk_ref_amc_plans_radius CHECK (free_visit_radius_km IS NULL OR free_visit_radius_km >= 0),
    CONSTRAINT chk_ref_amc_plans_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT ex_ref_amc_plans_dates EXCLUDE USING gist (
        plan_code WITH =,
        daterange(effective_from, CASE WHEN effective_to IS NULL THEN NULL ELSE effective_to + 1 END, '[)') WITH &&
    ) WHERE (active_ind = TRUE)
);
COMMENT ON TABLE solar_app.ref_amc_plans IS 'Effective-dated AMC plan catalogue. Each price covers the full configured duration; collection remains offline.';
COMMENT ON COLUMN solar_app.ref_amc_plans.amc_plan_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ref_amc_plans.plan_code IS 'Stable plan code shared by effective-dated versions.';
COMMENT ON COLUMN solar_app.ref_amc_plans.plan_name IS 'Customer-facing plan name (Basic Cleaning, Comprehensive, …).';
COMMENT ON COLUMN solar_app.ref_amc_plans.plan_desc IS 'What the plan includes.';
COMMENT ON COLUMN solar_app.ref_amc_plans.duration_months IS 'Contract length in months.';
COMMENT ON COLUMN solar_app.ref_amc_plans.includes_breakdown IS 'TRUE if breakdown visits are included.';
COMMENT ON COLUMN solar_app.ref_amc_plans.includes_cleaning IS 'TRUE if routine cleaning is included.';
COMMENT ON COLUMN solar_app.ref_amc_plans.free_visit_count IS 'How many site visits this subscription covers at no charge (configurable per plan). 0 = none free.';
COMMENT ON COLUMN solar_app.ref_amc_plans.free_visit_radius_km IS 'Optional km cap from office for a free entitlement visit; beyond this the visit becomes chargeable even on AMC.';
COMMENT ON COLUMN solar_app.ref_amc_plans.plan_price IS 'List price for the complete duration_months term.';
COMMENT ON COLUMN solar_app.ref_amc_plans.currency_code IS 'Currency of plan_price.';
COMMENT ON COLUMN solar_app.ref_amc_plans.effective_from IS 'Inclusive plan-version start date.';
COMMENT ON COLUMN solar_app.ref_amc_plans.effective_to IS 'Inclusive plan-version end date; NULL means open-ended.';
COMMENT ON COLUMN solar_app.ref_amc_plans.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_amc_plans.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_amc_plans.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_amc_plans.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_amc_plans.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_ref_amc_plans_lookup ON solar_app.ref_amc_plans (plan_code, effective_from, effective_to) WHERE active_ind = TRUE;

CREATE TABLE solar_app.ref_tax_rules (
    tax_rule_id             BIGINT GENERATED ALWAYS AS IDENTITY,
    tax_rule_code           VARCHAR(50)  NOT NULL,
    tax_group_code          VARCHAR(50)  NOT NULL,
    tax_component_code      VARCHAR(50)  NOT NULL,
    tax_display_name        VARCHAR(150) NOT NULL,
    country_id              BIGINT       NOT NULL,
    state_id                BIGINT,
    tax_classification_code VARCHAR(30),
    calculation_method      VARCHAR(20)  NOT NULL,
    rate_percent            NUMERIC(7,4),
    rate_amount             NUMERIC(14,2),
    currency_code           CHAR(3),
    priority                INTEGER      NOT NULL,
    effective_from          DATE         NOT NULL,
    effective_to            DATE,
    active_ind              BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by              VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by              VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on              TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on              TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_tax_rules PRIMARY KEY (tax_rule_id),
    CONSTRAINT fk_ref_tax_rules_country FOREIGN KEY (country_id) REFERENCES solar_app.ref_countries (country_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ref_tax_rules_state FOREIGN KEY (state_id) REFERENCES solar_app.ref_states (state_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ref_tax_rules_currency FOREIGN KEY (currency_code) REFERENCES solar_app.ref_currencies (currency_code) ON DELETE RESTRICT,
    CONSTRAINT uq_ref_tax_rules_version UNIQUE (tax_rule_code, effective_from),
    CONSTRAINT chk_ref_tax_rules_method CHECK (calculation_method IN ('PERCENTAGE', 'FIXED_AMOUNT')),
    CONSTRAINT chk_ref_tax_rules_rate CHECK (
        (calculation_method = 'PERCENTAGE' AND rate_percent BETWEEN 0 AND 100 AND rate_amount IS NULL AND currency_code IS NULL)
        OR
        (calculation_method = 'FIXED_AMOUNT' AND rate_percent IS NULL AND rate_amount >= 0 AND currency_code IS NOT NULL)
    ),
    CONSTRAINT chk_ref_tax_rules_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT ex_ref_tax_rules_dates EXCLUDE USING gist (
        tax_rule_code WITH =,
        daterange(effective_from, CASE WHEN effective_to IS NULL THEN NULL ELSE effective_to + 1 END, '[)') WITH &&
    ) WHERE (active_ind = TRUE)
);
COMMENT ON TABLE solar_app.ref_tax_rules IS 'Effective-dated tax-rule components grouped by tax_group_code. Rates are deployment configuration; transaction rows preserve applied snapshots.';
COMMENT ON COLUMN solar_app.ref_tax_rules.tax_rule_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ref_tax_rules.tax_rule_code IS 'Stable code for one versioned tax component rule.';
COMMENT ON COLUMN solar_app.ref_tax_rules.tax_group_code IS 'Groups components that apply together to a transaction.';
COMMENT ON COLUMN solar_app.ref_tax_rules.tax_component_code IS 'Stable component identifier used by calculation contracts.';
COMMENT ON COLUMN solar_app.ref_tax_rules.tax_display_name IS 'Configurable customer-facing component label.';
COMMENT ON COLUMN solar_app.ref_tax_rules.country_id IS 'Country jurisdiction.';
COMMENT ON COLUMN solar_app.ref_tax_rules.state_id IS 'Optional state or region jurisdiction.';
COMMENT ON COLUMN solar_app.ref_tax_rules.tax_classification_code IS 'Optional product or service tax classification matched by the rule.';
COMMENT ON COLUMN solar_app.ref_tax_rules.calculation_method IS 'PERCENTAGE or FIXED_AMOUNT; application and compounding policy remains deployment configuration.';
COMMENT ON COLUMN solar_app.ref_tax_rules.rate_percent IS 'Configured percentage when calculation_method is PERCENTAGE.';
COMMENT ON COLUMN solar_app.ref_tax_rules.rate_amount IS 'Configured amount when calculation_method is FIXED_AMOUNT.';
COMMENT ON COLUMN solar_app.ref_tax_rules.currency_code IS 'Currency of a fixed rate amount; NULL for percentage rules.';
COMMENT ON COLUMN solar_app.ref_tax_rules.priority IS 'Precedence when multiple applicable rules are configured.';
COMMENT ON COLUMN solar_app.ref_tax_rules.effective_from IS 'Inclusive rule-version start date.';
COMMENT ON COLUMN solar_app.ref_tax_rules.effective_to IS 'Inclusive rule-version end date; NULL means open-ended.';
COMMENT ON COLUMN solar_app.ref_tax_rules.active_ind IS 'Soft-delete flag. FALSE excludes the version from rule resolution.';
COMMENT ON COLUMN solar_app.ref_tax_rules.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_tax_rules.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_tax_rules.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_tax_rules.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_ref_tax_rules_lookup ON solar_app.ref_tax_rules (country_id, state_id, tax_classification_code, effective_from, effective_to) WHERE active_ind = TRUE;

CREATE TABLE solar_app.ref_checklist_items (
    checklist_item_id   BIGINT GENERATED ALWAYS AS IDENTITY,
    job_type            VARCHAR(30)  NOT NULL,
    item_code           VARCHAR(50)  NOT NULL,
    item_label          VARCHAR(255) NOT NULL,
    expected_value_type VARCHAR(20)  NOT NULL DEFAULT 'BOOLEAN',
    is_mandatory        BOOLEAN      NOT NULL DEFAULT TRUE,
    sort_order          INTEGER      NOT NULL DEFAULT 0,
    active_ind          BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by          VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by          VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_checklist_items PRIMARY KEY (checklist_item_id),
    CONSTRAINT chk_ref_checklist_items_job_type CHECK (job_type IN ('SERVICE_REQUEST', 'COMPLAINT', 'COMMISSIONING')),
    CONSTRAINT chk_ref_checklist_items_value_type CHECK (expected_value_type IN ('BOOLEAN', 'NUMERIC', 'TEXT'))
);
COMMENT ON TABLE solar_app.ref_checklist_items IS 'Field job-sheet template lines (VOC/ISC, earthing, cleaning, inverter logger) by job type.';
COMMENT ON COLUMN solar_app.ref_checklist_items.checklist_item_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ref_checklist_items.job_type IS 'SERVICE_REQUEST, COMPLAINT, or COMMISSIONING template set.';
COMMENT ON COLUMN solar_app.ref_checklist_items.item_code IS 'Stable item code unique per job_type while active.';
COMMENT ON COLUMN solar_app.ref_checklist_items.item_label IS 'Prompt shown on the technician job sheet.';
COMMENT ON COLUMN solar_app.ref_checklist_items.expected_value_type IS 'BOOLEAN, NUMERIC, or TEXT answer.';
COMMENT ON COLUMN solar_app.ref_checklist_items.is_mandatory IS 'TRUE if the technician must complete this item.';
COMMENT ON COLUMN solar_app.ref_checklist_items.sort_order IS 'Display order on the job sheet.';
COMMENT ON COLUMN solar_app.ref_checklist_items.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_checklist_items.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_checklist_items.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_checklist_items.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_checklist_items.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE UNIQUE INDEX uq_ref_checklist_items_code_active ON solar_app.ref_checklist_items (job_type, item_code) WHERE active_ind = TRUE;

CREATE TABLE solar_app.ref_office_locations (
    office_location_id BIGINT GENERATED ALWAYS AS IDENTITY,
    office_code        VARCHAR(30)   NOT NULL,
    office_name        VARCHAR(150)  NOT NULL,
    address_line1      VARCHAR(255)  NOT NULL,
    address_line2      VARCHAR(255),
    city_id            BIGINT,
    pincode_id         BIGINT,
    latitude           NUMERIC(10,7) NOT NULL,
    longitude          NUMERIC(10,7) NOT NULL,
    is_default         BOOLEAN       NOT NULL DEFAULT FALSE,
    active_ind         BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by         VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by         VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on         TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on         TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_office_locations PRIMARY KEY (office_location_id),
    CONSTRAINT uq_ref_office_locations_code UNIQUE (office_code),
    CONSTRAINT fk_office_city FOREIGN KEY (city_id) REFERENCES solar_app.ref_cities (city_id) ON DELETE RESTRICT,
    CONSTRAINT fk_office_pincode FOREIGN KEY (pincode_id) REFERENCES solar_app.ref_pincodes (pincode_id) ON DELETE RESTRICT,
    CONSTRAINT chk_office_lat CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT chk_office_lon CHECK (longitude BETWEEN -180 AND 180)
);
COMMENT ON TABLE solar_app.ref_office_locations IS 'Company office/branch points used as the origin for site-visit distance and charge slabs.';
COMMENT ON COLUMN solar_app.ref_office_locations.office_location_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ref_office_locations.office_code IS 'Stable deployment-defined office code.';
COMMENT ON COLUMN solar_app.ref_office_locations.office_name IS 'Display name of the office.';
COMMENT ON COLUMN solar_app.ref_office_locations.address_line1 IS 'Office street address line 1.';
COMMENT ON COLUMN solar_app.ref_office_locations.address_line2 IS 'Office street address line 2.';
COMMENT ON COLUMN solar_app.ref_office_locations.city_id IS 'FK to city.';
COMMENT ON COLUMN solar_app.ref_office_locations.pincode_id IS 'FK to postal-code master.';
COMMENT ON COLUMN solar_app.ref_office_locations.latitude IS 'Office latitude for haversine distance in SQL functions.';
COMMENT ON COLUMN solar_app.ref_office_locations.longitude IS 'Office longitude for haversine distance in SQL functions.';
COMMENT ON COLUMN solar_app.ref_office_locations.is_default IS 'TRUE is the deployment default origin when a visit does not specify an office.';
COMMENT ON COLUMN solar_app.ref_office_locations.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_office_locations.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_office_locations.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_office_locations.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_office_locations.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE UNIQUE INDEX uq_ref_office_locations_one_default ON solar_app.ref_office_locations ((1)) WHERE is_default = TRUE AND active_ind = TRUE;

CREATE TABLE solar_app.organization_details (
    organization_id          BIGINT GENERATED ALWAYS AS IDENTITY,
    legal_name               VARCHAR(200) NOT NULL,
    display_name             VARCHAR(200) NOT NULL,
    runtime_app_name         VARCHAR(150) NOT NULL,
    primary_logo_url         VARCHAR(500),
    secondary_logo_url       VARCHAR(500),
    primary_theme_color      VARCHAR(9),
    secondary_theme_color    VARCHAR(9),
    support_email            VARCHAR(255),
    support_phone_e164       VARCHAR(16),
    default_country_id       BIGINT       NOT NULL,
    default_currency_code    CHAR(3)      NOT NULL,
    locale_code              VARCHAR(20),
    time_zone_name           VARCHAR(100) NOT NULL,
    active_ind               BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by               VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by               VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on               TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on               TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_organization_details PRIMARY KEY (organization_id),
    CONSTRAINT fk_organization_country FOREIGN KEY (default_country_id) REFERENCES solar_app.ref_countries (country_id) ON DELETE RESTRICT,
    CONSTRAINT fk_organization_currency FOREIGN KEY (default_currency_code) REFERENCES solar_app.ref_currencies (currency_code) ON DELETE RESTRICT,
    CONSTRAINT chk_organization_primary_color CHECK (primary_theme_color IS NULL OR primary_theme_color ~ '^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$'),
    CONSTRAINT chk_organization_secondary_color CHECK (secondary_theme_color IS NULL OR secondary_theme_color ~ '^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$'),
    CONSTRAINT chk_organization_support_phone CHECK (support_phone_e164 IS NULL OR support_phone_e164 ~ '^\+[1-9][0-9]{3,14}$')
);
COMMENT ON TABLE solar_app.organization_details IS 'Single-company deployment profile for runtime branding and non-secret regional defaults. Native package identity, endpoints, and credentials remain deployment configuration.';
COMMENT ON COLUMN solar_app.organization_details.organization_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.organization_details.legal_name IS 'Legal company name used on business documents.';
COMMENT ON COLUMN solar_app.organization_details.display_name IS 'Customer-facing company name.';
COMMENT ON COLUMN solar_app.organization_details.runtime_app_name IS 'Runtime application title shown inside the app; launcher name is build configuration.';
COMMENT ON COLUMN solar_app.organization_details.primary_logo_url IS 'Managed URL for the primary runtime logo.';
COMMENT ON COLUMN solar_app.organization_details.secondary_logo_url IS 'Optional managed URL for an alternate logo.';
COMMENT ON COLUMN solar_app.organization_details.primary_theme_color IS 'Runtime primary theme color in hexadecimal RGB or RGBA notation.';
COMMENT ON COLUMN solar_app.organization_details.secondary_theme_color IS 'Runtime secondary theme color in hexadecimal RGB or RGBA notation.';
COMMENT ON COLUMN solar_app.organization_details.support_email IS 'Customer-support email displayed at runtime.';
COMMENT ON COLUMN solar_app.organization_details.support_phone_e164 IS 'Optional customer-support phone in normalized E.164 format.';
COMMENT ON COLUMN solar_app.organization_details.default_country_id IS 'Deployment default country for country-dependent configuration.';
COMMENT ON COLUMN solar_app.organization_details.default_currency_code IS 'Deployment default ISO currency code.';
COMMENT ON COLUMN solar_app.organization_details.locale_code IS 'Optional default locale code for formatting and labels.';
COMMENT ON COLUMN solar_app.organization_details.time_zone_name IS 'Deployment IANA time-zone name.';
COMMENT ON COLUMN solar_app.organization_details.active_ind IS 'Soft-delete flag. A partial unique index permits only one active deployment profile.';
COMMENT ON COLUMN solar_app.organization_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.organization_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.organization_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.organization_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE UNIQUE INDEX uq_organization_details_one_active ON solar_app.organization_details ((1)) WHERE active_ind = TRUE;

CREATE TABLE solar_app.ref_visit_charge_slabs (
    visit_charge_slab_id        BIGINT GENERATED ALWAYS AS IDENTITY,
    visit_purpose_ref_data_id   BIGINT,
    min_distance_km             NUMERIC(8,2)  NOT NULL,
    max_distance_km             NUMERIC(8,2),
    charge_amount               NUMERIC(12,2) NOT NULL,
    currency_code               CHAR(3)       NOT NULL,
    is_free_ind                 BOOLEAN       NOT NULL,
    effective_from              DATE          NOT NULL,
    effective_to                DATE,
    sort_order                  INTEGER       NOT NULL DEFAULT 0,
    distance_range              NUMRANGE GENERATED ALWAYS AS
                                (numrange(min_distance_km, max_distance_km, '[)')) STORED,
    active_ind                  BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by                  VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by                  VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on                  TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                  TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ref_visit_charge_slabs PRIMARY KEY (visit_charge_slab_id),
    CONSTRAINT fk_vcs_purpose FOREIGN KEY (visit_purpose_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_vcs_currency FOREIGN KEY (currency_code) REFERENCES solar_app.ref_currencies (currency_code) ON DELETE RESTRICT,
    CONSTRAINT chk_vcs_km CHECK (min_distance_km >= 0 AND (max_distance_km IS NULL OR max_distance_km > min_distance_km)),
    CONSTRAINT chk_vcs_amt CHECK (charge_amount >= 0),
    CONSTRAINT chk_vcs_free_amount CHECK (is_free_ind = FALSE OR charge_amount = 0),
    CONSTRAINT chk_vcs_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT ex_vcs_no_overlap EXCLUDE USING gist (
        COALESCE(visit_purpose_ref_data_id, 0) WITH =,
        distance_range WITH &&,
        daterange(effective_from, CASE WHEN effective_to IS NULL THEN NULL ELSE effective_to + 1 END, '[)') WITH &&
    ) WHERE (active_ind = TRUE)
);
COMMENT ON TABLE solar_app.ref_visit_charge_slabs IS 'Effective-dated site-visit charges by non-overlapping half-open distance band. A purpose-specific row takes precedence over a NULL-purpose default; free entitlement can override the configured amount.';
COMMENT ON COLUMN solar_app.ref_visit_charge_slabs.visit_charge_slab_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ref_visit_charge_slabs.visit_purpose_ref_data_id IS 'Optional SITE_VISIT_PURPOSES override; NULL applies to every purpose unless a more specific slab exists.';
COMMENT ON COLUMN solar_app.ref_visit_charge_slabs.min_distance_km IS 'Inclusive lower km of this band.';
COMMENT ON COLUMN solar_app.ref_visit_charge_slabs.max_distance_km IS 'Exclusive upper km of this band; NULL means the final open-ended band.';
COMMENT ON COLUMN solar_app.ref_visit_charge_slabs.charge_amount IS 'Configured offline visit fee in currency_code.';
COMMENT ON COLUMN solar_app.ref_visit_charge_slabs.currency_code IS 'Currency of charge_amount.';
COMMENT ON COLUMN solar_app.ref_visit_charge_slabs.is_free_ind IS 'TRUE identifies an explicitly zero-priced configured band.';
COMMENT ON COLUMN solar_app.ref_visit_charge_slabs.effective_from IS 'Inclusive rule-version start date.';
COMMENT ON COLUMN solar_app.ref_visit_charge_slabs.effective_to IS 'Inclusive rule-version end date; NULL means open-ended.';
COMMENT ON COLUMN solar_app.ref_visit_charge_slabs.sort_order IS 'Admin display order.';
COMMENT ON COLUMN solar_app.ref_visit_charge_slabs.distance_range IS 'Generated half-open distance range used for overlap protection.';
COMMENT ON COLUMN solar_app.ref_visit_charge_slabs.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_visit_charge_slabs.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ref_visit_charge_slabs.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ref_visit_charge_slabs.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ref_visit_charge_slabs.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_vcs_lookup ON solar_app.ref_visit_charge_slabs (visit_purpose_ref_data_id, effective_from, effective_to) WHERE active_ind = TRUE;

-- =====================================================================
-- MODULE 1 — Users
-- =====================================================================

CREATE TABLE solar_app.user_details (
    user_id                        BIGINT GENERATED ALWAYS AS IDENTITY,
    country_id                     BIGINT      NOT NULL,
    mobile_e164                    VARCHAR(16) NOT NULL,
    full_name                      VARCHAR(150),
    email                          VARCHAR(150),
    secondary_mobile_e164          VARCHAR(16),
    emergency_contact_name         VARCHAR(150),
    emergency_contact_mobile_e164  VARCHAR(16),
    role_ref_data_id               BIGINT      NOT NULL,
    preferred_language_ref_data_id BIGINT,
    pin_hash                       VARCHAR(255),
    biometric_enabled              BOOLEAN     NOT NULL DEFAULT FALSE,
    push_notifications_enabled     BOOLEAN     NOT NULL DEFAULT TRUE,
    profile_photo_url              VARCHAR(500),
    admin_registered               BOOLEAN     NOT NULL DEFAULT FALSE,
    account_status_ref_data_id     BIGINT,
    registration_source_ref_data_id BIGINT,
    last_login_on                  TIMESTAMPTZ,
    failed_otp_count               INTEGER     NOT NULL DEFAULT 0,
    otp_window_started_on          TIMESTAMPTZ,
    lockout_until                  TIMESTAMPTZ,
    active_ind                     BOOLEAN     NOT NULL DEFAULT TRUE,
    created_by                     VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    updated_by                     VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    created_on                     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_user_details PRIMARY KEY (user_id),
    CONSTRAINT fk_user_details_country FOREIGN KEY (country_id) REFERENCES solar_app.ref_countries (country_id) ON DELETE RESTRICT,
    CONSTRAINT fk_user_details_role FOREIGN KEY (role_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_user_details_language FOREIGN KEY (preferred_language_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_user_details_acct_status FOREIGN KEY (account_status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_user_details_reg_source FOREIGN KEY (registration_source_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT chk_user_details_mobile CHECK (mobile_e164 ~ '^\+[1-9][0-9]{3,14}$'),
    CONSTRAINT chk_user_details_secondary_mobile CHECK (secondary_mobile_e164 IS NULL OR secondary_mobile_e164 ~ '^\+[1-9][0-9]{3,14}$'),
    CONSTRAINT chk_user_details_emergency_mobile CHECK (emergency_contact_mobile_e164 IS NULL OR emergency_contact_mobile_e164 ~ '^\+[1-9][0-9]{3,14}$'),
    CONSTRAINT chk_user_details_otp_count CHECK (failed_otp_count >= 0)
);
COMMENT ON TABLE solar_app.user_details IS 'Single login table for every app persona: customer, technician, sales, and admin. Technicians and customers are users; extra tables only hold role-specific fields.';
COMMENT ON COLUMN solar_app.user_details.user_id IS 'Surrogate primary key; stored as logged_in_user_id in function payloads.';
COMMENT ON COLUMN solar_app.user_details.country_id IS 'FK to ref_countries for country-specific display and validation metadata.';
COMMENT ON COLUMN solar_app.user_details.mobile_e164 IS 'Normalized E.164 mobile number; unique among active users and used as the OTP login key.';
COMMENT ON COLUMN solar_app.user_details.full_name IS 'Display name on profile and tickets.';
COMMENT ON COLUMN solar_app.user_details.email IS 'Optional communication email.';
COMMENT ON COLUMN solar_app.user_details.secondary_mobile_e164 IS 'Optional second contact in normalized E.164 format.';
COMMENT ON COLUMN solar_app.user_details.emergency_contact_name IS 'Emergency contact person name.';
COMMENT ON COLUMN solar_app.user_details.emergency_contact_mobile_e164 IS 'Emergency contact number in normalized E.164 format.';
COMMENT ON COLUMN solar_app.user_details.role_ref_data_id IS 'FK to USER_ROLES (customer, technician, sales, admin).';
COMMENT ON COLUMN solar_app.user_details.preferred_language_ref_data_id IS 'FK to APP_LANGUAGES (EN/MR/HI).';
COMMENT ON COLUMN solar_app.user_details.pin_hash IS 'Hashed 4-digit PIN for quick login; never store plaintext PIN.';
COMMENT ON COLUMN solar_app.user_details.biometric_enabled IS 'TRUE if device biometric quick-login is allowed.';
COMMENT ON COLUMN solar_app.user_details.push_notifications_enabled IS 'Master push toggle. Inbox rows are still written when FALSE.';
COMMENT ON COLUMN solar_app.user_details.profile_photo_url IS 'Profile photo; for technicians this is the assigned-engineer card photo.';
COMMENT ON COLUMN solar_app.user_details.admin_registered IS 'TRUE when admin created/activated this login (Path B post-install, or admin-created staff). FALSE = Path A self-app / lead funnel until they complete self-registration (functions then set TRUE).';
COMMENT ON COLUMN solar_app.user_details.account_status_ref_data_id IS 'ACTIVE vs SUSPENDED. Suspend blocks login without soft-delete.';
COMMENT ON COLUMN solar_app.user_details.registration_source_ref_data_id IS 'REG_SELF_APP (Path A) vs REG_ADMIN_POST_INSTALL (Path B).';
COMMENT ON COLUMN solar_app.user_details.last_login_on IS 'Last successful OTP/PIN login timestamp.';
COMMENT ON COLUMN solar_app.user_details.failed_otp_count IS 'Failed OTP attempts in the current lockout window.';
COMMENT ON COLUMN solar_app.user_details.otp_window_started_on IS 'Start of the current 3-fail-per-hour window.';
COMMENT ON COLUMN solar_app.user_details.lockout_until IS 'Login blocked until this instant after too many OTP failures.';
COMMENT ON COLUMN solar_app.user_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.user_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.user_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.user_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.user_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE UNIQUE INDEX uq_user_details_mobile_active ON solar_app.user_details (mobile_e164) WHERE active_ind = TRUE;
CREATE INDEX idx_user_details_role ON solar_app.user_details (role_ref_data_id);

CREATE TABLE solar_app.technician_details (
    technician_id     BIGINT GENERATED ALWAYS AS IDENTITY,
    user_id           BIGINT        NOT NULL,
    employee_code     VARCHAR(30)   NOT NULL,
    service_radius_km NUMERIC(6,2),
    is_available      BOOLEAN       NOT NULL DEFAULT TRUE,
    current_latitude  NUMERIC(10,7),
    current_longitude NUMERIC(10,7),
    active_ind        BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by        VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by        VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on        TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on        TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_technician_details PRIMARY KEY (technician_id),
    CONSTRAINT fk_technician_details_user FOREIGN KEY (user_id) REFERENCES solar_app.user_details (user_id) ON DELETE RESTRICT,
    CONSTRAINT uq_technician_details_user UNIQUE (user_id),
    CONSTRAINT uq_technician_details_emp_code UNIQUE (employee_code),
    CONSTRAINT chk_technician_details_lat CHECK (current_latitude IS NULL OR current_latitude BETWEEN -90 AND 90),
    CONSTRAINT chk_technician_details_lon CHECK (current_longitude IS NULL OR current_longitude BETWEEN -180 AND 180)
);
COMMENT ON TABLE solar_app.technician_details IS 'Field-engineer profile for a user who already exists in user_details with ROLE_TECHNICIAN. Not a separate login: OTP, name, mobile, photo, push, and language live on user_details. This row holds only job-queue fields (employee code, availability, GPS, radius). Required 1:1 — creating a technician user must insert both rows in the same SQL function.';
COMMENT ON COLUMN solar_app.technician_details.technician_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.technician_details.user_id IS 'Required 1:1 FK to user_details. This person logs into the app with that user_id (same OTP as any other user). UNIQUE so one user cannot have two technician profiles.';
COMMENT ON COLUMN solar_app.technician_details.employee_code IS 'HR/employee code unique among technicians.';
COMMENT ON COLUMN solar_app.technician_details.service_radius_km IS 'Optional service coverage radius in kilometres.';
COMMENT ON COLUMN solar_app.technician_details.is_available IS 'FALSE hides the technician from new job allocation.';
COMMENT ON COLUMN solar_app.technician_details.current_latitude IS 'Last known latitude for arrival tracking.';
COMMENT ON COLUMN solar_app.technician_details.current_longitude IS 'Last known longitude for arrival tracking.';
COMMENT ON COLUMN solar_app.technician_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.technician_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.technician_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.technician_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.technician_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

-- =====================================================================
-- MODULE 10 — Logging
-- =====================================================================

CREATE TABLE solar_app.log_api_execution (
    api_log_id        BIGINT GENERATED ALWAYS AS IDENTITY,
    api_endpoint      VARCHAR(255) NOT NULL,
    http_method       VARCHAR(10),
    logged_in_user_id VARCHAR(50),
    user_id           BIGINT,
    client_ip         VARCHAR(45),
    request_payload   JSONB,
    response_payload  JSONB,
    http_status       INTEGER,
    execution_status  VARCHAR(20)  NOT NULL,
    error_message     TEXT,
    execution_time_ms INTEGER,
    active_ind        BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by        VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by        VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on        TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on        TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_log_api_execution PRIMARY KEY (api_log_id),
    CONSTRAINT fk_log_api_execution_user FOREIGN KEY (user_id) REFERENCES solar_app.user_details (user_id) ON DELETE SET NULL,
    CONSTRAINT chk_log_api_execution_status CHECK (execution_status IN ('SUCCESS', 'ERROR'))
);
COMMENT ON TABLE solar_app.log_api_execution IS 'One audit row per API invocation (endpoint, latency, payload snapshot, SUCCESS/ERROR).';
COMMENT ON COLUMN solar_app.log_api_execution.api_log_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.log_api_execution.api_endpoint IS 'HTTP path or logical endpoint name from the payload.';
COMMENT ON COLUMN solar_app.log_api_execution.http_method IS 'GET, POST, PUT, DELETE, etc.';
COMMENT ON COLUMN solar_app.log_api_execution.logged_in_user_id IS 'String actor id from the JSON envelope.';
COMMENT ON COLUMN solar_app.log_api_execution.user_id IS 'Optional FK to user_details when the actor is a known user.';
COMMENT ON COLUMN solar_app.log_api_execution.client_ip IS 'Client IP captured by the API proxy.';
COMMENT ON COLUMN solar_app.log_api_execution.request_payload IS 'Request JSON snapshot (redact secrets in functions).';
COMMENT ON COLUMN solar_app.log_api_execution.response_payload IS 'Response JSON snapshot.';
COMMENT ON COLUMN solar_app.log_api_execution.http_status IS 'HTTP status returned to the client.';
COMMENT ON COLUMN solar_app.log_api_execution.execution_status IS 'SUCCESS or ERROR at the API layer.';
COMMENT ON COLUMN solar_app.log_api_execution.error_message IS 'Error text when execution_status is ERROR.';
COMMENT ON COLUMN solar_app.log_api_execution.execution_time_ms IS 'Elapsed milliseconds for the call.';
COMMENT ON COLUMN solar_app.log_api_execution.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.log_api_execution.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.log_api_execution.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.log_api_execution.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.log_api_execution.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_log_api_execution_endpoint ON solar_app.log_api_execution (api_endpoint, created_on DESC);

CREATE TABLE solar_app.log_sql_functions (
    function_log_id   BIGINT GENERATED ALWAYS AS IDENTITY,
    api_endpoint      VARCHAR(255),
    function_name     VARCHAR(150) NOT NULL,
    logged_in_user_id VARCHAR(50),
    user_id           BIGINT,
    request_payload   JSONB,
    execution_status  VARCHAR(20)  NOT NULL,
    error_message     TEXT,
    sql_state         VARCHAR(10),
    execution_time_ms INTEGER,
    active_ind        BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by        VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by        VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on        TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on        TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_log_sql_functions PRIMARY KEY (function_log_id),
    CONSTRAINT fk_log_sql_functions_user FOREIGN KEY (user_id) REFERENCES solar_app.user_details (user_id) ON DELETE SET NULL,
    CONSTRAINT chk_log_sql_functions_status CHECK (execution_status IN ('SUCCESS', 'ERROR'))
);
COMMENT ON TABLE solar_app.log_sql_functions IS 'PL/pgSQL function execution audit written by fn_log_function_execution.';
COMMENT ON COLUMN solar_app.log_sql_functions.function_log_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.log_sql_functions.api_endpoint IS 'Calling API endpoint for correlation.';
COMMENT ON COLUMN solar_app.log_sql_functions.function_name IS 'PL/pgSQL function name (fn_*).';
COMMENT ON COLUMN solar_app.log_sql_functions.logged_in_user_id IS 'String actor id from the JSON envelope.';
COMMENT ON COLUMN solar_app.log_sql_functions.user_id IS 'Optional FK to user_details.';
COMMENT ON COLUMN solar_app.log_sql_functions.request_payload IS 'p_payload snapshot passed into the function.';
COMMENT ON COLUMN solar_app.log_sql_functions.execution_status IS 'SUCCESS or ERROR from the function.';
COMMENT ON COLUMN solar_app.log_sql_functions.error_message IS 'SQLERRM when the function hit EXCEPTION.';
COMMENT ON COLUMN solar_app.log_sql_functions.sql_state IS 'PostgreSQL SQLSTATE of the exception.';
COMMENT ON COLUMN solar_app.log_sql_functions.execution_time_ms IS 'Elapsed milliseconds inside the function.';
COMMENT ON COLUMN solar_app.log_sql_functions.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.log_sql_functions.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.log_sql_functions.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.log_sql_functions.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.log_sql_functions.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_log_sql_functions_name ON solar_app.log_sql_functions (function_name, created_on DESC);

CREATE TABLE solar_app.log_user_sessions (
    session_id     BIGINT GENERATED ALWAYS AS IDENTITY,
    user_id        BIGINT,
    mobile_e164    VARCHAR(16) NOT NULL,
    device_id      VARCHAR(100),
    device_model   VARCHAR(100),
    device_os      VARCHAR(50),
    ip_address     VARCHAR(45),
    jwt_token_hash VARCHAR(255),
    push_token     VARCHAR(512),
    session_status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    login_on       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_on   TIMESTAMPTZ,
    logout_on      TIMESTAMPTZ,
    active_ind     BOOLEAN     NOT NULL DEFAULT TRUE,
    created_by     VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    updated_by     VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    created_on     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_log_user_sessions PRIMARY KEY (session_id),
    CONSTRAINT fk_log_user_sessions_user FOREIGN KEY (user_id) REFERENCES solar_app.user_details (user_id) ON DELETE SET NULL,
    CONSTRAINT chk_log_user_sessions_mobile CHECK (mobile_e164 ~ '^\+[1-9][0-9]{3,14}$'),
    CONSTRAINT chk_log_user_sessions_status CHECK (session_status IN ('PENDING_OTP', 'ACTIVE', 'EXPIRED', 'LOGGED_OUT', 'LOCKED'))
);
COMMENT ON TABLE solar_app.log_user_sessions IS 'Login session, device, hashed JWT, and FCM push token. Named log_* per project logging rules.';
COMMENT ON COLUMN solar_app.log_user_sessions.session_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.log_user_sessions.user_id IS 'Set after OTP succeeds; NULL while PENDING_OTP.';
COMMENT ON COLUMN solar_app.log_user_sessions.mobile_e164 IS 'Normalized E.164 mobile used to start this login.';
COMMENT ON COLUMN solar_app.log_user_sessions.device_id IS 'Client device identifier.';
COMMENT ON COLUMN solar_app.log_user_sessions.device_model IS 'Device model string for audit.';
COMMENT ON COLUMN solar_app.log_user_sessions.device_os IS 'Android/iOS version string.';
COMMENT ON COLUMN solar_app.log_user_sessions.ip_address IS 'Login IP address.';
COMMENT ON COLUMN solar_app.log_user_sessions.jwt_token_hash IS 'Hash of the issued JWT; never store the raw token.';
COMMENT ON COLUMN solar_app.log_user_sessions.push_token IS 'FCM (or equivalent) device token for Module 13 push.';
COMMENT ON COLUMN solar_app.log_user_sessions.session_status IS 'PENDING_OTP, ACTIVE, EXPIRED, LOGGED_OUT, or LOCKED.';
COMMENT ON COLUMN solar_app.log_user_sessions.login_on IS 'When the session was created.';
COMMENT ON COLUMN solar_app.log_user_sessions.last_seen_on IS 'Last authenticated activity.';
COMMENT ON COLUMN solar_app.log_user_sessions.logout_on IS 'When the user logged out, if applicable.';
COMMENT ON COLUMN solar_app.log_user_sessions.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.log_user_sessions.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.log_user_sessions.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.log_user_sessions.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.log_user_sessions.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_log_user_sessions_user ON solar_app.log_user_sessions (user_id, created_on DESC);

CREATE TABLE solar_app.log_otp_attempts (
    otp_attempt_id      BIGINT GENERATED ALWAYS AS IDENTITY,
    mobile_e164         VARCHAR(16)  NOT NULL,
    session_id          BIGINT,
    otp_hash            VARCHAR(255) NOT NULL,
    otp_expires_on      TIMESTAMPTZ  NOT NULL,
    is_consumed         BOOLEAN      NOT NULL DEFAULT FALSE,
    attempt_no          INTEGER      NOT NULL DEFAULT 1,
    resend_available_on TIMESTAMPTZ,
    ip_address          VARCHAR(45),
    active_ind          BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by          VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by          VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_log_otp_attempts PRIMARY KEY (otp_attempt_id),
    CONSTRAINT fk_log_otp_attempts_session FOREIGN KEY (session_id) REFERENCES solar_app.log_user_sessions (session_id) ON DELETE SET NULL,
    CONSTRAINT chk_log_otp_attempts_mobile CHECK (mobile_e164 ~ '^\+[1-9][0-9]{3,14}$'),
    CONSTRAINT chk_log_otp_attempts_no CHECK (attempt_no > 0)
);
COMMENT ON TABLE solar_app.log_otp_attempts IS 'Hashed OTP dispatch and verification audit. Cooldown, expiry, and lockout limits come from effective-dated business parameters. Not used for ticket OTP.';
COMMENT ON COLUMN solar_app.log_otp_attempts.otp_attempt_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.log_otp_attempts.mobile_e164 IS 'Normalized E.164 mobile to which the OTP was sent.';
COMMENT ON COLUMN solar_app.log_otp_attempts.session_id IS 'FK to the login session this OTP belongs to.';
COMMENT ON COLUMN solar_app.log_otp_attempts.otp_hash IS 'Hashed OTP; never store plaintext OTP.';
COMMENT ON COLUMN solar_app.log_otp_attempts.otp_expires_on IS 'OTP expiry instant.';
COMMENT ON COLUMN solar_app.log_otp_attempts.is_consumed IS 'TRUE after successful verify; blocks replay.';
COMMENT ON COLUMN solar_app.log_otp_attempts.attempt_no IS 'Nth send/verify in this window.';
COMMENT ON COLUMN solar_app.log_otp_attempts.resend_available_on IS 'Earliest time another OTP may be sent under the applied parameter version.';
COMMENT ON COLUMN solar_app.log_otp_attempts.ip_address IS 'IP of the dispatch/verify request.';
COMMENT ON COLUMN solar_app.log_otp_attempts.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.log_otp_attempts.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.log_otp_attempts.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.log_otp_attempts.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.log_otp_attempts.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_log_otp_attempts_mobile_created ON solar_app.log_otp_attempts (mobile_e164, created_on DESC);

-- =====================================================================
-- MODULE 13 — Notifications (inbox + push log)
-- =====================================================================

CREATE TABLE solar_app.notification_details (
    notification_id                 BIGINT GENERATED ALWAYS AS IDENTITY,
    recipient_user_id               BIGINT        NOT NULL,
    notification_type_ref_data_id   BIGINT        NOT NULL,
    title                           VARCHAR(200)  NOT NULL,
    body                            VARCHAR(1000) NOT NULL,
    payload_json                    JSONB         NOT NULL DEFAULT '{}'::jsonb,
    related_entity_type             VARCHAR(40),
    related_entity_id               BIGINT,
    is_read_ind                     BOOLEAN       NOT NULL DEFAULT FALSE,
    read_on                         TIMESTAMPTZ,
    active_ind                      BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by                      VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by                      VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on                      TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                      TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_notification_details PRIMARY KEY (notification_id),
    CONSTRAINT fk_ntf_recipient FOREIGN KEY (recipient_user_id) REFERENCES solar_app.user_details (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ntf_type FOREIGN KEY (notification_type_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT chk_ntf_entity_type CHECK (
        related_entity_type IS NULL
        OR related_entity_type IN (
            'PRODUCT', 'ENQUIRY', 'ORDER', 'SERVICE_REQUEST', 'SERVICE_MILESTONE',
            'TICKET', 'JOB', 'KYC', 'INVOICE', 'PAYMENT', 'FOLLOWUP', 'LEAD', 'AMC', 'USER', 'SITE_VISIT'
        )
    )
);
COMMENT ON TABLE solar_app.notification_details IS 'In-app notification inbox: one row per recipient per event. Enqueued by fn_create_notification_details (no triggers).';
COMMENT ON COLUMN solar_app.notification_details.notification_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.notification_details.recipient_user_id IS 'User who should see this inbox row.';
COMMENT ON COLUMN solar_app.notification_details.notification_type_ref_data_id IS 'FK to NOTIFICATION_TYPES (catalogue, enquiry, complaint, reminder, …).';
COMMENT ON COLUMN solar_app.notification_details.title IS 'Short inbox/push title.';
COMMENT ON COLUMN solar_app.notification_details.body IS 'Inbox/push body text.';
COMMENT ON COLUMN solar_app.notification_details.payload_json IS 'Deep-link JSON: entity_type, entity_id, extras.';
COMMENT ON COLUMN solar_app.notification_details.related_entity_type IS 'Parent entity class for navigation (PRODUCT, TICKET, …).';
COMMENT ON COLUMN solar_app.notification_details.related_entity_id IS 'Primary key of the related entity.';
COMMENT ON COLUMN solar_app.notification_details.is_read_ind IS 'FALSE counts toward the unread badge.';
COMMENT ON COLUMN solar_app.notification_details.read_on IS 'When the recipient marked the row read.';
COMMENT ON COLUMN solar_app.notification_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.notification_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.notification_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.notification_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.notification_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_ntf_recipient_unread ON solar_app.notification_details (recipient_user_id, created_on DESC) WHERE active_ind = TRUE;
CREATE INDEX idx_ntf_type ON solar_app.notification_details (notification_type_ref_data_id);

CREATE TABLE solar_app.log_notification_delivery (
    delivery_id              BIGINT GENERATED ALWAYS AS IDENTITY,
    notification_id          BIGINT       NOT NULL,
    session_id               BIGINT,
    channel_ref_data_id      BIGINT       NOT NULL,
    delivery_status_ref_data_id BIGINT    NOT NULL,
    provider_message_id      VARCHAR(200),
    error_message            VARCHAR(1000),
    sent_on                  TIMESTAMPTZ,
    active_ind               BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by               VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by               VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on               TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on               TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_log_notification_delivery PRIMARY KEY (delivery_id),
    CONSTRAINT fk_ntf_del_ntf FOREIGN KEY (notification_id) REFERENCES solar_app.notification_details (notification_id) ON DELETE CASCADE,
    CONSTRAINT fk_ntf_del_session FOREIGN KEY (session_id) REFERENCES solar_app.log_user_sessions (session_id) ON DELETE SET NULL,
    CONSTRAINT fk_ntf_del_channel FOREIGN KEY (channel_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ntf_del_status FOREIGN KEY (delivery_status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT
);
COMMENT ON TABLE solar_app.log_notification_delivery IS 'Push (FCM) send queue and delivery audit. OTP SMS is stored in log_otp_attempts, not here.';
COMMENT ON COLUMN solar_app.log_notification_delivery.delivery_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.log_notification_delivery.notification_id IS 'FK to the inbox row being pushed.';
COMMENT ON COLUMN solar_app.log_notification_delivery.session_id IS 'Session whose push_token was used, if any.';
COMMENT ON COLUMN solar_app.log_notification_delivery.channel_ref_data_id IS 'FK to NOTIFICATION_CHANNELS (typically PUSH).';
COMMENT ON COLUMN solar_app.log_notification_delivery.delivery_status_ref_data_id IS 'FK to PENDING / SENT / FAILED.';
COMMENT ON COLUMN solar_app.log_notification_delivery.provider_message_id IS 'FCM (or provider) message id when sent.';
COMMENT ON COLUMN solar_app.log_notification_delivery.error_message IS 'Provider error text when FAILED.';
COMMENT ON COLUMN solar_app.log_notification_delivery.sent_on IS 'When the worker marked SENT.';
COMMENT ON COLUMN solar_app.log_notification_delivery.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.log_notification_delivery.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.log_notification_delivery.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.log_notification_delivery.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.log_notification_delivery.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_ntf_del_pending ON solar_app.log_notification_delivery (delivery_status_ref_data_id, created_on) WHERE active_ind = TRUE;

-- =====================================================================
-- MODULE 2 — Calculator, leads, quotes
-- =====================================================================

CREATE TABLE solar_app.calculator_estimate_details (
    estimate_id                 BIGINT GENERATED ALWAYS AS IDENTITY,
    user_id                     BIGINT,
    monthly_bill_amount         NUMERIC(12,2) NOT NULL,
    rooftop_area                NUMERIC(12,2) NOT NULL,
    area_unit                   VARCHAR(10)   NOT NULL,
    connection_type_ref_data_id BIGINT        NOT NULL,
    state_id                    BIGINT,
    recommended_capacity_kw     NUMERIC(8,3)  NOT NULL,
    estimated_gross_cost        NUMERIC(14,2) NOT NULL,
    estimated_subsidy_amount    NUMERIC(14,2) NOT NULL DEFAULT 0,
    net_investment_cost         NUMERIC(14,2) NOT NULL,
    estimated_monthly_savings   NUMERIC(12,2),
    estimated_annual_savings    NUMERIC(12,2),
    payback_months              INTEGER,
    co2_reduction_tons_year     NUMERIC(10,3),
    area_insufficient_ind       BOOLEAN       NOT NULL DEFAULT FALSE,
    subsidy_slab_id             BIGINT,
    currency_code               CHAR(3)       NOT NULL,
    applied_parameters_json     JSONB         NOT NULL DEFAULT '{}'::jsonb,
    subsidy_rule_snapshot_json  JSONB         NOT NULL DEFAULT '{}'::jsonb,
    estimate_json               JSONB         NOT NULL DEFAULT '{}'::jsonb,
    active_ind                  BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by                  VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by                  VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on                  TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                  TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_calculator_estimate_details PRIMARY KEY (estimate_id),
    CONSTRAINT fk_calc_est_user FOREIGN KEY (user_id) REFERENCES solar_app.user_details (user_id) ON DELETE SET NULL,
    CONSTRAINT fk_calc_est_conn FOREIGN KEY (connection_type_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_calc_est_state FOREIGN KEY (state_id) REFERENCES solar_app.ref_states (state_id) ON DELETE RESTRICT,
    CONSTRAINT fk_calc_est_slab FOREIGN KEY (subsidy_slab_id) REFERENCES solar_app.ref_subsidy_slabs (subsidy_slab_id) ON DELETE RESTRICT,
    CONSTRAINT fk_calc_est_currency FOREIGN KEY (currency_code) REFERENCES solar_app.ref_currencies (currency_code) ON DELETE RESTRICT,
    CONSTRAINT chk_calc_est_area_unit CHECK (area_unit IN ('SQFT', 'SQM')),
    CONSTRAINT chk_calc_est_bill CHECK (monthly_bill_amount >= 0),
    CONSTRAINT chk_calc_est_area CHECK (rooftop_area > 0)
);
COMMENT ON TABLE solar_app.calculator_estimate_details IS 'Persisted feasibility calculator runs so quotes can reproduce subsidy and savings.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.estimate_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.user_id IS 'Logged-in user; NULL for anonymous calculator runs.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.monthly_bill_amount IS 'Monthly electricity bill input in currency_code.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.rooftop_area IS 'Shade-free rooftop area entered by the user.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.area_unit IS 'SQFT or SQM.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.connection_type_ref_data_id IS 'FK to CONNECTION_TYPES.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.state_id IS 'State used to pick subsidy overlay.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.recommended_capacity_kw IS 'Engine recommended system size.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.estimated_gross_cost IS 'Estimated project cost before subsidy.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.estimated_subsidy_amount IS 'Estimated DBT subsidy.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.net_investment_cost IS 'Gross minus subsidy.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.estimated_monthly_savings IS 'Estimated monthly bill savings.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.estimated_annual_savings IS 'Estimated annual savings.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.payback_months IS 'Simple payback in months.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.co2_reduction_tons_year IS 'Estimated CO₂ reduction (tons/year).';
COMMENT ON COLUMN solar_app.calculator_estimate_details.area_insufficient_ind IS 'TRUE if rooftop area is below the effective configured area rule.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.subsidy_slab_id IS 'Slab used so historical quotes stay explainable.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.currency_code IS 'Currency snapshot used for every monetary estimate column.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.applied_parameters_json IS 'Immutable snapshot of effective business parameter codes and values used for the estimate.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.subsidy_rule_snapshot_json IS 'Immutable snapshot of the applied subsidy scheme, slab, method, rate, cap, and eligibility outcome.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.estimate_json IS 'Full breakdown JSON for PDF quote rendering.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.calculator_estimate_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.calculator_estimate_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.calculator_estimate_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.calculator_estimate_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

CREATE TABLE solar_app.lead_details (
    lead_id                  BIGINT GENERATED ALWAYS AS IDENTITY,
    lead_no                  VARCHAR(30)  NOT NULL,
    estimate_id              BIGINT,
    user_id                  BIGINT,
    full_name                VARCHAR(150) NOT NULL,
    country_id               BIGINT       NOT NULL,
    mobile_e164              VARCHAR(16)  NOT NULL,
    pincode_id               BIGINT,
    pincode                  VARCHAR(20),
    preferred_contact_window VARCHAR(50),
    lead_status_ref_data_id  BIGINT       NOT NULL,
    converted_customer_id    BIGINT,
    assigned_agent_user_id   BIGINT,
    remarks                  VARCHAR(500),
    active_ind               BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by               VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by               VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on               TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on               TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_lead_details PRIMARY KEY (lead_id),
    CONSTRAINT uq_lead_details_lead_no UNIQUE (lead_no),
    CONSTRAINT fk_lead_details_estimate FOREIGN KEY (estimate_id) REFERENCES solar_app.calculator_estimate_details (estimate_id) ON DELETE RESTRICT,
    CONSTRAINT fk_lead_details_user FOREIGN KEY (user_id) REFERENCES solar_app.user_details (user_id) ON DELETE SET NULL,
    CONSTRAINT fk_lead_details_country FOREIGN KEY (country_id) REFERENCES solar_app.ref_countries (country_id) ON DELETE RESTRICT,
    CONSTRAINT fk_lead_details_pincode FOREIGN KEY (pincode_id) REFERENCES solar_app.ref_pincodes (pincode_id) ON DELETE RESTRICT,
    CONSTRAINT fk_lead_details_status FOREIGN KEY (lead_status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_lead_details_agent FOREIGN KEY (assigned_agent_user_id) REFERENCES solar_app.user_details (user_id) ON DELETE SET NULL,
    CONSTRAINT chk_lead_details_mobile CHECK (mobile_e164 ~ '^\+[1-9][0-9]{3,14}$')
);
COMMENT ON TABLE solar_app.lead_details IS 'Sales lead after Get quote or after converting a product enquiry.';
COMMENT ON COLUMN solar_app.lead_details.lead_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.lead_details.lead_no IS 'Public unique lead number.';
COMMENT ON COLUMN solar_app.lead_details.estimate_id IS 'Calculator run this lead was created from, if any.';
COMMENT ON COLUMN solar_app.lead_details.user_id IS 'App user who became a lead, if already registered.';
COMMENT ON COLUMN solar_app.lead_details.full_name IS 'Lead contact name.';
COMMENT ON COLUMN solar_app.lead_details.country_id IS 'Country used for address and country-dependent validation metadata.';
COMMENT ON COLUMN solar_app.lead_details.mobile_e164 IS 'Lead contact number in normalized E.164 format.';
COMMENT ON COLUMN solar_app.lead_details.pincode_id IS 'FK to installation postal code when known.';
COMMENT ON COLUMN solar_app.lead_details.pincode IS 'Raw postal code if a master row is unavailable.';
COMMENT ON COLUMN solar_app.lead_details.preferred_contact_window IS 'Preferred callback window.';
COMMENT ON COLUMN solar_app.lead_details.lead_status_ref_data_id IS 'FK to LEAD_STATUSES.';
COMMENT ON COLUMN solar_app.lead_details.converted_customer_id IS 'Customer created after onboarding; deferred FK.';
COMMENT ON COLUMN solar_app.lead_details.assigned_agent_user_id IS 'Sales agent owner.';
COMMENT ON COLUMN solar_app.lead_details.remarks IS 'Internal sales notes.';
COMMENT ON COLUMN solar_app.lead_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.lead_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.lead_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.lead_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.lead_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_lead_details_mobile ON solar_app.lead_details (mobile_e164);

CREATE TABLE solar_app.quote_details (
    quote_id                 BIGINT GENERATED ALWAYS AS IDENTITY,
    quote_no                 VARCHAR(30)   NOT NULL,
    lead_id                  BIGINT        NOT NULL,
    estimate_id              BIGINT,
    quote_status_ref_data_id BIGINT        NOT NULL,
    subsidy_slab_id          BIGINT,
    gross_amount             NUMERIC(14,2) NOT NULL,
    subsidy_amount           NUMERIC(14,2) NOT NULL DEFAULT 0,
    net_amount               NUMERIC(14,2) NOT NULL,
    currency_code            CHAR(3)       NOT NULL,
    rule_snapshot_json       JSONB         NOT NULL DEFAULT '{}'::jsonb,
    pdf_url                  VARCHAR(500),
    valid_until              DATE,
    active_ind               BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by               VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by               VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_quote_details PRIMARY KEY (quote_id),
    CONSTRAINT uq_quote_details_quote_no UNIQUE (quote_no),
    CONSTRAINT fk_quote_details_lead FOREIGN KEY (lead_id) REFERENCES solar_app.lead_details (lead_id) ON DELETE RESTRICT,
    CONSTRAINT fk_quote_details_estimate FOREIGN KEY (estimate_id) REFERENCES solar_app.calculator_estimate_details (estimate_id) ON DELETE RESTRICT,
    CONSTRAINT fk_quote_details_status FOREIGN KEY (quote_status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_quote_details_subsidy_slab FOREIGN KEY (subsidy_slab_id) REFERENCES solar_app.ref_subsidy_slabs (subsidy_slab_id) ON DELETE RESTRICT,
    CONSTRAINT fk_quote_details_currency FOREIGN KEY (currency_code) REFERENCES solar_app.ref_currencies (currency_code) ON DELETE RESTRICT
);
COMMENT ON TABLE solar_app.quote_details IS 'Formal quotation header with PDF URL and validity date.';
COMMENT ON COLUMN solar_app.quote_details.quote_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.quote_details.quote_no IS 'Public unique quotation number.';
COMMENT ON COLUMN solar_app.quote_details.lead_id IS 'Parent lead.';
COMMENT ON COLUMN solar_app.quote_details.estimate_id IS 'Calculator estimate copied into this quote.';
COMMENT ON COLUMN solar_app.quote_details.quote_status_ref_data_id IS 'FK to QUOTE_STATUSES.';
COMMENT ON COLUMN solar_app.quote_details.subsidy_slab_id IS 'Source subsidy slab copied from the estimate for traceability.';
COMMENT ON COLUMN solar_app.quote_details.gross_amount IS 'Quoted gross amount.';
COMMENT ON COLUMN solar_app.quote_details.subsidy_amount IS 'Quoted subsidy.';
COMMENT ON COLUMN solar_app.quote_details.net_amount IS 'Quoted net payable (collected offline).';
COMMENT ON COLUMN solar_app.quote_details.currency_code IS 'Currency snapshot for all quote monetary columns.';
COMMENT ON COLUMN solar_app.quote_details.rule_snapshot_json IS 'Immutable snapshot of applied pricing, calculator, and subsidy rule outcomes.';
COMMENT ON COLUMN solar_app.quote_details.pdf_url IS 'Generated branded PDF URL.';
COMMENT ON COLUMN solar_app.quote_details.valid_until IS 'Quote validity date.';
COMMENT ON COLUMN solar_app.quote_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.quote_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.quote_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.quote_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.quote_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

CREATE TABLE solar_app.quote_line_details (
    quote_line_id  BIGINT GENERATED ALWAYS AS IDENTITY,
    quote_id       BIGINT        NOT NULL,
    line_no        INTEGER       NOT NULL,
    component_type VARCHAR(50)   NOT NULL,
    component_desc VARCHAR(255)  NOT NULL,
    tax_classification_code VARCHAR(30),
    quantity       NUMERIC(12,3) NOT NULL DEFAULT 1,
    unit_rate      NUMERIC(12,2) NOT NULL,
    line_amount    NUMERIC(14,2) NOT NULL,
    active_ind     BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by     VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by     VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on     TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on     TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_quote_line_details PRIMARY KEY (quote_line_id),
    CONSTRAINT fk_quote_line_quote FOREIGN KEY (quote_id) REFERENCES solar_app.quote_details (quote_id) ON DELETE CASCADE,
    CONSTRAINT uq_quote_line_no UNIQUE (quote_id, line_no),
    CONSTRAINT chk_quote_line_component CHECK (component_type IN ('PANEL', 'INVERTER', 'STRUCTURE', 'BOS', 'BATTERY', 'OTHER')),
    CONSTRAINT chk_quote_line_qty CHECK (quantity > 0)
);
COMMENT ON TABLE solar_app.quote_line_details IS 'Itemized quote BOM (panels, inverter, structure, BOS, battery). Distinct from the product catalogue.';
COMMENT ON COLUMN solar_app.quote_line_details.quote_line_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.quote_line_details.quote_id IS 'Parent quote header.';
COMMENT ON COLUMN solar_app.quote_line_details.line_no IS 'Line sequence unique per quote.';
COMMENT ON COLUMN solar_app.quote_line_details.component_type IS 'PANEL, INVERTER, STRUCTURE, BOS, BATTERY, or OTHER.';
COMMENT ON COLUMN solar_app.quote_line_details.component_desc IS 'Line description.';
COMMENT ON COLUMN solar_app.quote_line_details.tax_classification_code IS 'Optional country-specific tax classification code snapshot.';
COMMENT ON COLUMN solar_app.quote_line_details.quantity IS 'Quantity (must be > 0).';
COMMENT ON COLUMN solar_app.quote_line_details.unit_rate IS 'Rate per unit.';
COMMENT ON COLUMN solar_app.quote_line_details.line_amount IS 'quantity × rate (or function-computed).';
COMMENT ON COLUMN solar_app.quote_line_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.quote_line_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.quote_line_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.quote_line_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.quote_line_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

CREATE TABLE solar_app.site_visit_details (
    site_visit_id               BIGINT GENERATED ALWAYS AS IDENTITY,
    visit_no                    VARCHAR(30)   NOT NULL,
    visit_purpose_ref_data_id   BIGINT        NOT NULL,
    lead_id                     BIGINT,
    product_enquiry_id          BIGINT,
    customer_id                 BIGINT,
    site_id                     BIGINT,
    order_id                    BIGINT,
    service_request_id          BIGINT,
    service_milestone_id        BIGINT,
    complaint_ticket_id         BIGINT,
    amc_contract_id             BIGINT,
    office_location_id          BIGINT        NOT NULL,
    assigned_to_user_id         BIGINT,
    slot_window_ref_data_id     BIGINT,
    visit_status_ref_data_id    BIGINT        NOT NULL,
    scheduled_on                DATE          NOT NULL,
    started_on                  TIMESTAMPTZ,
    completed_on                TIMESTAMPTZ,
    distance_from_office_km     NUMERIC(8,2),
    visit_charge_slab_id        BIGINT,
    is_chargeable_ind           BOOLEAN       NOT NULL DEFAULT TRUE,
    is_free_entitlement_ind     BOOLEAN       NOT NULL DEFAULT FALSE,
    charge_amount               NUMERIC(12,2) NOT NULL DEFAULT 0,
    currency_code               CHAR(3)       NOT NULL,
    charge_rule_snapshot_json   JSONB         NOT NULL DEFAULT '{}'::jsonb,
    charges_received_ind        BOOLEAN       NOT NULL DEFAULT FALSE,
    charges_received_on         DATE,
    invoice_id                  BIGINT,
    payment_id                  BIGINT,
    remarks                     VARCHAR(500),
    outcome_notes               VARCHAR(1000),
    active_ind                  BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by                  VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by                  VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on                  TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                  TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_site_visit_details PRIMARY KEY (site_visit_id),
    CONSTRAINT uq_site_visit_no UNIQUE (visit_no),
    CONSTRAINT fk_sv_purpose FOREIGN KEY (visit_purpose_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_sv_lead FOREIGN KEY (lead_id) REFERENCES solar_app.lead_details (lead_id) ON DELETE SET NULL,
    CONSTRAINT fk_sv_office FOREIGN KEY (office_location_id) REFERENCES solar_app.ref_office_locations (office_location_id) ON DELETE RESTRICT,
    CONSTRAINT fk_sv_assignee FOREIGN KEY (assigned_to_user_id) REFERENCES solar_app.user_details (user_id) ON DELETE SET NULL,
    CONSTRAINT fk_sv_slot FOREIGN KEY (slot_window_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_sv_status FOREIGN KEY (visit_status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_sv_slab FOREIGN KEY (visit_charge_slab_id) REFERENCES solar_app.ref_visit_charge_slabs (visit_charge_slab_id) ON DELETE RESTRICT,
    CONSTRAINT fk_sv_currency FOREIGN KEY (currency_code) REFERENCES solar_app.ref_currencies (currency_code) ON DELETE RESTRICT,
    CONSTRAINT chk_sv_charge CHECK (charge_amount >= 0),
    CONSTRAINT chk_sv_km CHECK (distance_from_office_km IS NULL OR distance_from_office_km >= 0),
    CONSTRAINT chk_sv_received CHECK (charges_received_ind = FALSE OR charges_received_on IS NOT NULL)
);
COMMENT ON TABLE solar_app.site_visit_details IS 'All field visits: enquiry/feasibility, installation, free or paid servicing, complaints. Charge vs free is decided in functions from AMC/subscription entitlement and distance slabs from the office. Assignee is any app user (technician, sales, or other authorised role). Money collected offline.';
COMMENT ON COLUMN solar_app.site_visit_details.site_visit_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.site_visit_details.visit_no IS 'Public unique visit number generated in fn_create_site_visit_details.';
COMMENT ON COLUMN solar_app.site_visit_details.visit_purpose_ref_data_id IS 'FK to SITE_VISIT_PURPOSES (enquiry, installation, service, complaint, commissioning).';
COMMENT ON COLUMN solar_app.site_visit_details.lead_id IS 'Optional lead for pre-customer feasibility/enquiry visits.';
COMMENT ON COLUMN solar_app.site_visit_details.product_enquiry_id IS 'Optional catalogue enquiry this visit follows up. FK added after product_enquiry_details exists.';
COMMENT ON COLUMN solar_app.site_visit_details.customer_id IS 'Optional customer. FK added after customer_details exists.';
COMMENT ON COLUMN solar_app.site_visit_details.site_id IS 'Optional installed/planned site. FK added after site_details exists.';
COMMENT ON COLUMN solar_app.site_visit_details.order_id IS 'Optional fulfilment order (installation visit). FK added after order_details exists.';
COMMENT ON COLUMN solar_app.site_visit_details.service_request_id IS 'Optional preventive service booking. FK added after service_request_details exists.';
COMMENT ON COLUMN solar_app.site_visit_details.service_milestone_id IS 'Optional free-service milestone consumed by this visit.';
COMMENT ON COLUMN solar_app.site_visit_details.complaint_ticket_id IS 'Optional complaint this visit is for. FK added after complaint_ticket_details exists.';
COMMENT ON COLUMN solar_app.site_visit_details.amc_contract_id IS 'Optional AMC used to mark the visit free. FK added after amc_contract_details exists.';
COMMENT ON COLUMN solar_app.site_visit_details.office_location_id IS 'Office used as distance origin.';
COMMENT ON COLUMN solar_app.site_visit_details.assigned_to_user_id IS 'Assigned technician, sales agent, or other authorised user (user_details). Not limited to technician_details.';
COMMENT ON COLUMN solar_app.site_visit_details.slot_window_ref_data_id IS 'FK to SERVICE_SLOT_WINDOWS (morning/afternoon).';
COMMENT ON COLUMN solar_app.site_visit_details.visit_status_ref_data_id IS 'FK to SITE_VISIT_STATUSES (scheduled, assigned, in progress, completed, cancelled, no-show).';
COMMENT ON COLUMN solar_app.site_visit_details.scheduled_on IS 'Planned visit date.';
COMMENT ON COLUMN solar_app.site_visit_details.started_on IS 'When the assignee started on-site work.';
COMMENT ON COLUMN solar_app.site_visit_details.completed_on IS 'When the visit was marked done.';
COMMENT ON COLUMN solar_app.site_visit_details.distance_from_office_km IS 'Haversine km from office to site/pincode, computed in functions.';
COMMENT ON COLUMN solar_app.site_visit_details.visit_charge_slab_id IS 'Distance slab used to price this visit.';
COMMENT ON COLUMN solar_app.site_visit_details.is_chargeable_ind IS 'FALSE when a free servicing entitlement or explicitly free slab applies.';
COMMENT ON COLUMN solar_app.site_visit_details.is_free_entitlement_ind IS 'TRUE if this visit consumed an AMC or free-milestone credit.';
COMMENT ON COLUMN solar_app.site_visit_details.charge_amount IS 'Visit fee to collect offline (0 when free).';
COMMENT ON COLUMN solar_app.site_visit_details.currency_code IS 'Currency snapshot for charge_amount.';
COMMENT ON COLUMN solar_app.site_visit_details.charge_rule_snapshot_json IS 'Immutable snapshot of distance, purpose, slab, pricing precedence, entitlement, and applied rule values.';
COMMENT ON COLUMN solar_app.site_visit_details.charges_received_ind IS 'TRUE after admin records that the visit fee was collected offline.';
COMMENT ON COLUMN solar_app.site_visit_details.charges_received_on IS 'Date the visit fee was collected.';
COMMENT ON COLUMN solar_app.site_visit_details.invoice_id IS 'Optional offline bill for this visit fee. FK added after invoice_details exists.';
COMMENT ON COLUMN solar_app.site_visit_details.payment_id IS 'Optional offline receipt. FK added after payment_details exists.';
COMMENT ON COLUMN solar_app.site_visit_details.remarks IS 'Planning notes.';
COMMENT ON COLUMN solar_app.site_visit_details.outcome_notes IS 'What was done on site.';
COMMENT ON COLUMN solar_app.site_visit_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.site_visit_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.site_visit_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.site_visit_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.site_visit_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_sv_assignee_sched ON solar_app.site_visit_details (assigned_to_user_id, scheduled_on) WHERE active_ind = TRUE;
CREATE INDEX idx_sv_status ON solar_app.site_visit_details (visit_status_ref_data_id, scheduled_on);

-- =====================================================================
-- MODULE 11 — Product catalogue & enquiry (NEW)
-- =====================================================================

CREATE TABLE solar_app.product_details (
    product_id             BIGINT GENERATED ALWAYS AS IDENTITY,
    product_code           VARCHAR(40)   NOT NULL,
    product_name           VARCHAR(200)  NOT NULL,
    category_ref_data_id   BIGINT        NOT NULL,
    short_description      VARCHAR(500),
    long_description       TEXT,
    specs_json             JSONB         NOT NULL DEFAULT '{}'::jsonb,
    list_price             NUMERIC(14,2) NOT NULL,
    currency_code          CHAR(3)       NOT NULL,
    tax_classification_code VARCHAR(30),
    thumbnail_url          VARCHAR(500),
    is_published           BOOLEAN       NOT NULL DEFAULT FALSE,
    published_on           TIMESTAMPTZ,
    sort_order             INTEGER       NOT NULL DEFAULT 0,
    active_ind             BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by             VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by             VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on             TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on             TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_product_details PRIMARY KEY (product_id),
    CONSTRAINT fk_product_details_category FOREIGN KEY (category_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_product_details_currency FOREIGN KEY (currency_code) REFERENCES solar_app.ref_currencies (currency_code) ON DELETE RESTRICT,
    CONSTRAINT chk_product_details_price CHECK (list_price >= 0)
);
COMMENT ON TABLE solar_app.product_details IS 'Admin-maintained catalogue of sellable and related products shown to registered users when published.';
COMMENT ON COLUMN solar_app.product_details.product_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.product_details.product_code IS 'Business SKU; unique among active catalogue rows.';
COMMENT ON COLUMN solar_app.product_details.product_name IS 'Catalogue card and detail title.';
COMMENT ON COLUMN solar_app.product_details.category_ref_data_id IS 'FK to PRODUCT_CATEGORIES.';
COMMENT ON COLUMN solar_app.product_details.short_description IS 'List-card blurb.';
COMMENT ON COLUMN solar_app.product_details.long_description IS 'Product detail body.';
COMMENT ON COLUMN solar_app.product_details.specs_json IS 'Flexible specification table (wattage, warranty years, …).';
COMMENT ON COLUMN solar_app.product_details.list_price IS 'Indicative list price; formal quote is a separate object.';
COMMENT ON COLUMN solar_app.product_details.currency_code IS 'ISO currency for list_price.';
COMMENT ON COLUMN solar_app.product_details.tax_classification_code IS 'Optional country-specific product tax classification.';
COMMENT ON COLUMN solar_app.product_details.thumbnail_url IS 'List thumbnail URL.';
COMMENT ON COLUMN solar_app.product_details.is_published IS 'TRUE = visible to registered users; FALSE = admin draft. Publish enqueues NTF_CATALOGUE_NEW.';
COMMENT ON COLUMN solar_app.product_details.published_on IS 'When the product was last published.';
COMMENT ON COLUMN solar_app.product_details.sort_order IS 'Featured/list order (lower first).';
COMMENT ON COLUMN solar_app.product_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.product_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.product_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.product_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.product_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE UNIQUE INDEX uq_product_details_code_active ON solar_app.product_details (product_code) WHERE active_ind = TRUE;
CREATE INDEX idx_product_details_published ON solar_app.product_details (is_published, active_ind, sort_order);
CREATE INDEX idx_product_details_category ON solar_app.product_details (category_ref_data_id);

CREATE TABLE solar_app.product_media_details (
    product_media_id BIGINT GENERATED ALWAYS AS IDENTITY,
    product_id       BIGINT       NOT NULL,
    media_type       VARCHAR(20)  NOT NULL,
    file_url         VARCHAR(500) NOT NULL,
    caption          VARCHAR(255),
    sort_order       INTEGER      NOT NULL DEFAULT 0,
    active_ind       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by       VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by       VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on       TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on       TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_product_media_details PRIMARY KEY (product_media_id),
    CONSTRAINT fk_product_media_product FOREIGN KEY (product_id) REFERENCES solar_app.product_details (product_id) ON DELETE CASCADE,
    CONSTRAINT chk_product_media_type CHECK (media_type IN ('PHOTO', 'VIDEO', 'DOCUMENT'))
);
COMMENT ON TABLE solar_app.product_media_details IS 'Product gallery photos, videos, and spec-sheet documents.';
COMMENT ON COLUMN solar_app.product_media_details.product_media_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.product_media_details.product_id IS 'Parent catalogue product.';
COMMENT ON COLUMN solar_app.product_media_details.media_type IS 'PHOTO, VIDEO, or DOCUMENT.';
COMMENT ON COLUMN solar_app.product_media_details.file_url IS 'Object-storage URL.';
COMMENT ON COLUMN solar_app.product_media_details.caption IS 'Optional alt text or caption.';
COMMENT ON COLUMN solar_app.product_media_details.sort_order IS 'Gallery order.';
COMMENT ON COLUMN solar_app.product_media_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.product_media_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.product_media_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.product_media_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.product_media_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_product_media_product ON solar_app.product_media_details (product_id, sort_order);

CREATE TABLE solar_app.product_enquiry_details (
    product_enquiry_id       BIGINT GENERATED ALWAYS AS IDENTITY,
    enquiry_no               VARCHAR(30)   NOT NULL,
    product_id               BIGINT        NOT NULL,
    user_id                  BIGINT        NOT NULL,
    customer_id              BIGINT,
    pincode_id               BIGINT,
    message_text             VARCHAR(2000) NOT NULL,
    preferred_contact_window VARCHAR(50),
    status_ref_data_id       BIGINT        NOT NULL,
    assigned_agent_user_id   BIGINT,
    admin_remarks            VARCHAR(500),
    converted_lead_id        BIGINT,
    converted_on             TIMESTAMPTZ,
    active_ind               BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by               VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by               VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_product_enquiry_details PRIMARY KEY (product_enquiry_id),
    CONSTRAINT uq_product_enquiry_no UNIQUE (enquiry_no),
    CONSTRAINT fk_enq_product FOREIGN KEY (product_id) REFERENCES solar_app.product_details (product_id) ON DELETE RESTRICT,
    CONSTRAINT fk_enq_user FOREIGN KEY (user_id) REFERENCES solar_app.user_details (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_enq_pincode FOREIGN KEY (pincode_id) REFERENCES solar_app.ref_pincodes (pincode_id) ON DELETE RESTRICT,
    CONSTRAINT fk_enq_status FOREIGN KEY (status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_enq_agent FOREIGN KEY (assigned_agent_user_id) REFERENCES solar_app.user_details (user_id) ON DELETE SET NULL,
    CONSTRAINT fk_enq_lead FOREIGN KEY (converted_lead_id) REFERENCES solar_app.lead_details (lead_id) ON DELETE SET NULL
);
COMMENT ON TABLE solar_app.product_enquiry_details IS 'Registered-user enquiry against one catalogue product; may convert to a lead without deleting history.';
COMMENT ON COLUMN solar_app.product_enquiry_details.product_enquiry_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.product_enquiry_details.enquiry_no IS 'Public tracking number generated in fn_create_product_enquiry_details.';
COMMENT ON COLUMN solar_app.product_enquiry_details.product_id IS 'Catalogue product of interest.';
COMMENT ON COLUMN solar_app.product_enquiry_details.user_id IS 'Logged-in registered user who submitted the enquiry.';
COMMENT ON COLUMN solar_app.product_enquiry_details.customer_id IS 'Set when the user already has a customer_details row.';
COMMENT ON COLUMN solar_app.product_enquiry_details.pincode_id IS 'Optional installation postal code.';
COMMENT ON COLUMN solar_app.product_enquiry_details.message_text IS 'Requirement or questions from the user.';
COMMENT ON COLUMN solar_app.product_enquiry_details.preferred_contact_window IS 'Preferred callback window.';
COMMENT ON COLUMN solar_app.product_enquiry_details.status_ref_data_id IS 'FK to PRODUCT_ENQUIRY_STATUSES.';
COMMENT ON COLUMN solar_app.product_enquiry_details.assigned_agent_user_id IS 'Sales follow-up owner.';
COMMENT ON COLUMN solar_app.product_enquiry_details.admin_remarks IS 'Internal notes.';
COMMENT ON COLUMN solar_app.product_enquiry_details.converted_lead_id IS 'Lead created or linked on conversion; enquiry row is retained.';
COMMENT ON COLUMN solar_app.product_enquiry_details.converted_on IS 'Conversion timestamp.';
COMMENT ON COLUMN solar_app.product_enquiry_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.product_enquiry_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.product_enquiry_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.product_enquiry_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.product_enquiry_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_enq_product ON solar_app.product_enquiry_details (product_id, created_on DESC);
CREATE INDEX idx_enq_user ON solar_app.product_enquiry_details (user_id, created_on DESC);
CREATE INDEX idx_enq_status ON solar_app.product_enquiry_details (status_ref_data_id, active_ind);

-- =====================================================================
-- MODULE 3 — Customer, site, KYC
-- =====================================================================

CREATE TABLE solar_app.customer_details (
    customer_id           BIGINT GENERATED ALWAYS AS IDENTITY,
    user_id               BIGINT       NOT NULL,
    customer_code         VARCHAR(30)  NOT NULL,
    billing_name          VARCHAR(150),
    tax_registration_no   VARCHAR(50),
    billing_address_line1 VARCHAR(255),
    billing_address_line2 VARCHAR(255),
    billing_pincode_id    BIGINT,
    originating_lead_id   BIGINT,
    active_ind            BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by            VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by            VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on            TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on            TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_customer_details PRIMARY KEY (customer_id),
    CONSTRAINT uq_customer_details_user UNIQUE (user_id),
    CONSTRAINT uq_customer_details_code UNIQUE (customer_code),
    CONSTRAINT fk_customer_user FOREIGN KEY (user_id) REFERENCES solar_app.user_details (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_pincode FOREIGN KEY (billing_pincode_id) REFERENCES solar_app.ref_pincodes (pincode_id) ON DELETE RESTRICT,
    CONSTRAINT fk_customer_lead FOREIGN KEY (originating_lead_id) REFERENCES solar_app.lead_details (lead_id) ON DELETE SET NULL
);
COMMENT ON TABLE solar_app.customer_details IS 'Legal/billing party with optional country-specific tax registration, linked 1:1 to a user and separate from physical sites.';
COMMENT ON COLUMN solar_app.customer_details.customer_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.customer_details.user_id IS '1:1 FK to the login user for this legal/billing party.';
COMMENT ON COLUMN solar_app.customer_details.customer_code IS 'Business customer code unique in the register.';
COMMENT ON COLUMN solar_app.customer_details.billing_name IS 'Name printed on offline bills.';
COMMENT ON COLUMN solar_app.customer_details.tax_registration_no IS 'Optional country-specific tax registration number validated from country metadata.';
COMMENT ON COLUMN solar_app.customer_details.billing_address_line1 IS 'Billing address line 1.';
COMMENT ON COLUMN solar_app.customer_details.billing_address_line2 IS 'Billing address line 2.';
COMMENT ON COLUMN solar_app.customer_details.billing_pincode_id IS 'FK to billing postal code.';
COMMENT ON COLUMN solar_app.customer_details.originating_lead_id IS 'Lead this customer was converted from, if Path A.';
COMMENT ON COLUMN solar_app.customer_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.customer_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.customer_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.customer_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.customer_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

ALTER TABLE solar_app.product_enquiry_details
    ADD CONSTRAINT fk_enq_customer
        FOREIGN KEY (customer_id) REFERENCES solar_app.customer_details (customer_id) ON DELETE SET NULL;
ALTER TABLE solar_app.lead_details
    ADD CONSTRAINT fk_lead_converted_customer
        FOREIGN KEY (converted_customer_id) REFERENCES solar_app.customer_details (customer_id) ON DELETE SET NULL;

CREATE TABLE solar_app.site_details (
    site_id                         BIGINT GENERATED ALWAYS AS IDENTITY,
    customer_id                     BIGINT        NOT NULL,
    site_name                       VARCHAR(150)  NOT NULL,
    address_line1                   VARCHAR(255)  NOT NULL,
    address_line2                   VARCHAR(255),
    pincode_id                      BIGINT,
    city_id                         BIGINT,
    district_id                     BIGINT,
    state_id                        BIGINT,
    latitude                        NUMERIC(10,7),
    longitude                       NUMERIC(10,7),
    discom_id                       BIGINT,
    consumer_number                 VARCHAR(50),
    meter_number                    VARCHAR(50),
    sanctioned_load_kw              NUMERIC(8,3),
    connection_type_ref_data_id     BIGINT,
    installation_status_ref_data_id BIGINT,
    commissioning_on                DATE,
    order_id                        BIGINT,
    active_ind                      BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by                      VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by                      VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on                      TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                      TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_site_details PRIMARY KEY (site_id),
    CONSTRAINT fk_site_customer FOREIGN KEY (customer_id) REFERENCES solar_app.customer_details (customer_id) ON DELETE RESTRICT,
    CONSTRAINT fk_site_pincode FOREIGN KEY (pincode_id) REFERENCES solar_app.ref_pincodes (pincode_id) ON DELETE RESTRICT,
    CONSTRAINT fk_site_city FOREIGN KEY (city_id) REFERENCES solar_app.ref_cities (city_id) ON DELETE RESTRICT,
    CONSTRAINT fk_site_district FOREIGN KEY (district_id) REFERENCES solar_app.ref_districts (district_id) ON DELETE RESTRICT,
    CONSTRAINT fk_site_state FOREIGN KEY (state_id) REFERENCES solar_app.ref_states (state_id) ON DELETE RESTRICT,
    CONSTRAINT fk_site_discom FOREIGN KEY (discom_id) REFERENCES solar_app.ref_discoms (discom_id) ON DELETE RESTRICT,
    CONSTRAINT fk_site_conn FOREIGN KEY (connection_type_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_site_inst_status FOREIGN KEY (installation_status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT chk_site_lat CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT chk_site_lon CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    CONSTRAINT chk_site_load CHECK (sanctioned_load_kw IS NULL OR sanctioned_load_kw >= 0)
);
COMMENT ON TABLE solar_app.site_details IS 'Installed or planned solar site (address, DISCOM account, GPS, commissioning). Multi-property selector parent.';
COMMENT ON COLUMN solar_app.site_details.site_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.site_details.customer_id IS 'Owner customer of this installation site.';
COMMENT ON COLUMN solar_app.site_details.site_name IS 'Selector label such as Home - 5kW.';
COMMENT ON COLUMN solar_app.site_details.address_line1 IS 'Site street address line 1.';
COMMENT ON COLUMN solar_app.site_details.address_line2 IS 'Site street address line 2.';
COMMENT ON COLUMN solar_app.site_details.pincode_id IS 'FK to site postal code.';
COMMENT ON COLUMN solar_app.site_details.city_id IS 'FK to city.';
COMMENT ON COLUMN solar_app.site_details.district_id IS 'FK to district.';
COMMENT ON COLUMN solar_app.site_details.state_id IS 'FK to state.';
COMMENT ON COLUMN solar_app.site_details.latitude IS 'GPS latitude for technician routing.';
COMMENT ON COLUMN solar_app.site_details.longitude IS 'GPS longitude for technician routing.';
COMMENT ON COLUMN solar_app.site_details.discom_id IS 'Electricity provider for this connection.';
COMMENT ON COLUMN solar_app.site_details.consumer_number IS 'DISCOM consumer account number.';
COMMENT ON COLUMN solar_app.site_details.meter_number IS 'Electricity meter number.';
COMMENT ON COLUMN solar_app.site_details.sanctioned_load_kw IS 'Sanctioned load in kW from the bill/KYC.';
COMMENT ON COLUMN solar_app.site_details.connection_type_ref_data_id IS 'FK to CONNECTION_TYPES.';
COMMENT ON COLUMN solar_app.site_details.installation_status_ref_data_id IS 'FK to INSTALLATION_STATUSES.';
COMMENT ON COLUMN solar_app.site_details.commissioning_on IS 'Commissioning date; starts the configured free-service milestone schedule.';
COMMENT ON COLUMN solar_app.site_details.order_id IS 'Order fulfilled at this site (Path A) or recorded at Path B registration. FK added after order_details exists.';
COMMENT ON COLUMN solar_app.site_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.site_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.site_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.site_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.site_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

CREATE TABLE solar_app.user_site_access_details (
    user_site_access_id      BIGINT GENERATED ALWAYS AS IDENTITY,
    user_id                  BIGINT  NOT NULL,
    site_id                  BIGINT  NOT NULL,
    is_default               BOOLEAN NOT NULL DEFAULT FALSE,
    access_role_ref_data_id  BIGINT,
    active_ind               BOOLEAN NOT NULL DEFAULT TRUE,
    created_by               VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    updated_by               VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    created_on               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_user_site_access PRIMARY KEY (user_site_access_id),
    CONSTRAINT fk_usa_user FOREIGN KEY (user_id) REFERENCES solar_app.user_details (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_usa_site FOREIGN KEY (site_id) REFERENCES solar_app.site_details (site_id) ON DELETE CASCADE,
    CONSTRAINT fk_usa_role FOREIGN KEY (access_role_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT uq_usa_user_site UNIQUE (user_id, site_id)
);
COMMENT ON TABLE solar_app.user_site_access_details IS 'Which users may switch into which sites (owner/family/operator) including default site.';
COMMENT ON COLUMN solar_app.user_site_access_details.user_site_access_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.user_site_access_details.user_id IS 'User who may switch into the site.';
COMMENT ON COLUMN solar_app.user_site_access_details.site_id IS 'Site being granted.';
COMMENT ON COLUMN solar_app.user_site_access_details.is_default IS 'TRUE is the last-selected / default site for the user (one per user via partial unique index).';
COMMENT ON COLUMN solar_app.user_site_access_details.access_role_ref_data_id IS 'FK to SITE_ACCESS_ROLES (owner, family, operator).';
COMMENT ON COLUMN solar_app.user_site_access_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.user_site_access_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.user_site_access_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.user_site_access_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.user_site_access_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

CREATE TABLE solar_app.kyc_document_details (
    kyc_document_id                  BIGINT GENERATED ALWAYS AS IDENTITY,
    customer_id                      BIGINT       NOT NULL,
    site_id                          BIGINT,
    document_type_ref_data_id        BIGINT       NOT NULL,
    file_url                         VARCHAR(500) NOT NULL,
    mime_type                        VARCHAR(100),
    file_size_bytes                  INTEGER      NOT NULL,
    verification_status_ref_data_id  BIGINT       NOT NULL,
    verified_by_user_id              BIGINT,
    rejection_comment                VARCHAR(500),
    active_ind                       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by                       VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by                       VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on                       TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                       TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_kyc_document PRIMARY KEY (kyc_document_id),
    CONSTRAINT fk_kyc_customer FOREIGN KEY (customer_id) REFERENCES solar_app.customer_details (customer_id) ON DELETE RESTRICT,
    CONSTRAINT fk_kyc_site FOREIGN KEY (site_id) REFERENCES solar_app.site_details (site_id) ON DELETE SET NULL,
    CONSTRAINT fk_kyc_doc_type FOREIGN KEY (document_type_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_kyc_status FOREIGN KEY (verification_status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_kyc_verifier FOREIGN KEY (verified_by_user_id) REFERENCES solar_app.user_details (user_id) ON DELETE SET NULL,
    CONSTRAINT chk_kyc_size CHECK (file_size_bytes > 0)
);
COMMENT ON TABLE solar_app.kyc_document_details IS 'KYC and DISCOM document uploads with verification status. Reject comment is mandatory in functions when rejected.';
COMMENT ON COLUMN solar_app.kyc_document_details.kyc_document_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.kyc_document_details.customer_id IS 'Customer who owns the document.';
COMMENT ON COLUMN solar_app.kyc_document_details.site_id IS 'Optional site this document belongs to (roof photos, bill).';
COMMENT ON COLUMN solar_app.kyc_document_details.document_type_ref_data_id IS 'FK to DOCUMENT_TYPES (Aadhaar, bill, NOC, photos).';
COMMENT ON COLUMN solar_app.kyc_document_details.file_url IS 'Object-storage URL of the upload.';
COMMENT ON COLUMN solar_app.kyc_document_details.mime_type IS 'MIME type of the file.';
COMMENT ON COLUMN solar_app.kyc_document_details.file_size_bytes IS 'Size in bytes; the effective upload limit is resolved from business parameters.';
COMMENT ON COLUMN solar_app.kyc_document_details.verification_status_ref_data_id IS 'FK to DOCUMENT_VERIFICATION_STATUSES.';
COMMENT ON COLUMN solar_app.kyc_document_details.verified_by_user_id IS 'Admin who approved or rejected.';
COMMENT ON COLUMN solar_app.kyc_document_details.rejection_comment IS 'Mandatory in functions when status is Action Required / Rejected.';
COMMENT ON COLUMN solar_app.kyc_document_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.kyc_document_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.kyc_document_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.kyc_document_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.kyc_document_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

-- =====================================================================
-- MODULE 4 — Equipment & warranty
-- =====================================================================

CREATE TABLE solar_app.equipment_details (
    equipment_id              BIGINT GENERATED ALWAYS AS IDENTITY,
    site_id                   BIGINT        NOT NULL,
    product_id                BIGINT,
    equipment_type_ref_data_id BIGINT       NOT NULL,
    brand_ref_data_id         BIGINT,
    model_name                VARCHAR(150),
    serial_no                 VARCHAR(80),
    barcode                   VARCHAR(80),
    quantity                  NUMERIC(12,3) NOT NULL DEFAULT 1,
    panel_wattage             NUMERIC(10,3),
    inverter_capacity_kw      NUMERIC(8,3),
    phase_type_ref_data_id    BIGINT,
    monitoring_dongle_id      VARCHAR(80),
    structure_type_ref_data_id BIGINT,
    battery_capacity_ah       NUMERIC(10,2),
    extra_json                JSONB         NOT NULL DEFAULT '{}'::jsonb,
    commissioned_on           DATE,
    active_ind                BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by                VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by                VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on                TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_equipment_details PRIMARY KEY (equipment_id),
    CONSTRAINT fk_eq_site FOREIGN KEY (site_id) REFERENCES solar_app.site_details (site_id) ON DELETE RESTRICT,
    CONSTRAINT fk_eq_product FOREIGN KEY (product_id) REFERENCES solar_app.product_details (product_id) ON DELETE SET NULL,
    CONSTRAINT fk_eq_type FOREIGN KEY (equipment_type_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_eq_brand FOREIGN KEY (brand_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_eq_phase FOREIGN KEY (phase_type_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_eq_structure FOREIGN KEY (structure_type_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT chk_eq_qty CHECK (quantity > 0)
);
COMMENT ON TABLE solar_app.equipment_details IS 'Installed asset register (panel/inverter/structure/battery) at a site, optionally linked to a catalogue product.';
COMMENT ON COLUMN solar_app.equipment_details.equipment_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.equipment_details.site_id IS 'Site where this asset is installed.';
COMMENT ON COLUMN solar_app.equipment_details.product_id IS 'Optional catalogue SKU this asset corresponds to.';
COMMENT ON COLUMN solar_app.equipment_details.equipment_type_ref_data_id IS 'FK to EQUIPMENT_TYPES (panel, inverter, structure, battery).';
COMMENT ON COLUMN solar_app.equipment_details.brand_ref_data_id IS 'FK to EQUIPMENT_BRANDS.';
COMMENT ON COLUMN solar_app.equipment_details.model_name IS 'Manufacturer model name.';
COMMENT ON COLUMN solar_app.equipment_details.serial_no IS 'Serial number; unique among active rows when present.';
COMMENT ON COLUMN solar_app.equipment_details.barcode IS 'Barcode or QR value scanned in the field.';
COMMENT ON COLUMN solar_app.equipment_details.quantity IS 'Count of identical units on this row (typical for panels).';
COMMENT ON COLUMN solar_app.equipment_details.panel_wattage IS 'Wattage per panel when type is panel.';
COMMENT ON COLUMN solar_app.equipment_details.inverter_capacity_kw IS 'Inverter capacity when type is inverter.';
COMMENT ON COLUMN solar_app.equipment_details.phase_type_ref_data_id IS 'FK to PHASE_TYPES (single / three phase).';
COMMENT ON COLUMN solar_app.equipment_details.monitoring_dongle_id IS 'Wi-Fi / dongle id for inverter monitoring (no telemetry table in v1).';
COMMENT ON COLUMN solar_app.equipment_details.structure_type_ref_data_id IS 'FK to STRUCTURE_TYPES.';
COMMENT ON COLUMN solar_app.equipment_details.battery_capacity_ah IS 'Battery bank Ah when type is battery.';
COMMENT ON COLUMN solar_app.equipment_details.extra_json IS 'Rare type-specific attributes that do not need dedicated columns.';
COMMENT ON COLUMN solar_app.equipment_details.commissioned_on IS 'Asset commissioning date if different from site.';
COMMENT ON COLUMN solar_app.equipment_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.equipment_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.equipment_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.equipment_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.equipment_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

CREATE TABLE solar_app.warranty_details (
    warranty_id               BIGINT GENERATED ALWAYS AS IDENTITY,
    equipment_id              BIGINT      NOT NULL,
    warranty_type_ref_data_id BIGINT      NOT NULL,
    start_on                  DATE        NOT NULL,
    end_on                    DATE        NOT NULL,
    terms_summary             VARCHAR(500),
    document_url              VARCHAR(500),
    active_ind                BOOLEAN     NOT NULL DEFAULT TRUE,
    created_by                VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    updated_by                VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    created_on                TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_warranty_details PRIMARY KEY (warranty_id),
    CONSTRAINT fk_warr_eq FOREIGN KEY (equipment_id) REFERENCES solar_app.equipment_details (equipment_id) ON DELETE CASCADE,
    CONSTRAINT fk_warr_type FOREIGN KEY (warranty_type_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT chk_warr_dates CHECK (end_on >= start_on)
);
COMMENT ON TABLE solar_app.warranty_details IS 'Warranty card vault for an equipment row (type, dates, document URL).';
COMMENT ON COLUMN solar_app.warranty_details.warranty_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.warranty_details.equipment_id IS 'Parent installed asset.';
COMMENT ON COLUMN solar_app.warranty_details.warranty_type_ref_data_id IS 'FK to WARRANTY_TYPES (panel performance, inverter, …).';
COMMENT ON COLUMN solar_app.warranty_details.start_on IS 'Warranty start date.';
COMMENT ON COLUMN solar_app.warranty_details.end_on IS 'Warranty end date.';
COMMENT ON COLUMN solar_app.warranty_details.terms_summary IS 'Short terms text.';
COMMENT ON COLUMN solar_app.warranty_details.document_url IS 'Scanned warranty card URL.';
COMMENT ON COLUMN solar_app.warranty_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.warranty_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.warranty_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.warranty_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.warranty_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

-- =====================================================================
-- MODULE 5 — AMC, milestones, service requests
-- =====================================================================

CREATE TABLE solar_app.amc_contract_details (
    amc_contract_id BIGINT GENERATED ALWAYS AS IDENTITY,
    site_id         BIGINT        NOT NULL,
    amc_plan_id     BIGINT        NOT NULL,
    order_id        BIGINT,
    product_id      BIGINT,
    invoice_id      BIGINT,
    start_on        DATE          NOT NULL,
    expiry_on       DATE          NOT NULL,
    contract_status VARCHAR(20)   NOT NULL DEFAULT 'ACTIVE',
    sold_amount     NUMERIC(12,2) NOT NULL DEFAULT 0,
    currency_code   CHAR(3)       NOT NULL,
    plan_snapshot_json JSONB      NOT NULL DEFAULT '{}'::jsonb,
    active_ind      BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by      VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by      VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on      TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on      TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_amc_contract PRIMARY KEY (amc_contract_id),
    CONSTRAINT fk_amc_site FOREIGN KEY (site_id) REFERENCES solar_app.site_details (site_id) ON DELETE RESTRICT,
    CONSTRAINT fk_amc_plan FOREIGN KEY (amc_plan_id) REFERENCES solar_app.ref_amc_plans (amc_plan_id) ON DELETE RESTRICT,
    CONSTRAINT fk_amc_product FOREIGN KEY (product_id) REFERENCES solar_app.product_details (product_id) ON DELETE SET NULL,
    CONSTRAINT fk_amc_currency FOREIGN KEY (currency_code) REFERENCES solar_app.ref_currencies (currency_code) ON DELETE RESTRICT,
    CONSTRAINT chk_amc_status CHECK (contract_status IN ('ACTIVE', 'EXPIRED', 'CANCELLED')),
    CONSTRAINT chk_amc_dates CHECK (expiry_on >= start_on),
    CONSTRAINT chk_amc_amount CHECK (sold_amount >= 0)
);
COMMENT ON TABLE solar_app.amc_contract_details IS 'Sold AMC contract instance for a site. Expiry drives a renewal request, not in-app payment.';
COMMENT ON COLUMN solar_app.amc_contract_details.amc_contract_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.amc_contract_details.site_id IS 'Site covered by this contract.';
COMMENT ON COLUMN solar_app.amc_contract_details.amc_plan_id IS 'FK to ref_amc_plans catalogue.';
COMMENT ON COLUMN solar_app.amc_contract_details.order_id IS 'Optional order this AMC was sold with.';
COMMENT ON COLUMN solar_app.amc_contract_details.product_id IS 'Optional catalogue AMC/product SKU.';
COMMENT ON COLUMN solar_app.amc_contract_details.invoice_id IS 'Optional offline bill for this contract; FK added after invoice_details exists.';
COMMENT ON COLUMN solar_app.amc_contract_details.start_on IS 'Contract start date.';
COMMENT ON COLUMN solar_app.amc_contract_details.expiry_on IS 'Contract end date; drives AMC expiry notifications.';
COMMENT ON COLUMN solar_app.amc_contract_details.contract_status IS 'ACTIVE, EXPIRED, or CANCELLED (CHECK, not ref_data, to avoid seed-order coupling).';
COMMENT ON COLUMN solar_app.amc_contract_details.sold_amount IS 'Contract value recorded for reference; money still collected offline.';
COMMENT ON COLUMN solar_app.amc_contract_details.currency_code IS 'Currency snapshot for sold_amount.';
COMMENT ON COLUMN solar_app.amc_contract_details.plan_snapshot_json IS 'Immutable snapshot of plan duration, price, included services, visit count, radius, and other sold terms.';
COMMENT ON COLUMN solar_app.amc_contract_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.amc_contract_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.amc_contract_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.amc_contract_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.amc_contract_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_amc_site_status_expiry ON solar_app.amc_contract_details (site_id, contract_status, expiry_on) WHERE active_ind = TRUE;

CREATE TABLE solar_app.service_milestone_details (
    service_milestone_id  BIGINT GENERATED ALWAYS AS IDENTITY,
    site_id               BIGINT  NOT NULL,
    milestone_no          INTEGER NOT NULL,
    due_on                DATE    NOT NULL,
    claim_window_end_on   DATE    NOT NULL,
    status_ref_data_id    BIGINT  NOT NULL,
    service_request_id    BIGINT,
    active_ind            BOOLEAN NOT NULL DEFAULT TRUE,
    created_by            VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    updated_by            VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    created_on            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_service_milestone PRIMARY KEY (service_milestone_id),
    CONSTRAINT fk_ms_site FOREIGN KEY (site_id) REFERENCES solar_app.site_details (site_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ms_status FOREIGN KEY (status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT chk_ms_no CHECK (milestone_no >= 1),
    CONSTRAINT uq_ms_site_no UNIQUE (site_id, milestone_no)
);
COMMENT ON TABLE solar_app.service_milestone_details IS 'Configured free-service milestones per site after commissioning; count and claim window come from the applied business-rule version.';
COMMENT ON COLUMN solar_app.service_milestone_details.service_milestone_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.service_milestone_details.site_id IS 'Site whose free-service clock this milestone belongs to.';
COMMENT ON COLUMN solar_app.service_milestone_details.milestone_no IS 'Sequence of free servicing visits for the site. How many are created is configurable (FREE_SVC_VISIT_COUNT / AMC free_visit_count), not hard-coded to 4.';
COMMENT ON COLUMN solar_app.service_milestone_details.due_on IS 'Planned visit date.';
COMMENT ON COLUMN solar_app.service_milestone_details.claim_window_end_on IS 'Final claim date calculated from the effective claim-window parameter and stored as a historical outcome.';
COMMENT ON COLUMN solar_app.service_milestone_details.status_ref_data_id IS 'FK to MILESTONE_STATUSES.';
COMMENT ON COLUMN solar_app.service_milestone_details.service_request_id IS 'Linked booking when the visit is claimed; deferred FK.';
COMMENT ON COLUMN solar_app.service_milestone_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.service_milestone_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.service_milestone_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.service_milestone_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.service_milestone_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_ms_status_due ON solar_app.service_milestone_details (status_ref_data_id, due_on) WHERE active_ind = TRUE;

CREATE TABLE solar_app.service_request_details (
    service_request_id        BIGINT GENERATED ALWAYS AS IDENTITY,
    service_request_no        VARCHAR(30)  NOT NULL,
    site_id                   BIGINT       NOT NULL,
    customer_id               BIGINT       NOT NULL,
    technician_id             BIGINT,
    service_type_ref_data_id  BIGINT       NOT NULL,
    slot_window_ref_data_id   BIGINT,
    status_ref_data_id        BIGINT       NOT NULL,
    preferred_on              DATE,
    milestone_id              BIGINT,
    amc_contract_id           BIGINT,
    order_id                  BIGINT,
    product_id                BIGINT,
    arrival_status            VARCHAR(30),
    completion_notes          VARCHAR(1000),
    report_url                VARCHAR(500),
    active_ind                BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by                VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by                VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on                TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_service_request PRIMARY KEY (service_request_id),
    CONSTRAINT uq_service_request_no UNIQUE (service_request_no),
    CONSTRAINT fk_sr_site FOREIGN KEY (site_id) REFERENCES solar_app.site_details (site_id) ON DELETE RESTRICT,
    CONSTRAINT fk_sr_customer FOREIGN KEY (customer_id) REFERENCES solar_app.customer_details (customer_id) ON DELETE RESTRICT,
    CONSTRAINT fk_sr_tech FOREIGN KEY (technician_id) REFERENCES solar_app.technician_details (technician_id) ON DELETE SET NULL,
    CONSTRAINT fk_sr_type FOREIGN KEY (service_type_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_sr_slot FOREIGN KEY (slot_window_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_sr_status FOREIGN KEY (status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_sr_milestone FOREIGN KEY (milestone_id) REFERENCES solar_app.service_milestone_details (service_milestone_id) ON DELETE SET NULL,
    CONSTRAINT fk_sr_amc FOREIGN KEY (amc_contract_id) REFERENCES solar_app.amc_contract_details (amc_contract_id) ON DELETE SET NULL,
    CONSTRAINT fk_sr_product FOREIGN KEY (product_id) REFERENCES solar_app.product_details (product_id) ON DELETE SET NULL
);
COMMENT ON TABLE solar_app.service_request_details IS 'Preventive service booking or admin-entered historical visit (Path B), linked to site/product/order when known.';
COMMENT ON COLUMN solar_app.service_request_details.service_request_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.service_request_details.service_request_no IS 'Public unique service request number.';
COMMENT ON COLUMN solar_app.service_request_details.site_id IS 'Site to be serviced.';
COMMENT ON COLUMN solar_app.service_request_details.customer_id IS 'Customer who owns the site.';
COMMENT ON COLUMN solar_app.service_request_details.technician_id IS 'Assigned field engineer, if any.';
COMMENT ON COLUMN solar_app.service_request_details.service_type_ref_data_id IS 'FK to SERVICE_TYPES (cleaning, inspection, inverter check).';
COMMENT ON COLUMN solar_app.service_request_details.slot_window_ref_data_id IS 'FK to SERVICE_SLOT_WINDOWS.';
COMMENT ON COLUMN solar_app.service_request_details.status_ref_data_id IS 'FK to SERVICE_REQUEST_STATUSES.';
COMMENT ON COLUMN solar_app.service_request_details.preferred_on IS 'Customer preferred date.';
COMMENT ON COLUMN solar_app.service_request_details.milestone_id IS 'Free-service milestone being claimed, if any.';
COMMENT ON COLUMN solar_app.service_request_details.amc_contract_id IS 'AMC this visit is billed/covered under, if any.';
COMMENT ON COLUMN solar_app.service_request_details.order_id IS 'Optional related fulfilment order.';
COMMENT ON COLUMN solar_app.service_request_details.product_id IS 'Optional catalogue product this visit relates to.';
COMMENT ON COLUMN solar_app.service_request_details.arrival_status IS 'Technician arrival state for the customer tracker.';
COMMENT ON COLUMN solar_app.service_request_details.completion_notes IS 'Work done / historical Path B notes.';
COMMENT ON COLUMN solar_app.service_request_details.report_url IS 'Downloadable service report URL.';
COMMENT ON COLUMN solar_app.service_request_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.service_request_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.service_request_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.service_request_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.service_request_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_sr_tech_status_date ON solar_app.service_request_details (technician_id, status_ref_data_id, preferred_on) WHERE active_ind = TRUE;
CREATE INDEX idx_sr_customer_site ON solar_app.service_request_details (customer_id, site_id) WHERE active_ind = TRUE;

-- =====================================================================
-- MODULE 6 — Complaints
-- =====================================================================

CREATE TABLE solar_app.complaint_ticket_details (
    complaint_ticket_id       BIGINT GENERATED ALWAYS AS IDENTITY,
    ticket_no                 VARCHAR(30)   NOT NULL,
    site_id                   BIGINT        NOT NULL,
    customer_id               BIGINT        NOT NULL,
    raised_by_user_id         BIGINT        NOT NULL,
    assigned_technician_id    BIGINT,
    category_ref_data_id      BIGINT        NOT NULL,
    severity_ref_data_id      BIGINT        NOT NULL,
    status_ref_data_id        BIGINT        NOT NULL,
    description               VARCHAR(2000) NOT NULL,
    resolution_otp_hash       VARCHAR(255),
    otp_expires_on            TIMESTAMPTZ,
    resolved_on               TIMESTAMPTZ,
    closed_on                 TIMESTAMPTZ,
    active_ind                BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by                VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by                VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on                TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_complaint_ticket PRIMARY KEY (complaint_ticket_id),
    CONSTRAINT uq_complaint_ticket_no UNIQUE (ticket_no),
    CONSTRAINT fk_tkt_site FOREIGN KEY (site_id) REFERENCES solar_app.site_details (site_id) ON DELETE RESTRICT,
    CONSTRAINT fk_tkt_customer FOREIGN KEY (customer_id) REFERENCES solar_app.customer_details (customer_id) ON DELETE RESTRICT,
    CONSTRAINT fk_tkt_raiser FOREIGN KEY (raised_by_user_id) REFERENCES solar_app.user_details (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_tkt_tech FOREIGN KEY (assigned_technician_id) REFERENCES solar_app.technician_details (technician_id) ON DELETE SET NULL,
    CONSTRAINT fk_tkt_cat FOREIGN KEY (category_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_tkt_sev FOREIGN KEY (severity_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_tkt_status FOREIGN KEY (status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT
);
COMMENT ON TABLE solar_app.complaint_ticket_details IS 'Breakdown complaint header with unique ticket number and hashed resolution OTP.';
COMMENT ON COLUMN solar_app.complaint_ticket_details.complaint_ticket_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.complaint_ticket_details.ticket_no IS 'Public unique ticket number (TKT-YYYY-nnnn).';
COMMENT ON COLUMN solar_app.complaint_ticket_details.site_id IS 'Site the complaint is about.';
COMMENT ON COLUMN solar_app.complaint_ticket_details.customer_id IS 'Customer who owns the site.';
COMMENT ON COLUMN solar_app.complaint_ticket_details.raised_by_user_id IS 'User who raised the ticket.';
COMMENT ON COLUMN solar_app.complaint_ticket_details.assigned_technician_id IS 'Assigned field engineer.';
COMMENT ON COLUMN solar_app.complaint_ticket_details.category_ref_data_id IS 'FK to COMPLAINT_CATEGORIES.';
COMMENT ON COLUMN solar_app.complaint_ticket_details.severity_ref_data_id IS 'FK to COMPLAINT_SEVERITIES (including Emergency).';
COMMENT ON COLUMN solar_app.complaint_ticket_details.status_ref_data_id IS 'FK to TICKET_STATUSES stepper.';
COMMENT ON COLUMN solar_app.complaint_ticket_details.description IS 'Fault description from the customer or admin.';
COMMENT ON COLUMN solar_app.complaint_ticket_details.resolution_otp_hash IS 'Hashed 4-digit OTP required to mark Resolved; never plaintext.';
COMMENT ON COLUMN solar_app.complaint_ticket_details.otp_expires_on IS 'Resolution OTP expiry.';
COMMENT ON COLUMN solar_app.complaint_ticket_details.resolved_on IS 'When the ticket was marked Resolved.';
COMMENT ON COLUMN solar_app.complaint_ticket_details.closed_on IS 'When the ticket was closed.';
COMMENT ON COLUMN solar_app.complaint_ticket_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.complaint_ticket_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.complaint_ticket_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.complaint_ticket_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.complaint_ticket_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_tkt_tech_status_created ON solar_app.complaint_ticket_details (assigned_technician_id, status_ref_data_id, created_on DESC) WHERE active_ind = TRUE;
CREATE INDEX idx_tkt_customer_site ON solar_app.complaint_ticket_details (customer_id, site_id, created_on DESC);

CREATE TABLE solar_app.ticket_status_history_details (
    ticket_status_history_id BIGINT GENERATED ALWAYS AS IDENTITY,
    complaint_ticket_id      BIGINT NOT NULL,
    from_status_ref_data_id  BIGINT,
    to_status_ref_data_id    BIGINT NOT NULL,
    changed_by_user_id       BIGINT,
    remarks                  VARCHAR(500),
    active_ind               BOOLEAN NOT NULL DEFAULT TRUE,
    created_by               VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    updated_by               VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    created_on               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on               TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ticket_status_history PRIMARY KEY (ticket_status_history_id),
    CONSTRAINT fk_tsh_ticket FOREIGN KEY (complaint_ticket_id) REFERENCES solar_app.complaint_ticket_details (complaint_ticket_id) ON DELETE CASCADE,
    CONSTRAINT fk_tsh_from FOREIGN KEY (from_status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_tsh_to FOREIGN KEY (to_status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_tsh_user FOREIGN KEY (changed_by_user_id) REFERENCES solar_app.user_details (user_id) ON DELETE SET NULL
);
COMMENT ON TABLE solar_app.ticket_status_history_details IS 'Ticket stepper history. Functions insert a row on each status change (no triggers).';
COMMENT ON COLUMN solar_app.ticket_status_history_details.ticket_status_history_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ticket_status_history_details.complaint_ticket_id IS 'Parent ticket.';
COMMENT ON COLUMN solar_app.ticket_status_history_details.from_status_ref_data_id IS 'Previous stepper status; NULL on first insert.';
COMMENT ON COLUMN solar_app.ticket_status_history_details.to_status_ref_data_id IS 'New stepper status.';
COMMENT ON COLUMN solar_app.ticket_status_history_details.changed_by_user_id IS 'Actor who changed status.';
COMMENT ON COLUMN solar_app.ticket_status_history_details.remarks IS 'Optional reason for the transition.';
COMMENT ON COLUMN solar_app.ticket_status_history_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ticket_status_history_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ticket_status_history_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ticket_status_history_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ticket_status_history_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_tsh_ticket_created ON solar_app.ticket_status_history_details (complaint_ticket_id, created_on);

CREATE TABLE solar_app.ticket_media_details (
    ticket_media_id     BIGINT GENERATED ALWAYS AS IDENTITY,
    complaint_ticket_id BIGINT       NOT NULL,
    media_type          VARCHAR(20)  NOT NULL,
    file_url            VARCHAR(500) NOT NULL,
    file_size_bytes     INTEGER,
    sort_order          INTEGER      NOT NULL DEFAULT 0,
    active_ind          BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by          VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by          VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ticket_media PRIMARY KEY (ticket_media_id),
    CONSTRAINT fk_tm_ticket FOREIGN KEY (complaint_ticket_id) REFERENCES solar_app.complaint_ticket_details (complaint_ticket_id) ON DELETE CASCADE,
    CONSTRAINT chk_tm_type CHECK (media_type IN ('PHOTO', 'VIDEO')),
    CONSTRAINT chk_tm_size CHECK (file_size_bytes IS NULL OR file_size_bytes > 0)
);
COMMENT ON TABLE solar_app.ticket_media_details IS 'Complaint photo/video attachments; the effective attachment-count limit comes from business parameters.';
COMMENT ON COLUMN solar_app.ticket_media_details.ticket_media_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ticket_media_details.complaint_ticket_id IS 'Parent ticket.';
COMMENT ON COLUMN solar_app.ticket_media_details.media_type IS 'PHOTO or VIDEO.';
COMMENT ON COLUMN solar_app.ticket_media_details.file_url IS 'Object-storage URL.';
COMMENT ON COLUMN solar_app.ticket_media_details.file_size_bytes IS 'File size in bytes.';
COMMENT ON COLUMN solar_app.ticket_media_details.sort_order IS 'Gallery order; count limits are resolved from effective business parameters.';
COMMENT ON COLUMN solar_app.ticket_media_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ticket_media_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ticket_media_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ticket_media_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ticket_media_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_tm_ticket_sort ON solar_app.ticket_media_details (complaint_ticket_id, sort_order);

CREATE TABLE solar_app.ticket_message_details (
    ticket_message_id   BIGINT GENERATED ALWAYS AS IDENTITY,
    complaint_ticket_id BIGINT        NOT NULL,
    sender_user_id      BIGINT        NOT NULL,
    message_text        VARCHAR(2000) NOT NULL,
    is_internal         BOOLEAN       NOT NULL DEFAULT FALSE,
    active_ind          BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by          VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by          VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on          TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on          TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ticket_message PRIMARY KEY (ticket_message_id),
    CONSTRAINT fk_tmsg_ticket FOREIGN KEY (complaint_ticket_id) REFERENCES solar_app.complaint_ticket_details (complaint_ticket_id) ON DELETE CASCADE,
    CONSTRAINT fk_tmsg_sender FOREIGN KEY (sender_user_id) REFERENCES solar_app.user_details (user_id) ON DELETE RESTRICT
);
COMMENT ON TABLE solar_app.ticket_message_details IS 'In-app ticket chat. is_internal hides dispatcher notes from the customer.';
COMMENT ON COLUMN solar_app.ticket_message_details.ticket_message_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.ticket_message_details.complaint_ticket_id IS 'Parent ticket.';
COMMENT ON COLUMN solar_app.ticket_message_details.sender_user_id IS 'User who sent the chat message.';
COMMENT ON COLUMN solar_app.ticket_message_details.message_text IS 'Chat body.';
COMMENT ON COLUMN solar_app.ticket_message_details.is_internal IS 'TRUE hides the note from the customer (dispatcher only).';
COMMENT ON COLUMN solar_app.ticket_message_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ticket_message_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.ticket_message_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.ticket_message_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.ticket_message_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_tmsg_ticket_created ON solar_app.ticket_message_details (complaint_ticket_id, created_on);

-- =====================================================================
-- MODULE 7 — Technician jobs
-- =====================================================================

CREATE TABLE solar_app.job_assignment_details (
    job_id                 BIGINT GENERATED ALWAYS AS IDENTITY,
    job_type               VARCHAR(30) NOT NULL,
    site_id                BIGINT      NOT NULL,
    technician_id          BIGINT      NOT NULL,
    service_request_id     BIGINT,
    complaint_ticket_id    BIGINT,
    site_visit_id          BIGINT,
    job_status_ref_data_id BIGINT      NOT NULL,
    scheduled_on           DATE        NOT NULL,
    sequence_no            INTEGER,
    travel_distance_km     NUMERIC(8,2),
    accept_reject_reason   VARCHAR(500),
    eta_on                 TIMESTAMPTZ,
    started_on             TIMESTAMPTZ,
    completed_on           TIMESTAMPTZ,
    active_ind             BOOLEAN     NOT NULL DEFAULT TRUE,
    created_by             VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    updated_by             VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    created_on             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_job_assignment PRIMARY KEY (job_id),
    CONSTRAINT fk_job_site FOREIGN KEY (site_id) REFERENCES solar_app.site_details (site_id) ON DELETE RESTRICT,
    CONSTRAINT fk_job_tech FOREIGN KEY (technician_id) REFERENCES solar_app.technician_details (technician_id) ON DELETE RESTRICT,
    CONSTRAINT fk_job_sr FOREIGN KEY (service_request_id) REFERENCES solar_app.service_request_details (service_request_id) ON DELETE CASCADE,
    CONSTRAINT fk_job_tkt FOREIGN KEY (complaint_ticket_id) REFERENCES solar_app.complaint_ticket_details (complaint_ticket_id) ON DELETE CASCADE,
    CONSTRAINT fk_job_visit FOREIGN KEY (site_visit_id) REFERENCES solar_app.site_visit_details (site_visit_id) ON DELETE SET NULL,
    CONSTRAINT fk_job_status FOREIGN KEY (job_status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT chk_job_type CHECK (job_type IN ('SERVICE_REQUEST', 'COMPLAINT', 'SITE_VISIT', 'COMMISSIONING')),
    CONSTRAINT chk_job_parent CHECK (
        (job_type = 'SERVICE_REQUEST' AND service_request_id IS NOT NULL)
        OR (job_type = 'COMPLAINT' AND complaint_ticket_id IS NOT NULL)
        OR (job_type = 'SITE_VISIT' AND site_visit_id IS NOT NULL)
        OR (job_type = 'COMMISSIONING')
    )
);
COMMENT ON TABLE solar_app.job_assignment_details IS 'Technician field job linked to a site visit, service request, complaint, or commissioning. Sales/other assignees use site_visit_details.assigned_to_user_id without a job row.';
COMMENT ON COLUMN solar_app.job_assignment_details.job_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.job_assignment_details.job_type IS 'SERVICE_REQUEST, COMPLAINT, SITE_VISIT, or COMMISSIONING.';
COMMENT ON COLUMN solar_app.job_assignment_details.site_id IS 'Site the technician must visit.';
COMMENT ON COLUMN solar_app.job_assignment_details.technician_id IS 'Assigned field engineer.';
COMMENT ON COLUMN solar_app.job_assignment_details.service_request_id IS 'Parent SR when job_type is SERVICE_REQUEST.';
COMMENT ON COLUMN solar_app.job_assignment_details.complaint_ticket_id IS 'Parent ticket when job_type is COMPLAINT.';
COMMENT ON COLUMN solar_app.job_assignment_details.site_visit_id IS 'Parent site_visit_details when this job is the technician execution of that visit.';
COMMENT ON COLUMN solar_app.job_assignment_details.job_status_ref_data_id IS 'FK to JOB_STATUSES.';
COMMENT ON COLUMN solar_app.job_assignment_details.scheduled_on IS 'Job date for the technician queue.';
COMMENT ON COLUMN solar_app.job_assignment_details.sequence_no IS 'Route order for the day.';
COMMENT ON COLUMN solar_app.job_assignment_details.travel_distance_km IS 'Route distance for the day queue; visit billing uses site_visit_details.distance_from_office_km.';
COMMENT ON COLUMN solar_app.job_assignment_details.accept_reject_reason IS 'Reason when the technician reschedules or rejects.';
COMMENT ON COLUMN solar_app.job_assignment_details.eta_on IS 'Estimated arrival instant.';
COMMENT ON COLUMN solar_app.job_assignment_details.started_on IS 'When on-site work started.';
COMMENT ON COLUMN solar_app.job_assignment_details.completed_on IS 'When the job was completed.';
COMMENT ON COLUMN solar_app.job_assignment_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.job_assignment_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.job_assignment_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.job_assignment_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.job_assignment_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_job_tech_schedule_status ON solar_app.job_assignment_details (technician_id, scheduled_on, job_status_ref_data_id) WHERE active_ind = TRUE;

CREATE TABLE solar_app.job_checklist_response_details (
    job_checklist_response_id BIGINT GENERATED ALWAYS AS IDENTITY,
    job_id                    BIGINT NOT NULL,
    checklist_item_id         BIGINT NOT NULL,
    is_pass                   BOOLEAN,
    measured_value            VARCHAR(100),
    remarks                   VARCHAR(500),
    active_ind                BOOLEAN NOT NULL DEFAULT TRUE,
    created_by                VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    updated_by                VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    created_on                TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_job_checklist PRIMARY KEY (job_checklist_response_id),
    CONSTRAINT fk_jcr_job FOREIGN KEY (job_id) REFERENCES solar_app.job_assignment_details (job_id) ON DELETE CASCADE,
    CONSTRAINT fk_jcr_item FOREIGN KEY (checklist_item_id) REFERENCES solar_app.ref_checklist_items (checklist_item_id) ON DELETE RESTRICT
);
COMMENT ON TABLE solar_app.job_checklist_response_details IS 'Technician answers against ref_checklist_items for one job.';
COMMENT ON COLUMN solar_app.job_checklist_response_details.job_checklist_response_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.job_checklist_response_details.job_id IS 'Parent job.';
COMMENT ON COLUMN solar_app.job_checklist_response_details.checklist_item_id IS 'FK to ref_checklist_items template line.';
COMMENT ON COLUMN solar_app.job_checklist_response_details.is_pass IS 'BOOLEAN result when expected_value_type is BOOLEAN.';
COMMENT ON COLUMN solar_app.job_checklist_response_details.measured_value IS 'Numeric or text measurement (VOC/ISC, remarks).';
COMMENT ON COLUMN solar_app.job_checklist_response_details.remarks IS 'Optional technician note for this item.';
COMMENT ON COLUMN solar_app.job_checklist_response_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.job_checklist_response_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.job_checklist_response_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.job_checklist_response_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.job_checklist_response_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

CREATE TABLE solar_app.job_media_details (
    job_media_id   BIGINT GENERATED ALWAYS AS IDENTITY,
    job_id         BIGINT       NOT NULL,
    media_purpose  VARCHAR(30)  NOT NULL,
    file_url       VARCHAR(500) NOT NULL,
    captured_on    TIMESTAMPTZ,
    active_ind     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by     VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by     VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on     TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on     TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_job_media PRIMARY KEY (job_media_id),
    CONSTRAINT fk_jm_job FOREIGN KEY (job_id) REFERENCES solar_app.job_assignment_details (job_id) ON DELETE CASCADE,
    CONSTRAINT chk_jm_purpose CHECK (media_purpose IN ('BEFORE', 'AFTER', 'INVERTER_STATUS', 'OTHER'))
);
COMMENT ON TABLE solar_app.job_media_details IS 'Before/after and inverter-status photos captured on a job.';
COMMENT ON COLUMN solar_app.job_media_details.job_media_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.job_media_details.job_id IS 'Parent job.';
COMMENT ON COLUMN solar_app.job_media_details.media_purpose IS 'BEFORE, AFTER, INVERTER_STATUS, or OTHER.';
COMMENT ON COLUMN solar_app.job_media_details.file_url IS 'Object-storage URL of the photo.';
COMMENT ON COLUMN solar_app.job_media_details.captured_on IS 'Capture timestamp.';
COMMENT ON COLUMN solar_app.job_media_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.job_media_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.job_media_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.job_media_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.job_media_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

CREATE TABLE solar_app.job_signoff_details (
    job_signoff_id    BIGINT GENERATED ALWAYS AS IDENTITY,
    job_id            BIGINT       NOT NULL,
    signature_url     VARCHAR(500) NOT NULL,
    signer_name       VARCHAR(150),
    signed_on         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    otp_verified_ind  BOOLEAN      NOT NULL DEFAULT FALSE,
    customer_user_id  BIGINT,
    active_ind        BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by        VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    updated_by        VARCHAR(50)  NOT NULL DEFAULT 'SYSTEM',
    created_on        TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on        TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_job_signoff PRIMARY KEY (job_signoff_id),
    CONSTRAINT fk_js_job FOREIGN KEY (job_id) REFERENCES solar_app.job_assignment_details (job_id) ON DELETE CASCADE,
    CONSTRAINT fk_js_user FOREIGN KEY (customer_user_id) REFERENCES solar_app.user_details (user_id) ON DELETE SET NULL
);
COMMENT ON TABLE solar_app.job_signoff_details IS 'Customer signature pad image; otp_verified_ind records complaint resolution OTP success.';
COMMENT ON COLUMN solar_app.job_signoff_details.job_signoff_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.job_signoff_details.job_id IS 'Parent job (one active sign-off per job in functions).';
COMMENT ON COLUMN solar_app.job_signoff_details.signature_url IS 'Signature-pad image URL.';
COMMENT ON COLUMN solar_app.job_signoff_details.signer_name IS 'Name captured with the signature.';
COMMENT ON COLUMN solar_app.job_signoff_details.signed_on IS 'When the customer signed.';
COMMENT ON COLUMN solar_app.job_signoff_details.otp_verified_ind IS 'TRUE when complaint resolution OTP succeeded.';
COMMENT ON COLUMN solar_app.job_signoff_details.customer_user_id IS 'Customer user who signed, if known.';
COMMENT ON COLUMN solar_app.job_signoff_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.job_signoff_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.job_signoff_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.job_signoff_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.job_signoff_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

CREATE TABLE solar_app.spare_part_request_details (
    spare_part_request_id BIGINT GENERATED ALWAYS AS IDENTITY,
    job_id                BIGINT        NOT NULL,
    complaint_ticket_id   BIGINT,
    part_code             VARCHAR(50),
    part_name             VARCHAR(150)  NOT NULL,
    quantity              NUMERIC(12,3) NOT NULL,
    request_status        VARCHAR(20)   NOT NULL DEFAULT 'REQUESTED',
    remarks               VARCHAR(500),
    active_ind            BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by            VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by            VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on            TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on            TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_spare_part_request PRIMARY KEY (spare_part_request_id),
    CONSTRAINT fk_spr_job FOREIGN KEY (job_id) REFERENCES solar_app.job_assignment_details (job_id) ON DELETE CASCADE,
    CONSTRAINT fk_spr_tkt FOREIGN KEY (complaint_ticket_id) REFERENCES solar_app.complaint_ticket_details (complaint_ticket_id) ON DELETE SET NULL,
    CONSTRAINT chk_spr_qty CHECK (quantity > 0),
    CONSTRAINT chk_spr_status CHECK (request_status IN ('REQUESTED', 'APPROVED', 'ISSUED', 'USED', 'REJECTED'))
);
COMMENT ON TABLE solar_app.spare_part_request_details IS 'Technician spare-part request from site. Not a warehouse SKU ledger in v1.';
COMMENT ON COLUMN solar_app.spare_part_request_details.spare_part_request_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.spare_part_request_details.job_id IS 'Job during which parts were requested.';
COMMENT ON COLUMN solar_app.spare_part_request_details.complaint_ticket_id IS 'Optional related complaint.';
COMMENT ON COLUMN solar_app.spare_part_request_details.part_code IS 'Optional part code (not a warehouse SKU master).';
COMMENT ON COLUMN solar_app.spare_part_request_details.part_name IS 'Part description.';
COMMENT ON COLUMN solar_app.spare_part_request_details.quantity IS 'Requested quantity.';
COMMENT ON COLUMN solar_app.spare_part_request_details.request_status IS 'REQUESTED, APPROVED, ISSUED, USED, or REJECTED.';
COMMENT ON COLUMN solar_app.spare_part_request_details.remarks IS 'Technician or admin notes.';
COMMENT ON COLUMN solar_app.spare_part_request_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.spare_part_request_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.spare_part_request_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.spare_part_request_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.spare_part_request_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

-- =====================================================================
-- MODULE 8 — Offline billing & payment register
-- =====================================================================

CREATE TABLE solar_app.invoice_details (
    invoice_id                      BIGINT GENERATED ALWAYS AS IDENTITY,
    invoice_no                      VARCHAR(40)   NOT NULL,
    customer_id                     BIGINT        NOT NULL,
    site_id                         BIGINT,
    related_order_id                BIGINT,
    invoice_category_ref_data_id    BIGINT        NOT NULL,
    invoice_status_ref_data_id      BIGINT        NOT NULL,
    invoice_date                    DATE          NOT NULL,
    currency_code                   CHAR(3)       NOT NULL,
    taxable_amount                  NUMERIC(14,2) NOT NULL DEFAULT 0,
    tax_amount                      NUMERIC(14,2) NOT NULL DEFAULT 0,
    total_amount                    NUMERIC(14,2) NOT NULL,
    paid_amount                     NUMERIC(14,2) NOT NULL DEFAULT 0,
    balance_amount                  NUMERIC(14,2) NOT NULL DEFAULT 0,
    related_amc_contract_id         BIGINT,
    related_service_request_id      BIGINT,
    related_spare_part_request_id   BIGINT,
    remarks                         VARCHAR(500),
    active_ind                      BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by                      VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by                      VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on                      TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                      TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_invoice_details PRIMARY KEY (invoice_id),
    CONSTRAINT uq_invoice_no UNIQUE (invoice_no),
    CONSTRAINT fk_inv_customer FOREIGN KEY (customer_id) REFERENCES solar_app.customer_details (customer_id) ON DELETE RESTRICT,
    CONSTRAINT fk_inv_site FOREIGN KEY (site_id) REFERENCES solar_app.site_details (site_id) ON DELETE SET NULL,
    CONSTRAINT fk_inv_cat FOREIGN KEY (invoice_category_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_inv_status FOREIGN KEY (invoice_status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_inv_currency FOREIGN KEY (currency_code) REFERENCES solar_app.ref_currencies (currency_code) ON DELETE RESTRICT,
    CONSTRAINT fk_inv_amc FOREIGN KEY (related_amc_contract_id) REFERENCES solar_app.amc_contract_details (amc_contract_id) ON DELETE SET NULL,
    CONSTRAINT fk_inv_sr FOREIGN KEY (related_service_request_id) REFERENCES solar_app.service_request_details (service_request_id) ON DELETE SET NULL,
    CONSTRAINT fk_inv_spr FOREIGN KEY (related_spare_part_request_id) REFERENCES solar_app.spare_part_request_details (spare_part_request_id) ON DELETE SET NULL,
    CONSTRAINT chk_inv_totals CHECK (taxable_amount >= 0 AND tax_amount >= 0 AND total_amount >= 0 AND paid_amount >= 0 AND balance_amount >= 0)
);
COMMENT ON TABLE solar_app.invoice_details IS 'Offline bill header transcribed by admin. Not a payment gateway or electronic tax-invoice integration. Customers may view only.';
COMMENT ON COLUMN solar_app.invoice_details.invoice_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.invoice_details.invoice_no IS 'Offline bill number (manual or generated). Unique.';
COMMENT ON COLUMN solar_app.invoice_details.customer_id IS 'Customer this bill is recorded against.';
COMMENT ON COLUMN solar_app.invoice_details.site_id IS 'Optional site.';
COMMENT ON COLUMN solar_app.invoice_details.related_order_id IS 'Optional fulfilment order; FK added after order_details exists.';
COMMENT ON COLUMN solar_app.invoice_details.invoice_category_ref_data_id IS 'FK to INVOICE_CATEGORIES (installation, AMC, spares, cleaning).';
COMMENT ON COLUMN solar_app.invoice_details.invoice_status_ref_data_id IS 'FK to INVOICE_STATUSES (draft, unpaid, partial, paid, cancelled).';
COMMENT ON COLUMN solar_app.invoice_details.invoice_date IS 'Bill date as transcribed by admin.';
COMMENT ON COLUMN solar_app.invoice_details.currency_code IS 'Currency snapshot for every invoice, line, tax, and balance amount.';
COMMENT ON COLUMN solar_app.invoice_details.taxable_amount IS 'Total taxable base transcribed or calculated for this invoice.';
COMMENT ON COLUMN solar_app.invoice_details.tax_amount IS 'Total of generic component snapshots in invoice_tax_details.';
COMMENT ON COLUMN solar_app.invoice_details.total_amount IS 'Total amount on the paper/bank bill.';
COMMENT ON COLUMN solar_app.invoice_details.paid_amount IS 'Running sum of offline receipts; maintained in functions.';
COMMENT ON COLUMN solar_app.invoice_details.balance_amount IS 'total_amount minus paid_amount; maintained in functions.';
COMMENT ON COLUMN solar_app.invoice_details.related_amc_contract_id IS 'Optional AMC this bill covers.';
COMMENT ON COLUMN solar_app.invoice_details.related_service_request_id IS 'Optional service visit this bill covers.';
COMMENT ON COLUMN solar_app.invoice_details.related_spare_part_request_id IS 'Optional spare-part request this bill covers.';
COMMENT ON COLUMN solar_app.invoice_details.remarks IS 'Admin transcription notes.';
COMMENT ON COLUMN solar_app.invoice_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.invoice_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.invoice_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.invoice_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.invoice_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_invoice_customer_date ON solar_app.invoice_details (customer_id, invoice_date DESC);
CREATE INDEX idx_invoice_status_date ON solar_app.invoice_details (invoice_status_ref_data_id, invoice_date DESC) WHERE active_ind = TRUE;

CREATE TABLE solar_app.invoice_line_details (
    invoice_line_id BIGINT GENERATED ALWAYS AS IDENTITY,
    invoice_id      BIGINT        NOT NULL,
    line_no         INTEGER       NOT NULL,
    line_desc       VARCHAR(255)  NOT NULL,
    tax_classification_code VARCHAR(30),
    quantity        NUMERIC(12,3) NOT NULL DEFAULT 1,
    unit_rate       NUMERIC(12,2) NOT NULL DEFAULT 0,
    line_amount     NUMERIC(14,2) NOT NULL,
    active_ind      BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by      VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by      VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on      TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on      TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_invoice_line PRIMARY KEY (invoice_line_id),
    CONSTRAINT fk_il_inv FOREIGN KEY (invoice_id) REFERENCES solar_app.invoice_details (invoice_id) ON DELETE CASCADE,
    CONSTRAINT uq_il_invoice_line UNIQUE (invoice_id, invoice_line_id),
    CONSTRAINT uq_il_no UNIQUE (invoice_id, line_no),
    CONSTRAINT chk_il_qty CHECK (quantity > 0)
);
COMMENT ON TABLE solar_app.invoice_line_details IS 'Optional transcribed paper-invoice lines. A bill may store header totals only.';
COMMENT ON COLUMN solar_app.invoice_line_details.invoice_line_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.invoice_line_details.invoice_id IS 'Parent offline bill.';
COMMENT ON COLUMN solar_app.invoice_line_details.line_no IS 'Line sequence unique per bill.';
COMMENT ON COLUMN solar_app.invoice_line_details.line_desc IS 'Transcribed line description.';
COMMENT ON COLUMN solar_app.invoice_line_details.tax_classification_code IS 'Optional country-specific tax classification copied from the source document.';
COMMENT ON COLUMN solar_app.invoice_line_details.quantity IS 'Quantity.';
COMMENT ON COLUMN solar_app.invoice_line_details.unit_rate IS 'Rate per unit.';
COMMENT ON COLUMN solar_app.invoice_line_details.line_amount IS 'Line amount.';
COMMENT ON COLUMN solar_app.invoice_line_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.invoice_line_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.invoice_line_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.invoice_line_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.invoice_line_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

CREATE TABLE solar_app.invoice_tax_details (
    invoice_tax_id      BIGINT GENERATED ALWAYS AS IDENTITY,
    invoice_id          BIGINT        NOT NULL,
    invoice_line_id     BIGINT,
    source_tax_rule_id  BIGINT,
    tax_group_code      VARCHAR(50)   NOT NULL,
    tax_component_code  VARCHAR(50)   NOT NULL,
    tax_display_name    VARCHAR(150)  NOT NULL,
    calculation_method  VARCHAR(20)   NOT NULL,
    rate_percent        NUMERIC(7,4),
    configured_rate_amount NUMERIC(14,2),
    taxable_amount      NUMERIC(14,2) NOT NULL,
    tax_amount          NUMERIC(14,2) NOT NULL,
    jurisdiction_json   JSONB         NOT NULL DEFAULT '{}'::jsonb,
    active_ind          BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by          VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by          VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on          TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on          TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_invoice_tax_details PRIMARY KEY (invoice_tax_id),
    CONSTRAINT fk_invoice_tax_invoice FOREIGN KEY (invoice_id) REFERENCES solar_app.invoice_details (invoice_id) ON DELETE CASCADE,
    CONSTRAINT fk_invoice_tax_line FOREIGN KEY (invoice_id, invoice_line_id) REFERENCES solar_app.invoice_line_details (invoice_id, invoice_line_id) ON DELETE CASCADE,
    CONSTRAINT fk_invoice_tax_rule FOREIGN KEY (source_tax_rule_id) REFERENCES solar_app.ref_tax_rules (tax_rule_id) ON DELETE SET NULL,
    CONSTRAINT chk_invoice_tax_method CHECK (calculation_method IN ('PERCENTAGE', 'FIXED_AMOUNT')),
    CONSTRAINT chk_invoice_tax_rate CHECK (
        (calculation_method = 'PERCENTAGE' AND rate_percent BETWEEN 0 AND 100 AND configured_rate_amount IS NULL)
        OR
        (calculation_method = 'FIXED_AMOUNT' AND rate_percent IS NULL AND configured_rate_amount >= 0)
    ),
    CONSTRAINT chk_invoice_tax_amounts CHECK (taxable_amount >= 0 AND tax_amount >= 0)
);
COMMENT ON TABLE solar_app.invoice_tax_details IS 'Immutable transaction-level tax component snapshots for an invoice or optional invoice line.';
COMMENT ON COLUMN solar_app.invoice_tax_details.invoice_tax_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.invoice_tax_details.invoice_id IS 'Parent offline invoice.';
COMMENT ON COLUMN solar_app.invoice_tax_details.invoice_line_id IS 'Optional invoice line to which this component applies; NULL means invoice-level.';
COMMENT ON COLUMN solar_app.invoice_tax_details.source_tax_rule_id IS 'Optional source rule retained for traceability; snapshot columns remain authoritative for history.';
COMMENT ON COLUMN solar_app.invoice_tax_details.tax_group_code IS 'Applied tax group code snapshot.';
COMMENT ON COLUMN solar_app.invoice_tax_details.tax_component_code IS 'Applied component code snapshot.';
COMMENT ON COLUMN solar_app.invoice_tax_details.tax_display_name IS 'Customer-facing component label snapshot.';
COMMENT ON COLUMN solar_app.invoice_tax_details.calculation_method IS 'Applied calculation method snapshot.';
COMMENT ON COLUMN solar_app.invoice_tax_details.rate_percent IS 'Applied percentage snapshot for a percentage rule.';
COMMENT ON COLUMN solar_app.invoice_tax_details.configured_rate_amount IS 'Applied configured amount snapshot for a fixed-amount rule.';
COMMENT ON COLUMN solar_app.invoice_tax_details.taxable_amount IS 'Taxable base used for this component.';
COMMENT ON COLUMN solar_app.invoice_tax_details.tax_amount IS 'Calculated or transcribed component amount.';
COMMENT ON COLUMN solar_app.invoice_tax_details.jurisdiction_json IS 'Snapshot of applicable country, region, place-of-supply, and classification context.';
COMMENT ON COLUMN solar_app.invoice_tax_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.invoice_tax_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.invoice_tax_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.invoice_tax_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.invoice_tax_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_invoice_tax_invoice ON solar_app.invoice_tax_details (invoice_id);
CREATE INDEX idx_invoice_tax_line ON solar_app.invoice_tax_details (invoice_line_id) WHERE invoice_line_id IS NOT NULL;

CREATE TABLE solar_app.payment_details (
    payment_id                  BIGINT GENERATED ALWAYS AS IDENTITY,
    invoice_id                  BIGINT        NOT NULL,
    customer_id                 BIGINT        NOT NULL,
    amount                      NUMERIC(14,2) NOT NULL,
    currency_code               CHAR(3)       NOT NULL,
    payment_method_ref_data_id  BIGINT        NOT NULL,
    payment_status_ref_data_id  BIGINT        NOT NULL,
    is_offline_ind              BOOLEAN       NOT NULL DEFAULT TRUE,
    instrument_ref              VARCHAR(100),
    paid_on                     DATE          NOT NULL,
    remarks                     VARCHAR(500),
    active_ind                  BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by                  VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by                  VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on                  TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                  TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_payment_details PRIMARY KEY (payment_id),
    CONSTRAINT fk_pay_inv FOREIGN KEY (invoice_id) REFERENCES solar_app.invoice_details (invoice_id) ON DELETE RESTRICT,
    CONSTRAINT fk_pay_customer FOREIGN KEY (customer_id) REFERENCES solar_app.customer_details (customer_id) ON DELETE RESTRICT,
    CONSTRAINT fk_pay_currency FOREIGN KEY (currency_code) REFERENCES solar_app.ref_currencies (currency_code) ON DELETE RESTRICT,
    CONSTRAINT fk_pay_method FOREIGN KEY (payment_method_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_pay_status FOREIGN KEY (payment_status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT chk_pay_amount CHECK (amount > 0)
);
COMMENT ON TABLE solar_app.payment_details IS 'Offline payment/receipt register. is_offline_ind is TRUE in v1; no in-app checkout.';
COMMENT ON COLUMN solar_app.payment_details.payment_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.payment_details.invoice_id IS 'Offline bill this receipt is applied to.';
COMMENT ON COLUMN solar_app.payment_details.customer_id IS 'Paying customer (denormalized for queries).';
COMMENT ON COLUMN solar_app.payment_details.amount IS 'Amount received outside the app.';
COMMENT ON COLUMN solar_app.payment_details.currency_code IS 'Currency snapshot for amount; it must match the associated invoice under transaction validation.';
COMMENT ON COLUMN solar_app.payment_details.payment_method_ref_data_id IS 'FK to PAYMENT_METHODS (cash, cheque, NEFT, UPI-offline, other).';
COMMENT ON COLUMN solar_app.payment_details.payment_status_ref_data_id IS 'FK to PAYMENT_STATUSES (recorded, cancelled).';
COMMENT ON COLUMN solar_app.payment_details.is_offline_ind IS 'Always TRUE in v1. There is no in-app payment gateway.';
COMMENT ON COLUMN solar_app.payment_details.instrument_ref IS 'Cheque number, UTR, or paper receipt number.';
COMMENT ON COLUMN solar_app.payment_details.paid_on IS 'Date money was collected offline.';
COMMENT ON COLUMN solar_app.payment_details.remarks IS 'Admin notes.';
COMMENT ON COLUMN solar_app.payment_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.payment_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.payment_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.payment_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.payment_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_payment_invoice_date ON solar_app.payment_details (invoice_id, paid_on DESC);
CREATE INDEX idx_payment_customer_date ON solar_app.payment_details (customer_id, paid_on DESC);

CREATE TABLE solar_app.payment_milestone_details (
    payment_milestone_id BIGINT GENERATED ALWAYS AS IDENTITY,
    invoice_id           BIGINT        NOT NULL,
    sequence_no          INTEGER       NOT NULL,
    percent_share        NUMERIC(5,2),
    due_amount           NUMERIC(14,2) NOT NULL,
    paid_amount          NUMERIC(14,2) NOT NULL DEFAULT 0,
    due_on               DATE,
    active_ind           BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by           VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by           VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on           TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on           TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_payment_milestone PRIMARY KEY (payment_milestone_id),
    CONSTRAINT fk_pm_inv FOREIGN KEY (invoice_id) REFERENCES solar_app.invoice_details (invoice_id) ON DELETE CASCADE,
    CONSTRAINT uq_pm_seq UNIQUE (invoice_id, sequence_no),
    CONSTRAINT chk_pm_pct CHECK (percent_share IS NULL OR (percent_share >= 0 AND percent_share <= 100)),
    CONSTRAINT chk_pm_amt CHECK (due_amount >= 0 AND paid_amount >= 0)
);
COMMENT ON TABLE solar_app.payment_milestone_details IS 'Agreed offline instalment split recorded after collection (not an EMI gateway).';
COMMENT ON COLUMN solar_app.payment_milestone_details.payment_milestone_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.payment_milestone_details.invoice_id IS 'Parent offline bill.';
COMMENT ON COLUMN solar_app.payment_milestone_details.sequence_no IS 'Instalment sequence (e.g. 1=20%, 2=70%, 3=10%).';
COMMENT ON COLUMN solar_app.payment_milestone_details.percent_share IS 'Agreed percent of the bill for this split.';
COMMENT ON COLUMN solar_app.payment_milestone_details.due_amount IS 'Amount expected for this split.';
COMMENT ON COLUMN solar_app.payment_milestone_details.paid_amount IS 'Amount recorded against this split.';
COMMENT ON COLUMN solar_app.payment_milestone_details.due_on IS 'Agreed due date; not an in-app collection date.';
COMMENT ON COLUMN solar_app.payment_milestone_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.payment_milestone_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.payment_milestone_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.payment_milestone_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.payment_milestone_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

ALTER TABLE solar_app.service_milestone_details
    ADD CONSTRAINT fk_ms_sr FOREIGN KEY (service_request_id) REFERENCES solar_app.service_request_details (service_request_id) ON DELETE SET NULL;

CREATE TABLE solar_app.order_details (
    order_id                 BIGINT GENERATED ALWAYS AS IDENTITY,
    order_no                 VARCHAR(30)   NOT NULL,
    order_source             VARCHAR(20)   NOT NULL,
    customer_id              BIGINT        NOT NULL,
    site_id                  BIGINT,
    user_id                  BIGINT,
    quote_id                 BIGINT,
    product_enquiry_id       BIGINT,
    lead_id                  BIGINT,
    order_status_ref_data_id BIGINT        NOT NULL,
    assigned_admin_user_id   BIGINT,
    gross_amount             NUMERIC(14,2) NOT NULL DEFAULT 0,
    currency_code            CHAR(3)       NOT NULL,
    remarks                  VARCHAR(500),
    active_ind               BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by               VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by               VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_order_details PRIMARY KEY (order_id),
    CONSTRAINT uq_order_details_no UNIQUE (order_no),
    CONSTRAINT chk_order_source CHECK (order_source IN ('QUOTE', 'ENQUIRY', 'LEAD', 'MANUAL')),
    CONSTRAINT fk_order_customer FOREIGN KEY (customer_id) REFERENCES solar_app.customer_details (customer_id) ON DELETE RESTRICT,
    CONSTRAINT fk_order_site FOREIGN KEY (site_id) REFERENCES solar_app.site_details (site_id) ON DELETE RESTRICT,
    CONSTRAINT fk_order_user FOREIGN KEY (user_id) REFERENCES solar_app.user_details (user_id) ON DELETE SET NULL,
    CONSTRAINT fk_order_quote FOREIGN KEY (quote_id) REFERENCES solar_app.quote_details (quote_id) ON DELETE RESTRICT,
    CONSTRAINT fk_order_enquiry FOREIGN KEY (product_enquiry_id) REFERENCES solar_app.product_enquiry_details (product_enquiry_id) ON DELETE SET NULL,
    CONSTRAINT fk_order_lead FOREIGN KEY (lead_id) REFERENCES solar_app.lead_details (lead_id) ON DELETE SET NULL,
    CONSTRAINT fk_order_status FOREIGN KEY (order_status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_order_admin FOREIGN KEY (assigned_admin_user_id) REFERENCES solar_app.user_details (user_id) ON DELETE SET NULL,
    CONSTRAINT fk_order_currency FOREIGN KEY (currency_code) REFERENCES solar_app.ref_currencies (currency_code) ON DELETE RESTRICT
);
COMMENT ON TABLE solar_app.order_details IS 'Commercial fulfilment order through installation (Path A) or already-commissioned (Path B). Distinct from bills and equipment.';
COMMENT ON COLUMN solar_app.order_details.order_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.order_details.order_no IS 'Human-readable unique order number.';
COMMENT ON COLUMN solar_app.order_details.order_source IS 'QUOTE, ENQUIRY, LEAD, or MANUAL (Path B / admin).';
COMMENT ON COLUMN solar_app.order_details.customer_id IS 'Fulfilment customer.';
COMMENT ON COLUMN solar_app.order_details.site_id IS 'Install site when known.';
COMMENT ON COLUMN solar_app.order_details.user_id IS 'End user who originated demand, if any.';
COMMENT ON COLUMN solar_app.order_details.quote_id IS 'Accepted quote, if any.';
COMMENT ON COLUMN solar_app.order_details.product_enquiry_id IS 'Source catalogue enquiry, if any.';
COMMENT ON COLUMN solar_app.order_details.lead_id IS 'Source lead, if any.';
COMMENT ON COLUMN solar_app.order_details.order_status_ref_data_id IS 'FK to ORDER_STATUSES through installation/commissioning.';
COMMENT ON COLUMN solar_app.order_details.assigned_admin_user_id IS 'Back-office owner.';
COMMENT ON COLUMN solar_app.order_details.gross_amount IS 'Sum of lines as computed in functions.';
COMMENT ON COLUMN solar_app.order_details.currency_code IS 'Currency snapshot for order amounts and lines.';
COMMENT ON COLUMN solar_app.order_details.remarks IS 'Admin notes.';
COMMENT ON COLUMN solar_app.order_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.order_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.order_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.order_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.order_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_order_customer ON solar_app.order_details (customer_id, created_on DESC);
CREATE INDEX idx_order_status ON solar_app.order_details (order_status_ref_data_id, active_ind);

CREATE TABLE solar_app.order_line_details (
    order_line_id BIGINT GENERATED ALWAYS AS IDENTITY,
    order_id      BIGINT        NOT NULL,
    line_no       INTEGER       NOT NULL,
    product_id    BIGINT,
    line_desc     VARCHAR(255)  NOT NULL,
    tax_classification_code VARCHAR(30),
    quantity      NUMERIC(12,3) NOT NULL DEFAULT 1,
    unit_rate     NUMERIC(12,2) NOT NULL DEFAULT 0,
    line_amount   NUMERIC(14,2) NOT NULL,
    active_ind    BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by    VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by    VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on    TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on    TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_order_line_details PRIMARY KEY (order_line_id),
    CONSTRAINT fk_order_line_hdr FOREIGN KEY (order_id) REFERENCES solar_app.order_details (order_id) ON DELETE CASCADE,
    CONSTRAINT fk_order_line_product FOREIGN KEY (product_id) REFERENCES solar_app.product_details (product_id) ON DELETE RESTRICT,
    CONSTRAINT uq_order_line_no UNIQUE (order_id, line_no),
    CONSTRAINT chk_order_line_qty CHECK (quantity > 0)
);
COMMENT ON TABLE solar_app.order_line_details IS 'Order line: catalogue product and/or free-text kit description.';
COMMENT ON COLUMN solar_app.order_line_details.order_line_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.order_line_details.order_id IS 'Parent order.';
COMMENT ON COLUMN solar_app.order_line_details.line_no IS 'Line sequence unique per order.';
COMMENT ON COLUMN solar_app.order_line_details.product_id IS 'Optional catalogue SKU.';
COMMENT ON COLUMN solar_app.order_line_details.line_desc IS 'Line description (required even when product_id is set).';
COMMENT ON COLUMN solar_app.order_line_details.tax_classification_code IS 'Optional country-specific tax classification code snapshot.';
COMMENT ON COLUMN solar_app.order_line_details.quantity IS 'Quantity (must be > 0).';
COMMENT ON COLUMN solar_app.order_line_details.unit_rate IS 'Rate per unit.';
COMMENT ON COLUMN solar_app.order_line_details.line_amount IS 'Line amount.';
COMMENT ON COLUMN solar_app.order_line_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.order_line_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.order_line_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.order_line_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.order_line_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE TABLE solar_app.followup_details (
    followup_id              BIGINT GENERATED ALWAYS AS IDENTITY,
    entity_type              VARCHAR(30)   NOT NULL,
    lead_id                  BIGINT,
    product_enquiry_id       BIGINT,
    order_id                 BIGINT,
    complaint_ticket_id      BIGINT,
    service_request_id       BIGINT,
    customer_id              BIGINT,
    user_id                  BIGINT,
    followup_type_ref_data_id BIGINT       NOT NULL,
    status_ref_data_id       BIGINT        NOT NULL,
    assigned_to_user_id      BIGINT        NOT NULL,
    due_on                   TIMESTAMPTZ   NOT NULL,
    completed_on             TIMESTAMPTZ,
    notes                    VARCHAR(1000),
    outcome_notes            VARCHAR(1000),
    active_ind               BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by               VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    updated_by               VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    created_on               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on               TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_followup_details PRIMARY KEY (followup_id),
    CONSTRAINT chk_followup_entity_type CHECK (entity_type IN ('LEAD', 'ENQUIRY', 'ORDER', 'TICKET', 'SERVICE_REQUEST', 'CUSTOMER', 'USER')),
    CONSTRAINT chk_followup_one_parent CHECK (
        (entity_type = 'LEAD' AND lead_id IS NOT NULL)
        OR (entity_type = 'ENQUIRY' AND product_enquiry_id IS NOT NULL)
        OR (entity_type = 'ORDER' AND order_id IS NOT NULL)
        OR (entity_type = 'TICKET' AND complaint_ticket_id IS NOT NULL)
        OR (entity_type = 'SERVICE_REQUEST' AND service_request_id IS NOT NULL)
        OR (entity_type = 'CUSTOMER' AND customer_id IS NOT NULL)
        OR (entity_type = 'USER' AND user_id IS NOT NULL)
    ),
    CONSTRAINT fk_fu_lead FOREIGN KEY (lead_id) REFERENCES solar_app.lead_details (lead_id) ON DELETE CASCADE,
    CONSTRAINT fk_fu_enquiry FOREIGN KEY (product_enquiry_id) REFERENCES solar_app.product_enquiry_details (product_enquiry_id) ON DELETE CASCADE,
    CONSTRAINT fk_fu_order FOREIGN KEY (order_id) REFERENCES solar_app.order_details (order_id) ON DELETE CASCADE,
    CONSTRAINT fk_fu_ticket FOREIGN KEY (complaint_ticket_id) REFERENCES solar_app.complaint_ticket_details (complaint_ticket_id) ON DELETE CASCADE,
    CONSTRAINT fk_fu_svc FOREIGN KEY (service_request_id) REFERENCES solar_app.service_request_details (service_request_id) ON DELETE CASCADE,
    CONSTRAINT fk_fu_customer FOREIGN KEY (customer_id) REFERENCES solar_app.customer_details (customer_id) ON DELETE CASCADE,
    CONSTRAINT fk_fu_user FOREIGN KEY (user_id) REFERENCES solar_app.user_details (user_id) ON DELETE CASCADE,
    CONSTRAINT fk_fu_type FOREIGN KEY (followup_type_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_fu_status FOREIGN KEY (status_ref_data_id) REFERENCES solar_app.ref_data (ref_data_id) ON DELETE RESTRICT,
    CONSTRAINT fk_fu_assignee FOREIGN KEY (assigned_to_user_id) REFERENCES solar_app.user_details (user_id) ON DELETE RESTRICT
);
COMMENT ON TABLE solar_app.followup_details IS 'Scheduled admin/sales follow-up against exactly one parent entity (lead, enquiry, order, ticket, etc.).';
COMMENT ON COLUMN solar_app.followup_details.followup_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.followup_details.entity_type IS 'Which parent FK is populated: LEAD, ENQUIRY, ORDER, TICKET, SERVICE_REQUEST, CUSTOMER, USER.';
COMMENT ON COLUMN solar_app.followup_details.lead_id IS 'Parent lead when entity_type is LEAD.';
COMMENT ON COLUMN solar_app.followup_details.product_enquiry_id IS 'Parent enquiry when entity_type is ENQUIRY.';
COMMENT ON COLUMN solar_app.followup_details.order_id IS 'Parent order when entity_type is ORDER.';
COMMENT ON COLUMN solar_app.followup_details.complaint_ticket_id IS 'Parent ticket when entity_type is TICKET.';
COMMENT ON COLUMN solar_app.followup_details.service_request_id IS 'Parent service request when entity_type is SERVICE_REQUEST.';
COMMENT ON COLUMN solar_app.followup_details.customer_id IS 'Parent customer when entity_type is CUSTOMER.';
COMMENT ON COLUMN solar_app.followup_details.user_id IS 'Parent user when entity_type is USER.';
COMMENT ON COLUMN solar_app.followup_details.followup_type_ref_data_id IS 'FK to FOLLOWUP_TYPES (call, visit, WhatsApp, email).';
COMMENT ON COLUMN solar_app.followup_details.status_ref_data_id IS 'FK to FOLLOWUP_STATUSES (open, done, cancelled).';
COMMENT ON COLUMN solar_app.followup_details.assigned_to_user_id IS 'Admin or sales owner of the task.';
COMMENT ON COLUMN solar_app.followup_details.due_on IS 'When the follow-up is due.';
COMMENT ON COLUMN solar_app.followup_details.completed_on IS 'When the task was completed.';
COMMENT ON COLUMN solar_app.followup_details.notes IS 'Instructions for the assignee.';
COMMENT ON COLUMN solar_app.followup_details.outcome_notes IS 'Result logged when completing the task.';
COMMENT ON COLUMN solar_app.followup_details.active_ind IS 'Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.followup_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.followup_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.followup_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.followup_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';
CREATE INDEX idx_followup_assignee_due ON solar_app.followup_details (assigned_to_user_id, due_on) WHERE active_ind = TRUE;
CREATE INDEX idx_followup_status ON solar_app.followup_details (status_ref_data_id, due_on);

-- Deferred FKs (child tables created before these parents, or circular)
ALTER TABLE solar_app.invoice_details
    ADD CONSTRAINT fk_inv_order FOREIGN KEY (related_order_id) REFERENCES solar_app.order_details (order_id) ON DELETE SET NULL;
ALTER TABLE solar_app.site_details
    ADD CONSTRAINT fk_site_order FOREIGN KEY (order_id) REFERENCES solar_app.order_details (order_id) ON DELETE SET NULL;
ALTER TABLE solar_app.amc_contract_details
    ADD CONSTRAINT fk_amc_order FOREIGN KEY (order_id) REFERENCES solar_app.order_details (order_id) ON DELETE SET NULL;
ALTER TABLE solar_app.amc_contract_details
    ADD CONSTRAINT fk_amc_invoice FOREIGN KEY (invoice_id) REFERENCES solar_app.invoice_details (invoice_id) ON DELETE SET NULL;
ALTER TABLE solar_app.service_request_details
    ADD CONSTRAINT fk_svc_req_order FOREIGN KEY (order_id) REFERENCES solar_app.order_details (order_id) ON DELETE SET NULL;
ALTER TABLE solar_app.site_visit_details
    ADD CONSTRAINT fk_sv_enquiry FOREIGN KEY (product_enquiry_id) REFERENCES solar_app.product_enquiry_details (product_enquiry_id) ON DELETE SET NULL;
ALTER TABLE solar_app.site_visit_details
    ADD CONSTRAINT fk_sv_customer FOREIGN KEY (customer_id) REFERENCES solar_app.customer_details (customer_id) ON DELETE SET NULL;
ALTER TABLE solar_app.site_visit_details
    ADD CONSTRAINT fk_sv_site FOREIGN KEY (site_id) REFERENCES solar_app.site_details (site_id) ON DELETE SET NULL;
ALTER TABLE solar_app.site_visit_details
    ADD CONSTRAINT fk_sv_order FOREIGN KEY (order_id) REFERENCES solar_app.order_details (order_id) ON DELETE SET NULL;
ALTER TABLE solar_app.site_visit_details
    ADD CONSTRAINT fk_sv_sr FOREIGN KEY (service_request_id) REFERENCES solar_app.service_request_details (service_request_id) ON DELETE SET NULL;
ALTER TABLE solar_app.site_visit_details
    ADD CONSTRAINT fk_sv_ms FOREIGN KEY (service_milestone_id) REFERENCES solar_app.service_milestone_details (service_milestone_id) ON DELETE SET NULL;
ALTER TABLE solar_app.site_visit_details
    ADD CONSTRAINT fk_sv_ticket FOREIGN KEY (complaint_ticket_id) REFERENCES solar_app.complaint_ticket_details (complaint_ticket_id) ON DELETE SET NULL;
ALTER TABLE solar_app.site_visit_details
    ADD CONSTRAINT fk_sv_amc FOREIGN KEY (amc_contract_id) REFERENCES solar_app.amc_contract_details (amc_contract_id) ON DELETE SET NULL;
ALTER TABLE solar_app.site_visit_details
    ADD CONSTRAINT fk_sv_invoice FOREIGN KEY (invoice_id) REFERENCES solar_app.invoice_details (invoice_id) ON DELETE SET NULL;
ALTER TABLE solar_app.site_visit_details
    ADD CONSTRAINT fk_sv_payment FOREIGN KEY (payment_id) REFERENCES solar_app.payment_details (payment_id) ON DELETE SET NULL;
