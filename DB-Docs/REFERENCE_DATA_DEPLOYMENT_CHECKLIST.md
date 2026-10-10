# Reference Data Deployment Checklist

## Purpose and status

This document tracks development-only configuration that must be replaced or
approved before production. It is not an executable seed script.

Reviewed sources:

- `Solar-DB/SQLScripts/01_schema.sql`
- `Solar-DB/SQLScripts/03_seed_data.sql`
- `Solar-DB/DB-Docs/DB_REQUIREMENTS.md`
- `Solar-DB/reference-data/SUMMARY.md`
- `Solar-Docs/BRD.md`
- `Solar-Docs/DB_AUDIT_REPORT.md`

Current database status: the seven tables below have zero rows.
`Solar-DB/SQLScripts/04_seed_development_reference_data.sql` now contains the
development fixtures described here, but it has not been executed. Existing
prerequisite masters already include `INR`, country `IN`, Maharashtra (`MH`),
connection types `CONN_RESIDENTIAL`, `CONN_SOCIETY`, `CONN_COMMERCIAL`, and
site-visit purpose codes. The development script uses database-generated
identity IDs and resolves foreign keys by stable codes.

## Required insertion order

1. `ref_business_parameters` — standalone.
2. `ref_subsidy_schemes` — requires country, optional state, and currency.
3. `ref_subsidy_slabs` — requires subsidy schemes and connection-type `ref_data`.
4. `ref_amc_plans` — requires currency.
5. `ref_tax_rules` — requires country, optional state, and optional currency.
6. `ref_office_locations` — requires city and pincode where supplied.
7. `ref_visit_charge_slabs` — requires currency and optional visit-purpose `ref_data`.

Steps 1, 4, 5, and 6 are independent after existing masters are available.
Always load subsidy schemes before their slabs and office locations before
creating operational site visits.

## Table checklist

| Table | Purpose and schema controls | Development sample status | Production verification |
| --- | --- | --- | --- |
| `ref_business_parameters` | Typed, effective-dated operational values. Exactly one of numeric/text/boolean/JSON must match `value_type`. Active date ranges for a code cannot overlap. | 11 `DEV_` numeric fixtures included in script 04; not executed. | Business owner must approve each code, value, unit, manageability, effective dates, and whether it is required by a function contract. Never store credentials or endpoints. |
| `ref_subsidy_schemes` | Effective-dated jurisdiction, calculation method, eligibility, currency, and optional cap. Depends on country/state/currency. | 1 `DEV_` residential scheme included; not executed. | Obtain scheme notification, eligibility, calculation method, cap, currency, jurisdiction, and validity dates from an authoritative government source. |
| `ref_subsidy_slabs` | Non-overlapping half-open capacity tiers per scheme and connection type. Exactly one of `rate_amount` or `rate_percent` is populated. | 2 tiers under the `DEV_` scheme included; not executed. | Confirm per-kW versus fixed/percentage semantics, boundary behavior, cumulative tier formula, connection eligibility, and cap interaction. |
| `ref_amc_plans` | Effective-dated AMC catalogue. `plan_price` covers the complete `duration_months` term. Includes free-visit count/radius and service coverage flags. | 3 `DEV_` plans included; not executed. | Service and finance owners must approve plan names, inclusions, duration, full-term price, currency, free visits, radius, and effective dates. |
| `ref_tax_rules` | Effective-dated percentage or fixed-amount tax components. Percentage rules require no currency; fixed rules require currency. | 3 `DEV_` GST component fixtures included; not executed. | Tax adviser must approve rates, components, tax groups, jurisdiction, classification codes, precedence, applicability, and dates. |
| `ref_office_locations` | Office origin for visit distance. Enforces coordinates, unique office code, and at most one active default office. | 1 fake `DEV_` Pune office included; not executed. | Replace name, full address, city, pincode, coordinates, branch code, and default designation with verified company data. |
| `ref_visit_charge_slabs` | Effective-dated, non-overlapping half-open distance ranges. Supports general (`purpose = NULL`) and purpose-specific overrides. Final range may be open-ended. | 4 general development bands included; not executed. | Operations/finance must approve distance source, boundaries, purpose precedence, free bands, amounts, currency, effective dates, and entitlement override behavior. |

## Development script inventory

`Solar-DB/SQLScripts/04_seed_development_reference_data.sql` contains 25
development records: 11 parameters, 1 subsidy scheme, 2 subsidy slabs, 3 AMC
plans, 3 tax rules, 1 office, and 4 visit-charge slabs. It is transactional,
does not use explicit identity IDs, resolves parent rows by stable codes, and
does not update existing rows. Production data must be deployed separately
after the approvals below; script 04 must never be used as a production seed.

