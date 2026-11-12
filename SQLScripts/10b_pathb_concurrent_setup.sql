\set ON_ERROR_STOP on
DO $$
BEGIN
  IF current_database() IS DISTINCT FROM 'SolarDB_restore_check' THEN
    RAISE EXCEPTION 'Refuse concurrent setup on %', current_database();
  END IF;
END $$;

DELETE FROM solar_app.notification_details
 WHERE recipient_user_id IN (SELECT user_id FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990012%' OR created_by='PATHB_CON');
DELETE FROM solar_app.order_line_details
 WHERE order_id IN (SELECT order_id FROM solar_app.order_details WHERE order_no LIKE 'PATHB-CON-%' OR created_by='PATHB_CON');
DELETE FROM solar_app.order_details WHERE order_no LIKE 'PATHB-CON-%' OR created_by='PATHB_CON';
DELETE FROM solar_app.equipment_details
 WHERE created_by='PATHB_CON'
    OR site_id IN (
         SELECT site_id FROM solar_app.site_details
          WHERE created_by='PATHB_CON'
             OR customer_id IN (SELECT customer_id FROM solar_app.customer_details WHERE customer_code LIKE 'PATHB-CON-%')
       );
DELETE FROM solar_app.user_site_access_details
 WHERE created_by='PATHB_CON'
    OR user_id IN (SELECT user_id FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990012%' OR created_by='PATHB_CON');
DELETE FROM solar_app.site_details
 WHERE created_by='PATHB_CON'
    OR customer_id IN (SELECT customer_id FROM solar_app.customer_details WHERE customer_code LIKE 'PATHB-CON-%');
DELETE FROM solar_app.customer_details WHERE customer_code LIKE 'PATHB-CON-%' OR created_by='PATHB_CON';
DELETE FROM solar_app.log_user_sessions WHERE jwt_token_hash LIKE 'aa11bb22%0000333%' OR mobile_e164 LIKE '+91990012%' OR created_by='PATHB_CON';
DELETE FROM solar_app.user_details WHERE mobile_e164 LIKE '+91990012%' OR created_by='PATHB_CON';

INSERT INTO solar_app.user_details (
  country_id, mobile_e164, full_name, role_ref_data_id, pin_hash,
  admin_registered, account_status_ref_data_id, registration_source_ref_data_id,
  created_by, updated_by
)
SELECT 1, '+919900120001', 'PATHB CON Admin', r.ref_data_id, NULL,
       TRUE, a.ref_data_id, s.ref_data_id, 'PATHB_CON', 'PATHB_CON'
  FROM solar_app.ref_data r
  JOIN solar_app.ref_data_categories rc ON rc.category_id=r.category_id AND rc.category_code='USER_ROLES'
  JOIN solar_app.ref_data a ON a.data_code='ACCT_ACTIVE'
  JOIN solar_app.ref_data_categories ac ON ac.category_id=a.category_id AND ac.category_code='USER_ACCOUNT_STATUSES'
  JOIN solar_app.ref_data s ON s.data_code='REG_SELF_APP'
  JOIN solar_app.ref_data_categories sc ON sc.category_id=s.category_id AND sc.category_code='REGISTRATION_SOURCES'
 WHERE r.data_code='ROLE_ADMIN';

INSERT INTO solar_app.log_user_sessions (
  user_id, mobile_e164, jwt_token_hash, session_status, active_ind, created_by, updated_by
)
SELECT user_id, '+919900120001',
       'aa11bb22cc33dd44ee55ff6677889900aaaabbbbccccddddeeeeffff00003333',
       'ACTIVE', TRUE, 'PATHB_CON', 'PATHB_CON'
  FROM solar_app.user_details WHERE mobile_e164='+919900120001';

SELECT 'PATHB_CON_SETUP_OK' AS status;
