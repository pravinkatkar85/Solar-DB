# solar_app.fn_get_amc_contract_details

Returns active `amc_contract_details` and `service_milestone_details` rows for sites owned by the session customer (`customer_details.user_id` to `site_details.customer_id`). A payload user id is not trusted.

Contract fields are the stored status (`ACTIVE`, `EXPIRED`, `CANCELLED`), start and expiry dates, and the linked plan name plus cleaning and breakdown flags. `free_visit_count` and `free_visit_radius_km` are read only from `plan_snapshot_json`. A missing key, a non-number, a negative value, or a count that is not a whole number is JSON null. The live `ref_amc_plans` columns are not used for those two fields. The screen already hides an empty count or radius, so a null leaves that line off. Contract order remains `expiry_on`, then site name. That is the Phase 1 list order. It is not the billing rule, which selects the latest `start_on` and then the greatest `amc_contract_id` inside the fee function. Milestone fields are the sequence, due date, claim-window end, and `MILESTONE_STATUSES` label.

Sold amount, plan price, and a calculated visit fee are not returned. The read-only fee quote is `fn_get_site_visit_charge`, which is authored and not installed.