## Proposed development-only data

Every code must retain a `DEV_` prefix. These values are designed only to make
calculation, boundary, effective-date, snapshot, and UI flows testable. They
must not be promoted to production by removing the prefix.

### `ref_business_parameters`

Use `effective_from = 2026-01-01`, `effective_to = NULL`,
`admin_manageable_ind = TRUE`, and `active_ind = TRUE` for development.

| Development code | Type/value | Unit | Requirement exercised | Production status |
| --- | --- | --- | --- | --- |
| `DEV_BILL_MIN` | NUMERIC `500` | `INR` | Calculator slider lower bound | BRD example; confirm deployment currency and limit. |
| `DEV_BILL_MAX` | NUMERIC `1000000` | `INR` | Calculator slider upper bound | BRD example; confirm deployment limit. |
| `DEV_SQFT_PER_KW` | NUMERIC `100` | `SQFT_PER_KW` | Rooftop-area warning | BRD states 100 sq. ft./kW; engineering approval still required. |
| `DEV_COST_PER_KW` | NUMERIC `55000` | `INR_PER_KW` | Gross-cost estimate | Sample only; no approved production value available. |
| `DEV_TARIFF_PER_KWH` | NUMERIC `9.5` | `INR_PER_KWH` | Savings/payback estimate | Sample only; production value may vary by tariff/customer. |
| `DEV_CUF` | NUMERIC `0.18` | `RATIO` | Energy-generation estimate | Sample only; engineering/location confirmation required. |
| `DEV_CO2_KG_PER_KWH` | NUMERIC `0.82` | `KG_PER_KWH` | CO₂ reduction estimate | Sample only; confirm published emissions factor. |
| `DEV_FREE_SVC_VISIT_COUNT` | NUMERIC `4` | `COUNT` | Configurable post-commissioning milestones | BRD default is four, but value must remain configurable. |
| `DEV_FREE_VISIT_RADIUS_KM` | NUMERIC `10` | `KM` | Free-entitlement radius | Sample only; no approved production radius available. |
| `DEV_SERVICE_CLAIM_WINDOW_DAYS` | NUMERIC `30` | `DAYS` | Lapse after due milestone | BRD states 30 days; confirm operational policy. |
| `DEV_KYC_UPLOAD_MAX_BYTES` | NUMERIC `2097152` | `BYTES` | 2 MB KYC upload limit | BRD states 2 MB; confirm infrastructure limit. |

OTP expiry, resend cooldown, lockout threshold, media-count limits, and other
runtime limits are required by behavior but have no approved values in the
reviewed requirements. Define development values only after their stable
parameter codes are agreed with the function/API contracts.

### `ref_subsidy_schemes` and `ref_subsidy_slabs`

Development scheme:

- Code: `DEV_PM_SURYA_RESIDENTIAL`
- Name: `Development Residential Subsidy`
- Country: resolve `IN`; state: `NULL`
- Method: `TIERED_RATE`
- Currency: `INR`
- Maximum benefit: `78000`
- Eligibility JSON must contain `"environment": "DEVELOPMENT"` and identify
  residential use only.
- Development effective period: from `2026-01-01`, open-ended.

Development slabs, resolving connection type by `CONN_RESIDENTIAL`:

| Capacity range | Development rate | Interpretation for tests |
| --- | ---: | --- |
| `[0, 2)` kW | `rate_amount = 30000` | Per-capacity tier sample |
| `[2, 3)` kW | `rate_amount = 18000` | Incremental tier sample |

Test 0, 1.999, 2, 2.999, 3, and above-3 kW values and the `78000` cap.
No zero-value Maharashtra placeholder should be active. Production values,
formula, scheme dates, cap, and eligibility remain unresolved and require an
authoritative notification.

### `ref_amc_plans`

Use currency `INR`, development effective date `2026-01-01`, and codes with a
`DEV_` prefix:

| Code | Duration | Coverage | Free visits/radius | Full-term sample price |
| --- | ---: | --- | --- | ---: |
| `DEV_AMC_BASIC` | 12 months | Cleaning | 2 / 10 km | `4999` |
| `DEV_AMC_COMPREHENSIVE` | 12 months | Cleaning and breakdown | 4 / 25 km | `9999` |
| `DEV_AMC_PREMIUM` | 24 months | Cleaning and breakdown | 8 / 50 km | `17999` |

