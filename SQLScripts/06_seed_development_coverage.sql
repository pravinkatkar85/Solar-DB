-- Development fixture only. Not a production seed.
-- Adds one AMC contract and two free-service milestones for the commissioned
-- Home rooftop site. Plan price and visit terms are copied from DEV_AMC_BASIC.

BEGIN;

INSERT INTO solar_app.amc_contract_details (
    site_id, amc_plan_id, start_on, expiry_on, contract_status,
    sold_amount, currency_code, plan_snapshot_json, created_by, updated_by
)
SELECT site.site_id,
       plan.amc_plan_id,
       DATE '2026-04-01',
       DATE '2027-03-31',
       'ACTIVE',
       plan.plan_price,
       plan.currency_code,
       jsonb_build_object(
           'plan_code', plan.plan_code,
           'plan_name', plan.plan_name,
           'duration_months', plan.duration_months,
           'includes_cleaning', plan.includes_cleaning,
           'includes_breakdown', plan.includes_breakdown,
           'free_visit_count', plan.free_visit_count,
           'free_visit_radius_km', plan.free_visit_radius_km,
           'plan_price', plan.plan_price,
           'currency_code', plan.currency_code
       ),
       'SYSTEM',
       'SYSTEM'
  FROM solar_app.site_details AS site
  JOIN solar_app.ref_amc_plans AS plan
    ON plan.plan_code = 'DEV_AMC_BASIC'
   AND plan.active_ind IS TRUE
 WHERE site.site_name = 'Home rooftop'
   AND site.active_ind IS TRUE
   AND site.created_by = 'SYSTEM'
   AND NOT EXISTS (
        SELECT 1
          FROM solar_app.amc_contract_details AS existing
         WHERE existing.site_id = site.site_id
           AND existing.amc_plan_id = plan.amc_plan_id
           AND existing.active_ind IS TRUE
   );

INSERT INTO solar_app.service_milestone_details (
    site_id, milestone_no, due_on, claim_window_end_on, status_ref_data_id,
    created_by, updated_by
)
SELECT site.site_id,
       sample.milestone_no,
       sample.due_on,
       sample.claim_window_end_on,
       status_row.ref_data_id,
       'SYSTEM',
       'SYSTEM'
  FROM solar_app.site_details AS site
  JOIN (
        VALUES
            (1, DATE '2025-11-18', DATE '2025-12-18', 'MS_COMPLETED'),
            (2, DATE '2026-11-18', DATE '2026-12-18', 'MS_DUE')
       ) AS sample(milestone_no, due_on, claim_window_end_on, status_code)
    ON TRUE
  JOIN solar_app.ref_data AS status_row
    ON status_row.data_code = sample.status_code
   AND status_row.active_ind IS TRUE
  JOIN solar_app.ref_data_categories AS status_category
    ON status_category.category_id = status_row.category_id
   AND status_category.category_code = 'MILESTONE_STATUSES'
   AND status_category.active_ind IS TRUE
 WHERE site.site_name = 'Home rooftop'
   AND site.active_ind IS TRUE
   AND site.created_by = 'SYSTEM'
   AND NOT EXISTS (
        SELECT 1
          FROM solar_app.service_milestone_details AS existing
         WHERE existing.site_id = site.site_id
           AND existing.milestone_no = sample.milestone_no
   );

COMMIT;
