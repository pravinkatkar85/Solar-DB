-- =============================================================================
-- DEVELOPMENT-ONLY CATALOGUE TEST PRODUCTS
-- =============================================================================
-- Purpose:
--   Insert 45 identifiable TEST catalogue products so published-list,
--   unpublished, inactive, sort order, category, detail, and media behaviour
--   can be exercised. There is no offer or discount column on
--   product_details; list_price is the only price field.
--
-- Distribution:
--   CAT_PANEL 10, CAT_INVERTER 8, CAT_STRUCTURE 5, CAT_BATTERY 6,
--   CAT_BOS 4, CAT_ACCESSORY 5, CAT_AMC_ADDON 4, CAT_OTHER 3.
--   36 active published, 6 active unpublished, 3 inactive.
--   Brand and capacity are stored in the existing specs_json field.
--   Published rows also get one PHOTO media row. Image files live in
--   Solar-API/media/catalogue/ and the stored path is /media/catalogue/<code>.jpg.
--
-- Safeguards:
--   * Development only. Do not run in production.
--   * Product codes use the TEST-CAT- prefix. created_by is DEV_SEED.
--   * Category and INR currency are resolved by stable codes, not assumed IDs.
--   * Existing product_code rows are left unchanged.
--   * The transaction aborts unless exactly 45 DEV_SEED TEST-CAT products exist
--     after the insert.
--
-- Run from Solar-DB:
--   psql -U solar_app_user -d SolarDB -h 127.0.0.1 -v ON_ERROR_STOP=1 -f SQLScripts/07_seed_catalogue_test_products.sql
-- =============================================================================

BEGIN;
SET LOCAL search_path TO solar_app, public;

INSERT INTO solar_app.product_details (
    product_code,
    product_name,
    category_ref_data_id,
    short_description,
    long_description,
    specs_json,
    list_price,
    currency_code,
    thumbnail_url,
    is_published,
    published_on,
    sort_order,
    active_ind,
    created_by,
    updated_by
)
SELECT
    seed.product_code,
    seed.product_name,
    category.ref_data_id,
    seed.short_description,
    seed.long_description,
    seed.specs_json::JSONB,
    seed.list_price,
    currency.currency_code,
    CASE
        WHEN seed.is_published AND seed.active_ind
            THEN '/media/catalogue/' || seed.product_code || '.jpg'
        ELSE NULL
    END,
    seed.is_published,
    CASE WHEN seed.is_published AND seed.active_ind THEN CURRENT_TIMESTAMP ELSE NULL END,
    seed.sort_order,
    seed.active_ind,
    'DEV_SEED',
    'DEV_SEED'
