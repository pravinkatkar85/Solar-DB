-- Auto-generated. Do not edit by hand; re-run generate-reference-data.mjs
SET search_path TO solar_app, public;

INSERT INTO solar_app.ref_data_categories (category_id, category_code, category_name, category_desc, sort_order, active_ind, created_by, updated_by)
OVERRIDING SYSTEM VALUE
VALUES
  (1, 'USER_ROLES', 'User Roles', 'App personas', 1, TRUE, 'SYSTEM', 'SYSTEM'),
  (2, 'APP_LANGUAGES', 'App Languages', 'UI language', 2, TRUE, 'SYSTEM', 'SYSTEM'),
  (3, 'CONNECTION_TYPES', 'Connection Types', 'DISCOM connection class', 3, TRUE, 'SYSTEM', 'SYSTEM'),
  (4, 'LEAD_STATUSES', 'Lead Statuses', 'Sales pipeline', 4, TRUE, 'SYSTEM', 'SYSTEM'),
  (5, 'QUOTE_STATUSES', 'Quote Statuses', 'Quotation lifecycle', 5, TRUE, 'SYSTEM', 'SYSTEM'),
  (6, 'SITE_VISIT_STATUSES', 'Site Visit Statuses', 'Scheduled through done / charges', 6, TRUE, 'SYSTEM', 'SYSTEM'),
  (7, 'SITE_VISIT_PURPOSES', 'Site Visit Purposes', 'Enquiry, installation, service, complaint, commissioning', 7, TRUE, 'SYSTEM', 'SYSTEM'),
  (8, 'DOCUMENT_TYPES', 'KYC Document Types', 'Onboarding checklist', 8, TRUE, 'SYSTEM', 'SYSTEM'),
  (9, 'DOCUMENT_VERIFICATION_STATUSES', 'Document Verification Statuses', 'Admin review badge', 9, TRUE, 'SYSTEM', 'SYSTEM'),
  (10, 'EQUIPMENT_TYPES', 'Equipment Types', 'Asset register class', 10, TRUE, 'SYSTEM', 'SYSTEM'),
  (11, 'EQUIPMENT_BRANDS', 'Equipment Brands', 'Panel/inverter/battery brands', 11, TRUE, 'SYSTEM', 'SYSTEM'),
  (12, 'PHASE_TYPES', 'Phase Types', 'Inverter/connection phase', 12, TRUE, 'SYSTEM', 'SYSTEM'),
  (13, 'STRUCTURE_TYPES', 'Structure Types', 'Mounting structure', 13, TRUE, 'SYSTEM', 'SYSTEM'),
  (14, 'WARRANTY_TYPES', 'Warranty Types', 'Warranty vault', 14, TRUE, 'SYSTEM', 'SYSTEM'),
  (15, 'SERVICE_TYPES', 'Service Types', 'Preventive service booking', 15, TRUE, 'SYSTEM', 'SYSTEM'),
  (16, 'SERVICE_SLOT_WINDOWS', 'Service Slot Windows', 'Morning/afternoon', 16, TRUE, 'SYSTEM', 'SYSTEM'),
  (17, 'SERVICE_REQUEST_STATUSES', 'Service Request Statuses', 'AMC/cleaning request', 17, TRUE, 'SYSTEM', 'SYSTEM'),
  (18, 'MILESTONE_STATUSES', 'Free Service Milestone Statuses', 'Quarterly free visits', 18, TRUE, 'SYSTEM', 'SYSTEM'),
  (19, 'COMPLAINT_CATEGORIES', 'Complaint Categories', 'Ticket issue class', 19, TRUE, 'SYSTEM', 'SYSTEM'),
  (20, 'COMPLAINT_SEVERITIES', 'Complaint Severities', 'Priority', 20, TRUE, 'SYSTEM', 'SYSTEM'),
  (21, 'TICKET_STATUSES', 'Ticket Statuses', 'Complaint stepper', 21, TRUE, 'SYSTEM', 'SYSTEM'),
  (22, 'JOB_STATUSES', 'Job Assignment Statuses', 'Technician queue', 22, TRUE, 'SYSTEM', 'SYSTEM'),
  (23, 'INVOICE_CATEGORIES', 'Invoice Categories', 'Offline bill type (installation, AMC, spares, cleaning)', 23, TRUE, 'SYSTEM', 'SYSTEM'),
  (24, 'INVOICE_STATUSES', 'Invoice Statuses', 'Offline bill AR status', 24, TRUE, 'SYSTEM', 'SYSTEM'),
  (25, 'PAYMENT_METHODS', 'Payment Methods', 'Offline collection methods (no in-app gateway)', 25, TRUE, 'SYSTEM', 'SYSTEM'),
  (26, 'PAYMENT_STATUSES', 'Payment Statuses', 'Offline payment record status', 26, TRUE, 'SYSTEM', 'SYSTEM'),
  (27, 'INSTALLATION_STATUSES', 'Installation Statuses', 'Site pipeline', 27, TRUE, 'SYSTEM', 'SYSTEM'),
  (28, 'SITE_ACCESS_ROLES', 'Site Access Roles', 'Multi-property access', 28, TRUE, 'SYSTEM', 'SYSTEM'),
  (29, 'PRODUCT_CATEGORIES', 'Product Catalogue Categories', 'Sellable/related SKU class', 29, TRUE, 'SYSTEM', 'SYSTEM'),
  (30, 'PRODUCT_ENQUIRY_STATUSES', 'Product Enquiry Statuses', 'Catalogue enquiry pipeline', 30, TRUE, 'SYSTEM', 'SYSTEM'),
  (31, 'USER_ACCOUNT_STATUSES', 'User Account Statuses', 'Admin suspend/activate', 31, TRUE, 'SYSTEM', 'SYSTEM'),
  (32, 'ORDER_STATUSES', 'Order Statuses', 'Admin order fulfilment', 32, TRUE, 'SYSTEM', 'SYSTEM'),
  (33, 'FOLLOWUP_TYPES', 'Follow-up Types', 'Call, visit, WhatsApp, email', 33, TRUE, 'SYSTEM', 'SYSTEM'),
  (34, 'FOLLOWUP_STATUSES', 'Follow-up Statuses', 'Admin task pipeline', 34, TRUE, 'SYSTEM', 'SYSTEM'),
  (35, 'REGISTRATION_SOURCES', 'Registration Sources', 'Path A self-app vs Path B admin post-install', 35, TRUE, 'SYSTEM', 'SYSTEM'),
  (36, 'NOTIFICATION_TYPES', 'Notification Types', 'In-app / push event catalogue', 36, TRUE, 'SYSTEM', 'SYSTEM'),
  (37, 'NOTIFICATION_CHANNELS', 'Notification Channels', 'IN_APP vs PUSH (OTP SMS is separate)', 37, TRUE, 'SYSTEM', 'SYSTEM'),
  (38, 'NOTIFICATION_DELIVERY_STATUSES', 'Notification Delivery Statuses', 'Push send queue', 38, TRUE, 'SYSTEM', 'SYSTEM')
ON CONFLICT (category_id) DO UPDATE SET
  category_code = EXCLUDED.category_code,
  category_name = EXCLUDED.category_name,
  category_desc = EXCLUDED.category_desc,
  sort_order = EXCLUDED.sort_order,
  active_ind = EXCLUDED.active_ind,
  updated_by = EXCLUDED.updated_by,
  updated_on = CURRENT_TIMESTAMP;

SELECT setval(
  pg_get_serial_sequence('solar_app.ref_data_categories', 'category_id'),
  COALESCE((SELECT MAX(category_id) FROM solar_app.ref_data_categories), 1),
  EXISTS (SELECT 1 FROM solar_app.ref_data_categories)
);
