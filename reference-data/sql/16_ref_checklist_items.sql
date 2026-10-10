-- Auto-generated. Do not edit by hand; re-run generate-reference-data.mjs
SET search_path TO solar_app, public;

INSERT INTO solar_app.ref_checklist_items (checklist_item_id, job_type, item_code, item_label, expected_value_type, is_mandatory, sort_order, active_ind, created_by, updated_by)
OVERRIDING SYSTEM VALUE
VALUES
  (1, 'SERVICE_REQUEST', 'VOC_ISC', 'Panel VOC / ISC voltage measurement', 'NUMERIC', TRUE, 1, TRUE, 'SYSTEM', 'SYSTEM'),
  (2, 'SERVICE_REQUEST', 'ACDC_EARTH', 'AC/DC distribution box wiring and earthing check', 'BOOLEAN', TRUE, 2, TRUE, 'SYSTEM', 'SYSTEM'),
  (3, 'SERVICE_REQUEST', 'PANEL_CLEAN', 'Physical panel cleaning verification', 'BOOLEAN', TRUE, 3, TRUE, 'SYSTEM', 'SYSTEM'),
  (4, 'SERVICE_REQUEST', 'INV_LOGGER', 'Inverter firmware and Wi-Fi logger check', 'BOOLEAN', TRUE, 4, TRUE, 'SYSTEM', 'SYSTEM'),
  (5, 'COMPLAINT', 'FAULT_CODE', 'Inverter / logger fault code recorded', 'TEXT', TRUE, 5, TRUE, 'SYSTEM', 'SYSTEM'),
  (6, 'COMPLAINT', 'VOC_ISC', 'Panel VOC / ISC voltage measurement', 'NUMERIC', TRUE, 6, TRUE, 'SYSTEM', 'SYSTEM'),
  (7, 'COMPLAINT', 'ACDC_EARTH', 'AC/DC distribution box wiring and earthing check', 'BOOLEAN', TRUE, 7, TRUE, 'SYSTEM', 'SYSTEM'),
  (8, 'COMPLAINT', 'SAFETY', 'Sparking / isolation / safety check', 'BOOLEAN', TRUE, 8, TRUE, 'SYSTEM', 'SYSTEM'),
  (9, 'COMMISSIONING', 'VOC_ISC', 'String VOC / ISC at commissioning', 'NUMERIC', TRUE, 9, TRUE, 'SYSTEM', 'SYSTEM'),
  (10, 'COMMISSIONING', 'INV_COMM', 'Inverter commissioned and generating', 'BOOLEAN', TRUE, 10, TRUE, 'SYSTEM', 'SYSTEM'),
  (11, 'COMMISSIONING', 'DONGLE', 'Monitoring dongle online', 'BOOLEAN', TRUE, 11, TRUE, 'SYSTEM', 'SYSTEM'),
  (12, 'COMMISSIONING', 'EARTH', 'Earthing resistance acceptable', 'BOOLEAN', TRUE, 12, TRUE, 'SYSTEM', 'SYSTEM')
ON CONFLICT (checklist_item_id) DO UPDATE SET
  job_type = EXCLUDED.job_type,
  item_code = EXCLUDED.item_code,
  item_label = EXCLUDED.item_label,
  expected_value_type = EXCLUDED.expected_value_type,
  is_mandatory = EXCLUDED.is_mandatory,
  sort_order = EXCLUDED.sort_order,
  active_ind = EXCLUDED.active_ind,
  updated_by = EXCLUDED.updated_by,
  updated_on = CURRENT_TIMESTAMP;

SELECT setval(
  pg_get_serial_sequence('solar_app.ref_checklist_items', 'checklist_item_id'),
  COALESCE((SELECT MAX(checklist_item_id) FROM solar_app.ref_checklist_items), 1),
  EXISTS (SELECT 1 FROM solar_app.ref_checklist_items)
);