FROM (
    VALUES
        ('TEST-CAT-01', 'TEST Waaree 540W Mono PERC Panel', 'CAT_PANEL', 'TEST 540W module', 'TEST data. Half-cut mono PERC panel for rooftop strings.', '{"brand":"Waaree","wattage_wp":540}', 9200.00, TRUE, TRUE, 10),
        ('TEST-CAT-02', 'TEST Adani 550W Bifacial Panel', 'CAT_PANEL', 'TEST bifacial module', 'TEST data. Bifacial glass-glass module.', '{"brand":"Adani","wattage_wp":550}', 9800.00, TRUE, TRUE, 20),
        ('TEST-CAT-03', 'TEST Tata 445W Poly Panel', 'CAT_PANEL', 'TEST polycrystalline module', 'TEST data. Polycrystalline panel for smaller roofs.', '{"brand":"Tata Power","wattage_wp":445}', 7400.00, TRUE, TRUE, 30),
        ('TEST-CAT-04', 'TEST Loom 400W Mono Panel', 'CAT_PANEL', 'TEST compact module', 'TEST data. Compact mono panel.', '{"brand":"Loom Solar","wattage_wp":400}', 6100.00, TRUE, TRUE, 40),
        ('TEST-CAT-05', 'TEST Waaree 330W Panel', 'CAT_PANEL', 'TEST legacy wattage', 'TEST data. Lower wattage module kept for comparison.', '{"brand":"Waaree","wattage_wp":330}', 4800.00, TRUE, TRUE, 50),
        ('TEST-CAT-06', 'TEST RenewSys 450W Panel', 'CAT_PANEL', 'TEST DCR-style module', 'TEST data. 450W module.', '{"brand":"RenewSys","wattage_wp":450}', 7600.00, TRUE, TRUE, 60),
        ('TEST-CAT-07', 'TEST Vikram 535W Panel', 'CAT_PANEL', 'TEST high-efficiency module', 'TEST data. 535W mono module.', '{"brand":"Vikram","wattage_wp":535}', 8900.00, TRUE, TRUE, 70),
        ('TEST-CAT-08', 'TEST Premier 390W Panel', 'CAT_PANEL', 'TEST value module', 'TEST data. 390W panel.', '{"brand":"Premier","wattage_wp":390}', 5600.00, TRUE, TRUE, 80),
        ('TEST-CAT-09', 'TEST Unpublished 500W Panel', 'CAT_PANEL', 'TEST draft panel', 'TEST data. Draft panel that must stay out of the public catalogue.', '{"brand":"Waaree","wattage_wp":500}', 8000.00, FALSE, TRUE, 90),
        ('TEST-CAT-10', 'TEST Inactive 410W Panel', 'CAT_PANEL', 'TEST inactive panel', 'TEST data. Inactive panel that must stay hidden.', '{"brand":"Adani","wattage_wp":410}', 5000.00, TRUE, FALSE, 100),
        ('TEST-CAT-11', 'TEST Growatt 3kW On-grid Inverter', 'CAT_INVERTER', 'TEST 3 kW string inverter', 'TEST data. Single-phase on-grid inverter.', '{"brand":"Growatt","capacity_kw":3,"phase":"single"}', 28500.00, TRUE, TRUE, 110),
        ('TEST-CAT-12', 'TEST Growatt 5kW On-grid Inverter', 'CAT_INVERTER', 'TEST 5 kW string inverter', 'TEST data. Single-phase 5 kW inverter.', '{"brand":"Growatt","capacity_kw":5,"phase":"single"}', 36500.00, TRUE, TRUE, 120),
        ('TEST-CAT-13', 'TEST Sungrow 6kW Inverter', 'CAT_INVERTER', 'TEST 6 kW inverter', 'TEST data. 6 kW on-grid inverter.', '{"brand":"Sungrow","capacity_kw":6,"phase":"single"}', 42000.00, TRUE, TRUE, 130),
        ('TEST-CAT-14', 'TEST Sungrow 10kW Three-phase Inverter', 'CAT_INVERTER', 'TEST 10 kW inverter', 'TEST data. Three-phase commercial inverter.', '{"brand":"Sungrow","capacity_kw":10,"phase":"three"}', 78000.00, TRUE, TRUE, 140),
        ('TEST-CAT-15', 'TEST Luminous 2kW Off-grid Inverter', 'CAT_INVERTER', 'TEST off-grid inverter', 'TEST data. Off-grid inverter with battery input.', '{"brand":"Luminous","capacity_kw":2,"phase":"single"}', 24000.00, TRUE, TRUE, 150),
        ('TEST-CAT-16', 'TEST Eastman 7.5kW Hybrid Inverter', 'CAT_INVERTER', 'TEST hybrid inverter', 'TEST data. Hybrid inverter for battery-ready plants.', '{"brand":"Eastman","capacity_kw":7.5,"phase":"single"}', 69000.00, TRUE, TRUE, 160),
        ('TEST-CAT-17', 'TEST Unpublished 8kW Inverter', 'CAT_INVERTER', 'TEST draft inverter', 'TEST data. Draft inverter excluded from the public list.', '{"brand":"Growatt","capacity_kw":8}', 71000.00, FALSE, TRUE, 170),
        ('TEST-CAT-18', 'TEST Inactive 4kW Inverter', 'CAT_INVERTER', 'TEST inactive inverter', 'TEST data. Inactive inverter excluded from the public list.', '{"brand":"Sungrow","capacity_kw":4}', 30000.00, TRUE, FALSE, 180),
        ('TEST-CAT-19', 'TEST GI Elevated Roof Structure 1kW', 'CAT_STRUCTURE', 'TEST 1 kW structure', 'TEST data. Elevated galvanised structure.', '{"brand":"Local fabricate","capacity_kw":1,"material":"GI"}', 8500.00, TRUE, TRUE, 190),
        ('TEST-CAT-20', 'TEST GI Elevated Roof Structure 3kW', 'CAT_STRUCTURE', 'TEST 3 kW structure', 'TEST data. Elevated structure for a 3 kW plant.', '{"brand":"Local fabricate","capacity_kw":3,"material":"GI"}', 18500.00, TRUE, TRUE, 200),
        ('TEST-CAT-21', 'TEST GI Flush Roof Structure 5kW', 'CAT_STRUCTURE', 'TEST flush structure', 'TEST data. Flush-mount structure.', '{"brand":"Local fabricate","capacity_kw":5,"material":"GI"}', 22000.00, TRUE, TRUE, 210),
        ('TEST-CAT-22', 'TEST Aluminium Tin-shed Structure 2kW', 'CAT_STRUCTURE', 'TEST tin-shed structure', 'TEST data. Aluminium structure for a tin shed.', '{"brand":"Local fabricate","capacity_kw":2,"material":"aluminium"}', 16000.00, TRUE, TRUE, 220),
        ('TEST-CAT-23', 'TEST Unpublished Ground Structure 10kW', 'CAT_STRUCTURE', 'TEST draft structure', 'TEST data. Draft ground-mount structure.', '{"brand":"Local fabricate","capacity_kw":10}', 64000.00, FALSE, TRUE, 230),
        ('TEST-CAT-24', 'TEST Eastman 150Ah Solar Battery', 'CAT_BATTERY', 'TEST tall tubular battery', 'TEST data. 12V 150Ah battery.', '{"brand":"Eastman","capacity_ah":150,"voltage_v":12}', 18500.00, TRUE, TRUE, 240),
        ('TEST-CAT-25', 'TEST Luminous 200Ah Solar Battery', 'CAT_BATTERY', 'TEST 200Ah battery', 'TEST data. 12V 200Ah tubular battery.', '{"brand":"Luminous","capacity_ah":200,"voltage_v":12}', 24000.00, TRUE, TRUE, 250),
        ('TEST-CAT-26', 'TEST Exide 100Ah Solar Battery', 'CAT_BATTERY', 'TEST 100Ah battery', 'TEST data. Compact 100Ah battery.', '{"brand":"Exide","capacity_ah":100,"voltage_v":12}', 13200.00, TRUE, TRUE, 260),
        ('TEST-CAT-27', 'TEST Lithium 5kWh Wall Battery', 'CAT_BATTERY', 'TEST lithium pack', 'TEST data. 48V lithium battery pack.', '{"brand":"Eastman","capacity_kwh":5,"voltage_v":48}', 145000.00, TRUE, TRUE, 270),
        ('TEST-CAT-28', 'TEST Lithium 10kWh Rack Battery', 'CAT_BATTERY', 'TEST rack battery', 'TEST data. 48V rack battery.', '{"brand":"Luminous","capacity_kwh":10,"voltage_v":48}', 260000.00, TRUE, TRUE, 280),
        ('TEST-CAT-29', 'TEST Unpublished 120Ah Battery', 'CAT_BATTERY', 'TEST draft battery', 'TEST data. Draft battery excluded from the public list.', '{"brand":"Exide","capacity_ah":120}', 15000.00, FALSE, TRUE, 290),
        ('TEST-CAT-30', 'TEST DCDB 1-in 1-out', 'CAT_BOS', 'TEST DC distribution box', 'TEST data. DC distribution box with SPD and fuse.', '{"brand":"Generic","inputs":1}', 3200.00, TRUE, TRUE, 300),
        ('TEST-CAT-31', 'TEST ACDB Single-phase', 'CAT_BOS', 'TEST AC distribution box', 'TEST data. Single-phase AC distribution box.', '{"brand":"Generic","phase":"single"}', 2800.00, TRUE, TRUE, 310),
        ('TEST-CAT-32', 'TEST DC Cable 4 sq mm Red', 'CAT_BOS', 'TEST solar cable', 'TEST data. 4 sq mm solar DC cable, priced per metre.', '{"brand":"Polycab","size_sqmm":4}', 48.00, TRUE, TRUE, 320),
        ('TEST-CAT-33', 'TEST Earthing Kit', 'CAT_BOS', 'TEST earthing set', 'TEST data. Chemical earthing kit.', '{"brand":"Generic","length_m":2}', 4500.00, TRUE, TRUE, 330),
        ('TEST-CAT-34', 'TEST MC4 Connector Pair', 'CAT_ACCESSORY', 'TEST MC4 pair', 'TEST data. MC4 male and female pair.', '{"brand":"Generic","rating_a":30}', 180.00, TRUE, TRUE, 340),
        ('TEST-CAT-35', 'TEST Mid Clamp', 'CAT_ACCESSORY', 'TEST module clamp', 'TEST data. Mid clamp for 35 mm frames.', '{"brand":"Generic","frame_mm":35}', 45.00, TRUE, TRUE, 350),
        ('TEST-CAT-36', 'TEST End Clamp', 'CAT_ACCESSORY', 'TEST end clamp', 'TEST data. End clamp for 35 mm frames.', '{"brand":"Generic","frame_mm":35}', 42.00, TRUE, TRUE, 360),
        ('TEST-CAT-37', 'TEST Walkway Guard', 'CAT_ACCESSORY', 'TEST roof walkway', 'TEST data. Walkway section for maintenance access.', '{"brand":"Generic","length_m":1}', 2200.00, TRUE, TRUE, 370),
        ('TEST-CAT-38', 'TEST Inactive Cable Tie Pack', 'CAT_ACCESSORY', 'TEST inactive accessory', 'TEST data. Inactive accessory excluded from the public list.', '{"brand":"Generic"}', 90.00, TRUE, FALSE, 380),
        ('TEST-CAT-39', 'TEST Panel Cleaning AMC 1 Year', 'CAT_AMC_ADDON', 'TEST annual cleaning', 'TEST data. Four cleaning visits. Collection remains offline.', '{"brand":"Solar Service","visits":4}', 6000.00, TRUE, TRUE, 390),
        ('TEST-CAT-40', 'TEST Inverter Health Check', 'CAT_AMC_ADDON', 'TEST health check', 'TEST data. One inverter inspection visit.', '{"brand":"Solar Service","visits":1}', 1500.00, TRUE, TRUE, 400),
        ('TEST-CAT-41', 'TEST Comprehensive AMC 5kW', 'CAT_AMC_ADDON', 'TEST 5 kW AMC', 'TEST data. Annual AMC for a 5 kW plant. Collection remains offline.', '{"brand":"Solar Service","capacity_kw":5}', 9000.00, TRUE, TRUE, 410),
        ('TEST-CAT-42', 'TEST Unpublished AMC Addon', 'CAT_AMC_ADDON', 'TEST draft AMC', 'TEST data. Draft AMC product excluded from the public list.', '{"brand":"Solar Service"}', 4000.00, FALSE, TRUE, 420),
        ('TEST-CAT-43', 'TEST Net Meter Coordination', 'CAT_OTHER', 'TEST utility coordination', 'TEST data. Coordination assistance. Not a payment product.', '{"brand":"Solar Service"}', 2500.00, TRUE, TRUE, 430),
        ('TEST-CAT-44', 'TEST Generation Meter', 'CAT_OTHER', 'TEST generation meter', 'TEST data. Solar generation meter.', '{"brand":"L&T","phase":"single"}', 3200.00, TRUE, TRUE, 440),
        ('TEST-CAT-45', 'TEST Unpublished Site Survey Kit', 'CAT_OTHER', 'TEST draft survey item', 'TEST data. Draft item excluded from the public list.', '{"brand":"Solar Service"}', 1000.00, FALSE, TRUE, 450)
) AS seed (
    product_code,
    product_name,
    category_code,
    short_description,
    long_description,
    specs_json,
    list_price,
    is_published,
    active_ind,
    sort_order
)
JOIN solar_app.ref_data AS category
    ON category.data_code = seed.category_code
   AND category.active_ind IS TRUE