The 24-month price is interpreted as a complete-contract sample because the
schema defines `plan_price` that way. All prices, visit counts, radii,
inclusions, tax treatment, and durations require production approval.

### `ref_tax_rules`

Development-only test set:

| Code/group/component | Jurisdiction | Method/rate | Test purpose |
| --- | --- | --- | --- |
| `DEV_GST_INTRA_CGST_9` / `DEV_GST_INTRA` / `CGST` | `IN`, Maharashtra | PERCENTAGE `9`; currency `NULL` | First intra-state component |
| `DEV_GST_INTRA_SGST_9` / `DEV_GST_INTRA` / `SGST` | `IN`, Maharashtra | PERCENTAGE `9`; currency `NULL` | Second intra-state component |
| `DEV_GST_INTER_IGST_18` / `DEV_GST_INTER` / `IGST` | `IN`, state `NULL` | PERCENTAGE `18`; currency `NULL` | Inter-state component |

Use distinct priorities and `effective_from = 2026-01-01`. The schema stores
rules but does not by itself decide intra-state versus inter-state grouping.
That selection contract must be approved and tested before production. Rates,
classification applicability, place-of-supply behavior, exemptions, and
effective dates require tax-adviser confirmation.

### `ref_office_locations`

Development-only row:

- Code: `DEV_OFFICE_PUNE`
- Name: `Development Office Pune`
- Address: `Development address — not a real company office`
- Resolve city `Pune`, Maharashtra and pincode `411001` from existing masters.
- Coordinates: `18.5204000`, `73.8567000`
- `is_default = TRUE` only when no other active default office exists; otherwise
  the development office is inserted as non-default to preserve unrelated data.

Do not use these details to charge a production customer. Verify geocoded
coordinates against the approved physical office before production.

### `ref_visit_charge_slabs`

Use `currency_code = INR`, `effective_from = 2026-01-01`, purpose `NULL`
(general default), and half-open ranges:

| Range | Development charge | Free |
| --- | ---: | --- |
| `[0, 10)` km | `0` | Yes |
| `[10, 25)` km | `750` | No |
| `[25, 50)` km | `1500` | No |
| `[50, ∞)` km | `3000` | No |

For purpose-precedence testing, add separate `DEV_` fixtures for
`VISIT_ENQUIRY` only if the resolver contract needs an override scenario.
Test exactly 0, 10, 25, and 50 km, an amount above 999 km, a free AMC/milestone
override, and offline `charges_received_ind` updates. Production bands and
amounts are not available in the requirements.

## Required development tests

- Parameter value-type consistency and effective-date resolution.
- Rejection of overlapping active parameter, scheme, AMC, tax, and visit-rule versions.
- Subsidy capacity boundaries, cumulative tier behavior, eligibility, and cap.
- Historical calculator/quote snapshots remaining unchanged after rule updates.
- AMC free-credit consumption, radius limit, expiry, renewal, and full-term price snapshot.
- Tax-group selection and immutable invoice tax-detail snapshots.
- One active default office and verified office-to-site distance.
- General versus purpose-specific visit pricing precedence.
- Exact visit-distance boundaries and open-ended final range.
- Free entitlement overriding a configured visit fee.
- Visit completion remaining separate from offline charge receipt.

## Production deployment gate

- [ ] Export/back up current reference rows and identity sequence positions.
- [ ] Confirm target country, state, currency, and stable FK codes exist.
- [ ] Confirm no duplicate natural keys or overlapping active effective ranges.
- [ ] Replace every `DEV_` code and development value with approved deployment data; do not update development rows into production identities.
- [ ] Subsidy authority signs off calculation method, tiers, cap, eligibility, jurisdiction, and dates.
- [ ] Tax adviser signs off components, grouping, rates, classification, precedence, and dates.
- [ ] Service/finance owners sign off AMC coverage, full-term prices, free visits, radius, and dates.
- [ ] Operations/finance owners sign off visit purposes, distance boundaries, rates, precedence, and currency.
- [ ] Operations verifies office address, city/pincode FKs, coordinates, and default office.
- [ ] Product owner approves global business parameters and identifies which are admin-manageable.
- [ ] Validate all effective-date and exclusion constraints in a staging database.
- [ ] Run calculator, subsidy, AMC, tax, and visit boundary regression tests.
- [ ] Verify quotation, invoice, AMC-contract, calculator, and visit snapshots preserve historical outcomes.
- [ ] Confirm no credentials, endpoints, real customer data, or placeholder office details are present.
- [ ] Obtain named business-owner approval and retain the authoritative source/version for every production rule.

