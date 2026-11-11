# solar_app.fn_create_service_request_details

Books one Open (`SR_OPEN`) preventive service request for a site owned by the session customer. Service type and slot must be active `SERVICE_TYPES` and `SERVICE_SLOT_WINDOWS` rows. `preferred_on` is the visit date. The public number is `SR-` plus the identity padded to 8 digits.

The fee comes from `fn_get_site_visit_charge`, called with the session token, the owned site, and `preferred_on`. A client fee, credit count, contract id, or user id is not used. No visit purpose is sent, so a quote uses a general slab. Service type is not mapped to a visit purpose.

An available quote is stored only when `quote_status` is `AVAILABLE` and the entitlement reason is not `CREDIT_HOLD_UNAVAILABLE`. `CREDIT_HOLD_UNAVAILABLE` still refuses the booking, because a paid price must not be substituted when the credit hold cannot be checked. A quote that is unavailable while an approved default office and at least one approved slab both exist also refuses the booking. Missing site coordinates, an ambiguous slab, or a distance with no matching slab are in that group. No fee is invented.

When that approved configuration is absent — the active default office count whose `office_code` does not start with `DEV_` is not exactly one, or there is no active slab whose `created_by` is not `DEV_SEED` — the function books the same Open request as before. `quoted_charge_amount`, `quoted_currency_code`, `visit_charge_slab_id`, and `quote_confirmed_on` stay null. `fee_quote_snapshot_json` stays `{}`. No reservation row is inserted. The success payload has `quote_confirmed` false. Completion still requires a confirmed quote, so this booking cannot be completed as a priced visit.

When the slab is free, the request stores that quote and does not reserve an AMC credit. When the slab is paid and the locked contract still qualifies, the function reserves one credit and stores a confirmed quote of 0. The slab amount remains in `fee_quote_snapshot_json`. When no credit remains, or the visit does not qualify, the request stores the paid slab amount and does not reserve a credit. A confirmed booking has `quote_confirmed` true.

Qualification uses the same snapshot keys as the fee function: `free_visit_count` and `free_visit_radius_km`. The live plan is not read. The contract row is locked with `FOR UPDATE`. The credit sequence is the lowest number from 1 through that count which is not already `RESERVED` or `CONSUMED`. A `RELEASED` row does not block that number. Allocation is not `COUNT(*) + 1`. The partial unique index is the backstop; a unique conflict retries the whole request and reservation up to three times. A failed attempt rolls back both writes.

An optional `milestone_id` must be an active `MS_DUE` milestone on the same site, still unlinked, whose `claim_window_end_on` is on or after `preferred_on`. The milestone status is not changed. Its `service_request_id` is set to the new request. A lost race returns 400 and writes nothing. Omitting `milestone_id` keeps the previous booking shape for that link. Technician assignment and visit completion stay outside this function. Cancellation, lapse, and rescheduling are `fn_update_service_request_details`.

## Codes

- 200 request booked, with `quote_confirmed` false when approved pricing configuration is absent
- 400 payload, date, type, slot, unavailable fee while pricing configuration exists, or a milestone that cannot be claimed
- 401 authentication is required
- 403 inactive or suspended account
- 404 no customer, or the site is not owned by this customer
- 500 unexpected failure, including a credit conflict that remains after three attempts

## Not installed

Do not run `02_functions.sql` for this step. Do not install this function until `08_amc_credit_reservation_and_quote.sql` has been applied. The quote columns and `amc_credit_reservation_details` are part of that migration. A confirmed fee still requires an approved office and an approved slab. Development `DEV_` office and `DEV_SEED` slabs are not a quote. While that configuration is absent, booking succeeds without a fee.
