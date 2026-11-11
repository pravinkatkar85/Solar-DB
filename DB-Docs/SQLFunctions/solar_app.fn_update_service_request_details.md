# solar_app.fn_update_service_request_details

Changes one active service request owned by the session customer. A payload user id is not trusted. Another customer's request is 404.

`action` is `CANCEL`, `LAPSE`, or `RESCHEDULE`. Those words map to the existing status codes `SR_CANCELLED` and `SR_LAPSED`. Reschedule keeps the request open and changes `preferred_on`.

`SR_COMPLETED`, a visit with `completed_on` or `VISIT_COMPLETED`, or a `CONSUMED` credit cannot be changed. A second `CANCEL` or `LAPSE` of a request that is already `SR_CANCELLED` or `SR_LAPSED` returns 400 and does not release a credit. The status change and the `RESERVED` release commit together, so a successful first call does not leave a `RESERVED` row. This function does not add a repair path for a row changed outside that transaction. A `CONSUMED` row is never set to `RELEASED`.

Cancel and lapse set the request status, clear that request's `milestone_id`, and release a `RESERVED` credit when one exists. An uncompleted visit row for that request is set to `VISIT_CANCELLED`. The visit stays active. `completed_on` is not set. `uq_sv_one_service_request` still counts that cancelled row, and an inactive row, as the one visit for the request. Completion does not reopen `VISIT_CANCELLED`, `VISIT_NO_SHOW`, or an inactive visit, and it does not insert a second visit. Those rules are unchanged.

The milestone link is cleared only when no other active booking still points at that milestone. Active here means `active_ind` and a status other than `SR_CANCELLED` or `SR_LAPSED`. If another booking remains and the milestone link points at the request being closed, the link moves to that other booking and the milestone status stays as it is. If none remains, and the milestone is not `MS_COMPLETED`, `service_request_id` is cleared and the status becomes `MS_LAPSED` when `claim_window_end_on` is before today. Otherwise it becomes `MS_DUE`. The claim-by date itself stays `MS_DUE`. `claim_window_end_on` is not updated. `MS_COMPLETED` is left unchanged.

Reschedule calls `fn_get_site_visit_charge` for the new date. The same snapshot, slab, and credit-sequence rules as booking apply. The current `RESERVED` row is ignored while choosing the next free sequence, so that same sequence can be kept. A client amount is not the fee. Confirmation is accepted only when `confirmed_charge_amount`, `confirmed_currency_code`, and `confirmed_visit_charge_slab_id` are all present, the amount and currency equal the fee just calculated, and the slab id is that same slab. Sending one or two of those fields, or a different slab with the same amount, returns 400 and changes nothing. Until all three match, the response is success code 200, `confirmation_required` true, and no booking, quote, or reservation is changed. The write, including release and a new reservation, is one subtransaction and starts only after that match. A unique conflict rolls it back and retries. After three conflicts the original row is unchanged.

A linked milestone cannot move to a date after `claim_window_end_on`. The claim-by date remains allowed. That rejection does not lapse the milestone.

`POST /api/service-requests/update` forwards `service_request_id`, `action`, and, for `RESCHEDULE`, `preferred_on`. Confirmation forwards `confirmed_charge_amount`, `confirmed_currency_code`, and `confirmed_visit_charge_slab_id` only when all three are present. A 200 response with `confirmation_required` true is the preview and is not a completed reschedule. The API does not calculate or replace the fee.

## Codes

- 200 cancelled, lapsed, rescheduled, or a new fee is waiting for confirmation
- 400 action, date, unavailable fee, confirmation required or mismatched, a closed request, or a milestone date that cannot be claimed
- 401 authentication is required
- 403 inactive or suspended account
- 404 the request is not owned by this customer
- 500 unexpected failure, or a credit conflict that remains after three attempts

## Not installed

Do not run `02_functions.sql` for this step. Do not install this function until `08_amc_credit_reservation_and_quote.sql` has been applied. Approved office coordinates and pricing slabs are still required before a reschedule can store a fee.
