-- Concurrent duplicate Path B registration race on SolarDB_restore_check only.
\set ON_ERROR_STOP on

DO $$
BEGIN
    IF current_database() IS DISTINCT FROM 'SolarDB_restore_check' THEN
        RAISE EXCEPTION 'Refuse concurrent Path B IT on %', current_database();
    END IF;
END $$;

DO $$
DECLARE
    v_role_admin BIGINT;
    v_acct_active BIGINT;
    v_reg_self BIGINT;
    v_admin_id BIGINT;
    v_admin_hash TEXT := 'aa11bb22cc33dd44ee55ff6677889900aaaabbbbccccddddeeeeffff00003333';
    v_payload JSONB;
BEGIN
    DELETE FROM solar_app.notification_details
     WHERE recipient_user_id IN (SELECT user_id FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990012%');
    DELETE FROM solar_app.order_line_details
     WHERE order_id IN (SELECT order_id FROM solar_app.order_details WHERE order_no LIKE 'PATHB-CON-%');
    DELETE FROM solar_app.order_details WHERE order_no LIKE 'PATHB-CON-%';
    DELETE FROM solar_app.equipment_details
     WHERE site_id IN (
            SELECT site_id FROM solar_app.site_details
             WHERE customer_id IN (SELECT customer_id FROM solar_app.customer_details WHERE customer_code LIKE 'PATHB-CON-%')
          );
    DELETE FROM solar_app.user_site_access_details
     WHERE user_id IN (SELECT user_id FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990012%');
    DELETE FROM solar_app.site_details
     WHERE customer_id IN (SELECT customer_id FROM solar_app.customer_details WHERE customer_code LIKE 'PATHB-CON-%');
    DELETE FROM solar_app.customer_details WHERE customer_code LIKE 'PATHB-CON-%';
    DELETE FROM solar_app.log_user_sessions WHERE jwt_token_hash = v_admin_hash OR mobile_e164 LIKE '+91990012%';
    DELETE FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990012%' OR created_by = 'PATHB_CON';

    SELECT r.ref_data_id INTO v_role_admin
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'USER_ROLES' AND r.data_code = 'ROLE_ADMIN';
    SELECT r.ref_data_id INTO v_acct_active
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'USER_ACCOUNT_STATUSES' AND r.data_code = 'ACCT_ACTIVE';
    SELECT r.ref_data_id INTO v_reg_self
      FROM solar_app.ref_data r
      JOIN solar_app.ref_data_categories c ON c.category_id = r.category_id
     WHERE c.category_code = 'REGISTRATION_SOURCES' AND r.data_code = 'REG_SELF_APP';

    INSERT INTO solar_app.user_details (
        country_id, mobile_e164, full_name, role_ref_data_id, pin_hash,
        admin_registered, account_status_ref_data_id, registration_source_ref_data_id,
        created_by, updated_by
    ) VALUES (
        1, '+919900120001', 'PATHB CON Admin', v_role_admin, NULL,
        TRUE, v_acct_active, v_reg_self, 'PATHB_CON', 'PATHB_CON'
    ) RETURNING user_id INTO v_admin_id;

    INSERT INTO solar_app.log_user_sessions (
        user_id, mobile_e164, jwt_token_hash, session_status, active_ind, created_by, updated_by
    ) VALUES (
        v_admin_id, '+919900120001', v_admin_hash, 'ACTIVE', TRUE, 'PATHB_CON', 'PATHB_CON'
    );

    -- Seed marker table for worker results
    CREATE TEMP TABLE pathb_con_results (
        worker TEXT PRIMARY KEY,
        status TEXT,
        code INTEGER,
        message TEXT
    ) ON COMMIT PRESERVE ROWS;
END $$;
