-- Development fixture only. Not a production seed.
-- Adds two sites and their equipment for each active customer that does not
-- already have those site names. Relationships are resolved by business codes.

BEGIN;

INSERT INTO solar_app.customer_details (
    user_id, customer_code, billing_name, created_by, updated_by
)
SELECT app_user.user_id,
       'CUST-' || lpad(app_user.user_id::TEXT, 8, '0'),
       NULLIF(btrim(app_user.full_name), ''),
       'SYSTEM',
       'SYSTEM'
  FROM solar_app.user_details AS app_user
  JOIN solar_app.ref_data AS role_row
    ON role_row.ref_data_id = app_user.role_ref_data_id
   AND role_row.data_code = 'ROLE_CUSTOMER'
   AND role_row.active_ind IS TRUE
  JOIN solar_app.ref_data_categories AS role_category
    ON role_category.category_id = role_row.category_id
   AND role_category.category_code = 'USER_ROLES'
   AND role_category.active_ind IS TRUE
 WHERE app_user.active_ind IS TRUE
   AND NOT EXISTS (
        SELECT 1
          FROM solar_app.customer_details AS existing
         WHERE existing.user_id = app_user.user_id
   );

INSERT INTO solar_app.site_details (
    customer_id, site_name, address_line1, address_line2,
    pincode_id, city_id, district_id, state_id,
    sanctioned_load_kw, installation_status_ref_data_id, commissioning_on,
    created_by, updated_by
)
SELECT customer.customer_id,
       'Home rooftop',
       '14, Shivaji Nagar',
       'Near the post office',
       place.pincode_id,
       place.city_id,
       place.district_id,
       place.state_id,
       5.000,
       status_row.ref_data_id,
       DATE '2024-11-18',
       'SYSTEM',
       'SYSTEM'
  FROM solar_app.customer_details AS customer
  JOIN LATERAL (
        SELECT pincode.pincode_id, pincode.city_id, pincode.district_id, pincode.state_id
          FROM solar_app.ref_pincodes AS pincode
         WHERE pincode.active_ind IS TRUE
         ORDER BY pincode.pincode_id
         LIMIT 1
       ) AS place ON TRUE
  JOIN solar_app.ref_data AS status_row
    ON status_row.data_code = 'INST_COMMISSIONED'
   AND status_row.active_ind IS TRUE
  JOIN solar_app.ref_data_categories AS status_category
    ON status_category.category_id = status_row.category_id
   AND status_category.category_code = 'INSTALLATION_STATUSES'
   AND status_category.active_ind IS TRUE
 WHERE customer.active_ind IS TRUE
   AND NOT EXISTS (
        SELECT 1
          FROM solar_app.site_details AS existing
         WHERE existing.customer_id = customer.customer_id
           AND existing.site_name = 'Home rooftop'
   );

INSERT INTO solar_app.site_details (
    customer_id, site_name, address_line1,
    pincode_id, city_id, district_id, state_id,
    sanctioned_load_kw, installation_status_ref_data_id,
    created_by, updated_by
)
SELECT customer.customer_id,
       'Farm shed',
       'Survey 42, village road',
       place.pincode_id,
       place.city_id,
       place.district_id,
       place.state_id,
       3.000,
       status_row.ref_data_id,
       'SYSTEM',
       'SYSTEM'
  FROM solar_app.customer_details AS customer
  JOIN LATERAL (
        SELECT pincode.pincode_id, pincode.city_id, pincode.district_id, pincode.state_id
          FROM solar_app.ref_pincodes AS pincode
         WHERE pincode.active_ind IS TRUE
         ORDER BY pincode.pincode_id DESC
         LIMIT 1
       ) AS place ON TRUE
  JOIN solar_app.ref_data AS status_row
    ON status_row.data_code = 'INST_INSTALLED'
   AND status_row.active_ind IS TRUE
  JOIN solar_app.ref_data_categories AS status_category
    ON status_category.category_id = status_row.category_id
   AND status_category.category_code = 'INSTALLATION_STATUSES'
   AND status_category.active_ind IS TRUE
 WHERE customer.active_ind IS TRUE
   AND NOT EXISTS (
        SELECT 1
          FROM solar_app.site_details AS existing
         WHERE existing.customer_id = customer.customer_id
           AND existing.site_name = 'Farm shed'
   );

INSERT INTO solar_app.equipment_details (
    site_id, equipment_type_ref_data_id, model_name, quantity,
    panel_wattage, commissioned_on, created_by, updated_by
)
SELECT site.site_id, type_row.ref_data_id, 'Mono 540', 10, 540, DATE '2024-11-18', 'SYSTEM', 'SYSTEM'
  FROM solar_app.site_details AS site
  JOIN solar_app.ref_data AS type_row
    ON type_row.data_code = 'EQ_PANEL'
   AND type_row.active_ind IS TRUE
  JOIN solar_app.ref_data_categories AS type_category
    ON type_category.category_id = type_row.category_id
   AND type_category.category_code = 'EQUIPMENT_TYPES'
   AND type_category.active_ind IS TRUE
 WHERE site.site_name = 'Home rooftop'
   AND site.active_ind IS TRUE
   AND site.created_by = 'SYSTEM'
   AND NOT EXISTS (
        SELECT 1
          FROM solar_app.equipment_details AS equipment
         WHERE equipment.site_id = site.site_id
           AND equipment.model_name = 'Mono 540'
           AND equipment.active_ind IS TRUE
   );

INSERT INTO solar_app.equipment_details (
    site_id, equipment_type_ref_data_id, model_name, quantity,
    inverter_capacity_kw, commissioned_on, created_by, updated_by
)
SELECT site.site_id, type_row.ref_data_id, 'String inverter 5kW', 1, 5, DATE '2024-11-18', 'SYSTEM', 'SYSTEM'
  FROM solar_app.site_details AS site
  JOIN solar_app.ref_data AS type_row
    ON type_row.data_code = 'EQ_INVERTER'
   AND type_row.active_ind IS TRUE
  JOIN solar_app.ref_data_categories AS type_category
    ON type_category.category_id = type_row.category_id
   AND type_category.category_code = 'EQUIPMENT_TYPES'
   AND type_category.active_ind IS TRUE
 WHERE site.site_name = 'Home rooftop'
   AND site.active_ind IS TRUE
   AND site.created_by = 'SYSTEM'
   AND NOT EXISTS (
        SELECT 1
          FROM solar_app.equipment_details AS equipment
         WHERE equipment.site_id = site.site_id
           AND equipment.model_name = 'String inverter 5kW'
           AND equipment.active_ind IS TRUE
   );

COMMIT;
