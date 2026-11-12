\set ON_ERROR_STOP on
-- Usage: psql ... -v worker=A -v custcode=PATHB-CON-A -v orderno=PATHB-CON-ORD-A -f ...
SELECT solar_app.fn_create_user_details(jsonb_build_object(
  'api_endpoint', '/api/admin/customers/create',
  'jwt_token_hash', 'aa11bb22cc33dd44ee55ff6677889900aaaabbbbccccddddeeeeffff00003333',
  'country_id', '1',
  'national_number', '9900120099',
  'full_name', 'PATHB Concurrent Customer',
  'customer_code', :'custcode',
  'order_no', :'orderno',
  'order_status_code', 'ORD_INSTALLED',
  'currency_code', 'INR',
  'sites', jsonb_build_array(jsonb_build_object(
    'site_name', 'PATHB Concurrent Site',
    'address_line1', '9 Race Road',
    'installation_status_code', 'INST_INSTALLED',
    'commissioning_on', '2026-02-01',
    'equipment', jsonb_build_array(jsonb_build_object(
      'equipment_type_code', 'EQ_PANEL',
      'quantity', '1'
    ))
  ))
)) AS response;
