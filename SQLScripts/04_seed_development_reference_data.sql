-- =============================================================================
-- DEVELOPMENT-ONLY REFERENCE DATA
-- =============================================================================
-- Purpose:
--   Populate configurable rules needed to exercise calculator, subsidy, AMC,
--   tax, office-distance, and site-visit charging flows in development.
--
-- Safeguards:
--   * Do not run in production.
--   * All stable codes use the DEV_ prefix where the table has a code column.
--   * Foreign keys are resolved from stable business codes, never assumed IDs.
--   * Existing rows are not updated or overwritten.
--   * Natural-key conflicts are skipped; exclusion/check/FK violations abort
--     and roll back the entire transaction.
--   * Values require the production approvals listed in
--     DB-Docs/REFERENCE_DATA_DEPLOYMENT_CHECKLIST.md.
-- =============================================================================

BEGIN;
SET LOCAL search_path TO solar_app, public;

DO $development_reference_data$
DECLARE
    c_effective_from CONSTANT DATE := DATE '2026-01-01';
    c_seed_actor     CONSTANT VARCHAR(50) := 'DEV_SEED';

    v_country_id          BIGINT;
    v_maharashtra_id      BIGINT;
    v_currency_code       CHAR(3);
    v_connection_type_id  BIGINT;
    v_subsidy_scheme_id   BIGINT;
    v_office_city_id      BIGINT;
    v_office_pincode_id   BIGINT;
    v_make_default_office BOOLEAN;
