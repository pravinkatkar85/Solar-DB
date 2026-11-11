# solar_app.fn_update_site_visit_details

Completes the site visit for one confirmed service request owned by the session customer. A payload user id, contract id, fee, or credit status is not used.

The request must be `SR_OPEN`, `SR_ASSIGNED`, or `SR_IN_PROGRESS`, with `quote_confirmed_on` and the stored quote amount, currency, and slab. The visit copies those values and `fee_quote_snapshot_json`. It does not call `fn_get_site_visit_charge`.

A new row uses visit number `SV-` plus the identity padded to 8 digits, purpose `VISIT_SERVICE`, and the office id already stored in the quote snapshot. `uq_sv_one_service_request` rejects a second visit for the same request. That failure rolls back the credit update.

The stored `coverage` and `fee.is_free_slab` must agree. A zero quote amount is not used to decide the credit.

- `FREE_SLAB` completes with no credit change, and only when that request has no `RESERVED` or `CONSUMED` row.
- `PAID_SLAB` does the same.
- `AMC_CREDIT` consumes the one `RESERVED` row for that request, matched by its id and `credit_seq`. It does not choose a credit by counting completed visits.

If those stored signals disagree, nothing is written. A `CONSUMED` credit is not changed and is not refunded. A second completion does not create a visit or consume another credit. `VISIT_CANCELLED`, `VISIT_NO_SHOW`, and an inactive visit are not reopened. `uq_sv_one_service_request` includes those rows, so the request does not receive another visit.

`MS_DUE` or `MS_BOOKED` becomes `MS_COMPLETED`. `MS_COMPLETED` and `MS_LAPSED` are not changed. `claim_window_end_on` is not changed. The request becomes `SR_COMPLETED`. Offline charge receipt is not recorded.

The same customer-ownership session check as booking is used. Assignment of a technician is not changed. `POST /api/service-requests/complete` forwards only `service_request_id` plus the session. A client user id, contract id, fee, or credit status is not accepted.

## Codes

- 200 visit completed
- 400 request, quote, conflicting credit signals, a closed visit, or a second visit
- 401 authentication is required
- 403 inactive or suspended account
- 404 the request is not owned by this customer
- 500 unexpected failure, or a required status code is missing

## Not installed

Do not run `02_functions.sql` for this step. Do not install this function until `08_amc_credit_reservation_and_quote.sql` has been applied. The one-visit unique index and the quote columns come from that migration.
