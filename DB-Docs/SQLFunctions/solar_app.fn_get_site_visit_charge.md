# solar_app.fn_get_site_visit_charge

Read-only quote for one proposed visit. The session customer must own the active site. A payload user id is not trusted.

The proposed date is `visit_on`. It is used for contract dates and for the slab effective date. A visit row does not exist yet, so this date stands in for the later `scheduled_on`.

Free visit count and radius are read only from `amc_contract_details.plan_snapshot_json` keys `free_visit_count` and `free_visit_radius_km`. A missing or unusable key makes free entitlement unavailable. The live `ref_amc_plans` row is not used.

When more than one contract is `ACTIVE` and covers `visit_on`, the latest `start_on` wins. The same start date uses the greatest `amc_contract_id`.

Distance uses the site GPS and the one active default office whose `office_code` does not start with `DEV_`. The Haversine radius is 6,371 km. The distance is rounded to two decimal places with PostgreSQL `round(numeric, 2)` before a slab is chosen. `round` is half away from zero.

A slab must be active, not created by `DEV_SEED`, and effective on `visit_on` (`effective_from` and `effective_to` are inclusive). The rounded distance must be greater than or equal to `min_distance_km` and, when `max_distance_km` is present, strictly less than that maximum. A purpose-specific slab is used when exactly one matches `visit_purpose_ref_data_id`. Otherwise exactly one null-purpose slab is used. Zero matches or more than one match leaves the fee unavailable.

Development office `DEV_OFFICE_PUNE` and the development slabs created by `DEV_SEED` are not a quote. There is no separate approval flag on those tables.

Held credits are `RESERVED` and `CONSUMED` rows for the selected contract. `RELEASED` rows are not counted. This function does not assign or reuse `credit_seq`. If `amc_credit_reservation_details` is not installed, credit counts are omitted and entitlement is not eligible.

An unavailable quote is still `status` `SUCCESS` and `code` 200. The fee fields are null. A calculated distance is returned when the coordinates exist. This function does not write a quote, reservation, booking, visit, or milestone.

## Payload

- `api_endpoint` required
- `jwt_token_hash` required, 64 lowercase hex characters
- `logged_in_user_id` and `user_id` optional; a different value is 401
- `site_id` required
- `visit_on` required, `YYYY-MM-DD`
- `visit_purpose_ref_data_id` optional; an active `SITE_VISIT_PURPOSES` id. Omitted means general slabs only

## Data

`quote_status` is `AVAILABLE` or `UNAVAILABLE`. `unavailable_reason` is `MISSING_SITE_COORDINATES`, `MISSING_APPROVED_OFFICE`, `MISSING_SLAB`, or `AMBIGUOUS_SLAB`.

`free_entitlement.reason` is `WITHIN_SNAPSHOT_ALLOWANCE`, `NO_ELIGIBLE_CONTRACT`, `MISSING_SNAPSHOT_COUNT`, `MISSING_SNAPSHOT_RADIUS`, `INVALID_SNAPSHOT`, `DISTANCE_UNKNOWN`, `OUTSIDE_SNAPSHOT_RADIUS`, `CREDIT_HOLD_UNAVAILABLE`, `NO_CREDIT_REMAINING`, or `FREE_PRICING_SLAB`.

`eligible` true means the snapshot allowance, radius, distance, and remaining hold all allow one later credit reservation. It does not reserve that credit. A free pricing slab sets `eligible` false with `FREE_PRICING_SLAB` so a later booking does not consume an AMC credit.

## Codes

- 200 fee calculated, or fee not available
- 400 payload, session hash, site, date, or purpose
- 401 authentication is required
- 403 inactive or suspended account
- 404 the site is not owned by this customer
- 500 unexpected failure

## Not installed

Source file: `DB-Objects/SQLFunctions/solar_app.fn_get_site_visit_charge.sql`. The loader line is in `SQLScripts/02_functions.sql`. Do not run the loader for this step. Migration `08_amc_credit_reservation_and_quote.sql` is also not applied.