BEGIN
    -- Required parent masters must already be present in canonical seed data.
    SELECT country_id
      INTO STRICT v_country_id
      FROM solar_app.ref_countries
     WHERE country_code = 'IN'
       AND active_ind = TRUE;

    SELECT state_id
      INTO STRICT v_maharashtra_id
      FROM solar_app.ref_states
     WHERE country_id = v_country_id
       AND state_code = 'MH'
       AND active_ind = TRUE;

    SELECT currency_code
      INTO STRICT v_currency_code
      FROM solar_app.ref_currencies
     WHERE currency_code = 'INR'
       AND active_ind = TRUE;

    -- -------------------------------------------------------------------------
    -- 1. Typed, effective-dated development business parameters.
    -- -------------------------------------------------------------------------
    INSERT INTO solar_app.ref_business_parameters (
        parameter_code,
        parameter_name,
        value_type,
        numeric_value,
        text_value,
        boolean_value,
        json_value,
        parameter_unit,
        parameter_desc,
        admin_manageable_ind,
        effective_from,
        effective_to,
        active_ind,
        created_by,
        updated_by
    )
    SELECT
        sample.parameter_code,
        sample.parameter_name,
        'NUMERIC',
        sample.numeric_value,
        NULL,
        NULL,
        NULL,
        sample.parameter_unit,
        sample.parameter_desc,
        TRUE,
        c_effective_from,
        NULL,
        TRUE,
        c_seed_actor,
        c_seed_actor
    FROM (
        VALUES
            ('DEV_BILL_MIN', 'Development bill slider minimum', 500::NUMERIC, 'INR', 'Development-only calculator lower bound.'),
            ('DEV_BILL_MAX', 'Development bill slider maximum', 1000000::NUMERIC, 'INR', 'Development-only calculator upper bound.'),
            ('DEV_SQFT_PER_KW', 'Development shade-free area per kW', 100::NUMERIC, 'SQFT_PER_KW', 'Development fixture for rooftop-area validation.'),
            ('DEV_COST_PER_KW', 'Development indicative EPC cost per kW', 55000::NUMERIC, 'INR_PER_KW', 'Non-production gross-cost assumption.'),
            ('DEV_TARIFF_PER_KWH', 'Development retail tariff', 9.5::NUMERIC, 'INR_PER_KWH', 'Non-production savings assumption.'),
            ('DEV_CUF', 'Development capacity utilisation factor', 0.18::NUMERIC, 'RATIO', 'Non-production generation assumption.'),
            ('DEV_CO2_KG_PER_KWH', 'Development CO2 factor', 0.82::NUMERIC, 'KG_PER_KWH', 'Non-production emissions factor.'),
            ('DEV_FREE_SVC_VISIT_COUNT', 'Development free-service visit count', 4::NUMERIC, 'COUNT', 'Configurable development default; AMC may override.'),
            ('DEV_FREE_VISIT_RADIUS_KM', 'Development free-visit radius', 10::NUMERIC, 'KM', 'Non-production free-entitlement radius.'),
            ('DEV_SERVICE_CLAIM_WINDOW_DAYS', 'Development service claim window', 30::NUMERIC, 'DAYS', 'Development fixture for milestone lapse testing.'),
            ('DEV_KYC_UPLOAD_MAX_BYTES', 'Development KYC upload limit', 2097152::NUMERIC, 'BYTES', 'Development fixture for the documented 2 MB limit.')
    ) AS sample(parameter_code, parameter_name, numeric_value, parameter_unit, parameter_desc)
    ON CONFLICT (parameter_code, effective_from) DO NOTHING;

    -- -------------------------------------------------------------------------
    -- 2. Development subsidy scheme. Rates and cap are test fixtures only.
    -- -------------------------------------------------------------------------
    INSERT INTO solar_app.ref_subsidy_schemes (
        scheme_code,
        scheme_name,
        country_id,
        state_id,
        calculation_method,
        maximum_benefit_amount,
        currency_code,
        eligibility_json,
        effective_from,
        effective_to,
        active_ind,
        created_by,
        updated_by
    )
    VALUES (
        'DEV_PM_SURYA_RESIDENTIAL',
        'Development Residential Subsidy',
        v_country_id,
        NULL,
        'TIERED_RATE',
        78000,
        v_currency_code,
        jsonb_build_object(
            'environment', 'DEVELOPMENT',
            'connection_type_code', 'CONN_RESIDENTIAL',
            'production_approved', FALSE
        ),
        c_effective_from,
        NULL,
        TRUE,
        c_seed_actor,
        c_seed_actor
    )
    ON CONFLICT (scheme_code, effective_from) DO NOTHING;

    SELECT subsidy_scheme_id
      INTO STRICT v_subsidy_scheme_id
      FROM solar_app.ref_subsidy_schemes
     WHERE scheme_code = 'DEV_PM_SURYA_RESIDENTIAL'
       AND effective_from = c_effective_from
       AND active_ind = TRUE;

    SELECT rd.ref_data_id
      INTO STRICT v_connection_type_id
      FROM solar_app.ref_data rd
      JOIN solar_app.ref_data_categories category
        ON category.category_id = rd.category_id
     WHERE category.category_code = 'CONNECTION_TYPES'
       AND rd.data_code = 'CONN_RESIDENTIAL'
       AND category.active_ind = TRUE
       AND rd.active_ind = TRUE;

    INSERT INTO solar_app.ref_subsidy_slabs (
        subsidy_scheme_id,
        connection_type_ref_data_id,
        min_capacity_kw,
        max_capacity_kw,
        rate_amount,
        rate_percent,
        sort_order,
        active_ind,
        created_by,
        updated_by
    )
    SELECT
        v_subsidy_scheme_id,
        v_connection_type_id,
        sample.min_capacity_kw,
        sample.max_capacity_kw,
        sample.rate_amount,
        NULL,
        sample.sort_order,
        TRUE,
        c_seed_actor,
        c_seed_actor
    FROM (
        VALUES
            (0::NUMERIC, 2::NUMERIC, 30000::NUMERIC, 1),
            (2::NUMERIC, 3::NUMERIC, 18000::NUMERIC, 2)
    ) AS sample(min_capacity_kw, max_capacity_kw, rate_amount, sort_order)
    WHERE NOT EXISTS (
        SELECT 1
          FROM solar_app.ref_subsidy_slabs existing
         WHERE existing.subsidy_scheme_id = v_subsidy_scheme_id
           AND existing.connection_type_ref_data_id = v_connection_type_id
           AND existing.min_capacity_kw = sample.min_capacity_kw
           AND existing.max_capacity_kw IS NOT DISTINCT FROM sample.max_capacity_kw
    );

    -- -------------------------------------------------------------------------
    -- 3. Development AMC plans. plan_price is for the complete term.
    -- -------------------------------------------------------------------------
    INSERT INTO solar_app.ref_amc_plans (
        plan_code,
        plan_name,
        plan_desc,
        duration_months,
        includes_breakdown,
        includes_cleaning,
        free_visit_count,
        free_visit_radius_km,
        plan_price,
        currency_code,
        effective_from,
        effective_to,
        active_ind,
        created_by,
        updated_by
    )
    SELECT
        sample.plan_code,
        sample.plan_name,
        sample.plan_desc,
        sample.duration_months,
        sample.includes_breakdown,
        sample.includes_cleaning,
        sample.free_visit_count,
        sample.free_visit_radius_km,
        sample.plan_price,
        v_currency_code,
        c_effective_from,
        NULL,
        TRUE,
        c_seed_actor,
        c_seed_actor
    FROM (
        VALUES
            ('DEV_AMC_BASIC', 'Development Basic Cleaning', 'Development-only cleaning plan.', 12, FALSE, TRUE, 2, 10::NUMERIC, 4999::NUMERIC),
            ('DEV_AMC_COMPREHENSIVE', 'Development Comprehensive', 'Development-only cleaning and breakdown plan.', 12, TRUE, TRUE, 4, 25::NUMERIC, 9999::NUMERIC),
            ('DEV_AMC_PREMIUM', 'Development Premium 24-Month', 'Development-only 24-month comprehensive plan.', 24, TRUE, TRUE, 8, 50::NUMERIC, 17999::NUMERIC)
    ) AS sample(
        plan_code,
        plan_name,
        plan_desc,
        duration_months,
        includes_breakdown,
        includes_cleaning,
        free_visit_count,
        free_visit_radius_km,
        plan_price
    )
    ON CONFLICT (plan_code, effective_from) DO NOTHING;

    -- -------------------------------------------------------------------------
    -- 4. Development tax components. Selection/grouping is test logic only.
    -- -------------------------------------------------------------------------
    INSERT INTO solar_app.ref_tax_rules (
        tax_rule_code,
        tax_group_code,
        tax_component_code,
        tax_display_name,
        country_id,
        state_id,
        tax_classification_code,
        calculation_method,
        rate_percent,
        rate_amount,
        currency_code,
        priority,
        effective_from,
        effective_to,
        active_ind,
        created_by,
        updated_by
    )
    SELECT
        sample.tax_rule_code,
        sample.tax_group_code,
        sample.tax_component_code,
        sample.tax_display_name,
        v_country_id,
        sample.state_id,
        NULL,
        'PERCENTAGE',
        sample.rate_percent,
        NULL,
        NULL,
        sample.priority,
        c_effective_from,
        NULL,
        TRUE,
        c_seed_actor,
        c_seed_actor
    FROM (
        VALUES
            ('DEV_GST_INTRA_CGST_9', 'DEV_GST_INTRA', 'CGST', 'Development CGST 9%', v_maharashtra_id, 9::NUMERIC, 10),
            ('DEV_GST_INTRA_SGST_9', 'DEV_GST_INTRA', 'SGST', 'Development SGST 9%', v_maharashtra_id, 9::NUMERIC, 20),
            ('DEV_GST_INTER_IGST_18', 'DEV_GST_INTER', 'IGST', 'Development IGST 18%', NULL::BIGINT, 18::NUMERIC, 10)
    ) AS sample(
        tax_rule_code,
        tax_group_code,
        tax_component_code,
        tax_display_name,
        state_id,
        rate_percent,
        priority
    )
    ON CONFLICT (tax_rule_code, effective_from) DO NOTHING;

    -- -------------------------------------------------------------------------
    -- 5. Development office. Resolve the city and pincode as one consistent row.
    -- -------------------------------------------------------------------------
    SELECT city.city_id, pincode.pincode_id
      INTO STRICT v_office_city_id, v_office_pincode_id
      FROM solar_app.ref_pincodes pincode
      JOIN solar_app.ref_cities city
        ON city.city_id = pincode.city_id
      JOIN solar_app.ref_states state
        ON state.state_id = city.state_id
      JOIN solar_app.ref_countries country
        ON country.country_id = state.country_id
     WHERE country.country_code = 'IN'
       AND state.state_code = 'MH'
       AND city.city_name = 'Pune'
       AND pincode.pincode = '411001'
       AND country.active_ind = TRUE
       AND state.active_ind = TRUE
       AND city.active_ind = TRUE
       AND pincode.active_ind = TRUE;

    SELECT NOT EXISTS (
        SELECT 1
          FROM solar_app.ref_office_locations
         WHERE is_default = TRUE
           AND active_ind = TRUE
    )
    INTO v_make_default_office;

    INSERT INTO solar_app.ref_office_locations (
        office_code,
        office_name,
        address_line1,
        address_line2,
        city_id,
        pincode_id,
        latitude,
        longitude,
        is_default,
        active_ind,
        created_by,
        updated_by
    )
    VALUES (
        'DEV_OFFICE_PUNE',
        'Development Office Pune',
        'Development address - not a real company office',
        NULL,
        v_office_city_id,
        v_office_pincode_id,
        18.5204000,
        73.8567000,
        v_make_default_office,
        TRUE,
        c_seed_actor,
        c_seed_actor
    )
    ON CONFLICT (office_code) DO NOTHING;

    -- -------------------------------------------------------------------------
    -- 6. Development general visit-charge bands. NULL purpose = default rule.
    -- -------------------------------------------------------------------------
    INSERT INTO solar_app.ref_visit_charge_slabs (
        visit_purpose_ref_data_id,
        min_distance_km,
        max_distance_km,
        charge_amount,
        currency_code,
        is_free_ind,
        effective_from,
        effective_to,
        sort_order,
        active_ind,
        created_by,
        updated_by
    )
    SELECT
        NULL,
        sample.min_distance_km,
        sample.max_distance_km,
        sample.charge_amount,
        v_currency_code,
        sample.is_free_ind,
        c_effective_from,
        NULL,
        sample.sort_order,
        TRUE,
        c_seed_actor,
        c_seed_actor
    FROM (
        VALUES
            (0::NUMERIC, 10::NUMERIC, 0::NUMERIC, TRUE, 1),
            (10::NUMERIC, 25::NUMERIC, 750::NUMERIC, FALSE, 2),
            (25::NUMERIC, 50::NUMERIC, 1500::NUMERIC, FALSE, 3),
            (50::NUMERIC, NULL::NUMERIC, 3000::NUMERIC, FALSE, 4)
    ) AS sample(min_distance_km, max_distance_km, charge_amount, is_free_ind, sort_order)
    WHERE NOT EXISTS (
        SELECT 1
          FROM solar_app.ref_visit_charge_slabs existing
         WHERE existing.visit_purpose_ref_data_id IS NULL
           AND existing.min_distance_km = sample.min_distance_km
           AND existing.max_distance_km IS NOT DISTINCT FROM sample.max_distance_km
           AND existing.effective_from = c_effective_from
    );

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE EXCEPTION
            'Development reference seed prerequisite is missing or inactive (IN, MH, INR, CONN_RESIDENTIAL, Pune/411001, or inserted DEV scheme).';
    WHEN TOO_MANY_ROWS THEN
        RAISE EXCEPTION
            'Development reference seed prerequisite is ambiguous; expected one active row for each stable business key.';
    WHEN OTHERS THEN
        RAISE NOTICE 'Development reference-data seed failed; the transaction will be rolled back.';
        RAISE;
END;
$development_reference_data$;

COMMIT;

