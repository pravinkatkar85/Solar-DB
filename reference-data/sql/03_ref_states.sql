-- Auto-generated. Do not edit by hand; re-run generate-reference-data.mjs
SET search_path TO solar_app, public;

INSERT INTO solar_app.ref_states (state_id, country_id, state_code, state_name, tax_region_code, active_ind, created_by, updated_by)
OVERRIDING SYSTEM VALUE
VALUES
  (1, 1, 'AN', 'Andaman and Nicobar Islands', '35', TRUE, 'SYSTEM', 'SYSTEM'),
  (2, 1, 'AP', 'Andhra Pradesh', '37', TRUE, 'SYSTEM', 'SYSTEM'),
  (3, 1, 'AR', 'Arunachal Pradesh', '12', TRUE, 'SYSTEM', 'SYSTEM'),
  (4, 1, 'AS', 'Assam', '18', TRUE, 'SYSTEM', 'SYSTEM'),
  (5, 1, 'BR', 'Bihar', '10', TRUE, 'SYSTEM', 'SYSTEM'),
  (6, 1, 'CH', 'Chandigarh', '04', TRUE, 'SYSTEM', 'SYSTEM'),
  (7, 1, 'CG', 'Chhattisgarh', '22', TRUE, 'SYSTEM', 'SYSTEM'),
  (8, 1, 'DH', 'Dadra and Nagar Haveli and Daman and Diu', '26', TRUE, 'SYSTEM', 'SYSTEM'),
  (9, 1, 'DL', 'Delhi', '07', TRUE, 'SYSTEM', 'SYSTEM'),
  (10, 1, 'GA', 'Goa', '30', TRUE, 'SYSTEM', 'SYSTEM'),
  (11, 1, 'GJ', 'Gujarat', '24', TRUE, 'SYSTEM', 'SYSTEM'),
  (12, 1, 'HR', 'Haryana', '06', TRUE, 'SYSTEM', 'SYSTEM'),
  (13, 1, 'HP', 'Himachal Pradesh', '02', TRUE, 'SYSTEM', 'SYSTEM'),
  (14, 1, 'JK', 'Jammu and Kashmir', '01', TRUE, 'SYSTEM', 'SYSTEM'),
  (15, 1, 'JH', 'Jharkhand', '20', TRUE, 'SYSTEM', 'SYSTEM'),
  (16, 1, 'KA', 'Karnataka', '29', TRUE, 'SYSTEM', 'SYSTEM'),
  (17, 1, 'KL', 'Kerala', '32', TRUE, 'SYSTEM', 'SYSTEM'),
  (18, 1, 'LA', 'Ladakh', '38', TRUE, 'SYSTEM', 'SYSTEM'),
  (19, 1, 'LD', 'Lakshadweep', '31', TRUE, 'SYSTEM', 'SYSTEM'),
  (20, 1, 'MP', 'Madhya Pradesh', '23', TRUE, 'SYSTEM', 'SYSTEM'),
  (21, 1, 'MH', 'Maharashtra', '27', TRUE, 'SYSTEM', 'SYSTEM'),
  (22, 1, 'MN', 'Manipur', '14', TRUE, 'SYSTEM', 'SYSTEM'),
  (23, 1, 'ML', 'Meghalaya', '17', TRUE, 'SYSTEM', 'SYSTEM'),
  (24, 1, 'MZ', 'Mizoram', '15', TRUE, 'SYSTEM', 'SYSTEM'),
  (25, 1, 'NL', 'Nagaland', '13', TRUE, 'SYSTEM', 'SYSTEM'),
  (26, 1, 'OD', 'Odisha', '21', TRUE, 'SYSTEM', 'SYSTEM'),
  (27, 1, 'PY', 'Puducherry', '34', TRUE, 'SYSTEM', 'SYSTEM'),
  (28, 1, 'PB', 'Punjab', '03', TRUE, 'SYSTEM', 'SYSTEM'),
  (29, 1, 'RJ', 'Rajasthan', '08', TRUE, 'SYSTEM', 'SYSTEM'),
  (30, 1, 'SK', 'Sikkim', '11', TRUE, 'SYSTEM', 'SYSTEM'),
  (31, 1, 'TN', 'Tamil Nadu', '33', TRUE, 'SYSTEM', 'SYSTEM'),
  (32, 1, 'TS', 'Telangana', '36', TRUE, 'SYSTEM', 'SYSTEM'),
  (33, 1, 'TR', 'Tripura', '16', TRUE, 'SYSTEM', 'SYSTEM'),
  (34, 1, 'UP', 'Uttar Pradesh', '09', TRUE, 'SYSTEM', 'SYSTEM'),
  (35, 1, 'UK', 'Uttarakhand', '05', TRUE, 'SYSTEM', 'SYSTEM'),
  (36, 1, 'WB', 'West Bengal', '19', TRUE, 'SYSTEM', 'SYSTEM')
ON CONFLICT (state_id) DO UPDATE SET
  country_id = EXCLUDED.country_id,
  state_code = EXCLUDED.state_code,
  state_name = EXCLUDED.state_name,
  tax_region_code = EXCLUDED.tax_region_code,
  active_ind = EXCLUDED.active_ind,
  updated_by = EXCLUDED.updated_by,
  updated_on = CURRENT_TIMESTAMP;

SELECT setval(
  pg_get_serial_sequence('solar_app.ref_states', 'state_id'),
  COALESCE((SELECT MAX(state_id) FROM solar_app.ref_states), 1),
  EXISTS (SELECT 1 FROM solar_app.ref_states)
);