JOIN solar_app.ref_data_categories AS category_group
    ON category_group.category_id = category.category_id
   AND category_group.category_code = 'PRODUCT_CATEGORIES'
   AND category_group.active_ind IS TRUE
JOIN solar_app.ref_currencies AS currency
    ON currency.currency_code = 'INR'
   AND currency.active_ind IS TRUE
WHERE NOT EXISTS (
    SELECT 1
      FROM solar_app.product_details AS existing
     WHERE existing.product_code = seed.product_code
);

INSERT INTO solar_app.product_media_details (
    product_id,
    media_type,
    file_url,
    caption,
    sort_order,
    created_by,
    updated_by
)
SELECT
    product.product_id,
    'PHOTO',
    '/media/catalogue/' || product.product_code || '.jpg',
    'TEST catalogue image',
    1,
    'DEV_SEED',
    'DEV_SEED'
FROM solar_app.product_details AS product
WHERE product.created_by = 'DEV_SEED'
  AND product.product_code LIKE 'TEST-CAT-%'
  AND product.active_ind IS TRUE
  AND product.is_published IS TRUE
  AND NOT EXISTS (
      SELECT 1
        FROM solar_app.product_media_details AS media
       WHERE media.product_id = product.product_id
         AND media.file_url = '/media/catalogue/' || product.product_code || '.jpg'
  );

DO $catalogue_seed_check$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*)
      INTO v_count
      FROM solar_app.product_details
     WHERE created_by = 'DEV_SEED'
       AND product_code LIKE 'TEST-CAT-%';
    IF v_count <> 45 THEN
        RAISE EXCEPTION 'Expected 45 TEST catalogue products, found %', v_count;
    END IF;
END;
$catalogue_seed_check$;

COMMIT;
