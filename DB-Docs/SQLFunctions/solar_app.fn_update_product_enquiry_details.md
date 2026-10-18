# solar_app.fn_update_product_enquiry_details

Customer actions on one enquiry owned by the active session. A payload user id is not used to choose the row.

The business requirements document says closing an enquiry is an admin or sales action. This function also lets the owner cancel their own enquiry while it is Open or In Progress, which sets `ENQ_CLOSED`. A converted enquiry is not changed.

## Request

- `api_endpoint` required
- `jwt_token_hash` required, supplied by the API
- `product_enquiry_id` required
- `action` is `cancel` or `followup`
- `note` optional, up to 1000 characters, used only for a follow-up

## Actions

`cancel` sets the status to Closed.

`followup` inserts one open phone-call row in `followup_details` for the assigned engineer, due immediately. It is refused when no active engineer is assigned, or when an open follow-up already exists for that enquiry.

## Codes

- 200 enquiry cancelled, or follow-up requested
- 400 action, enquiry id, note, status, or missing engineer
- 401 authentication is required
- 403 inactive or suspended account
- 404 the enquiry is not owned by this user
- 500 unexpected failure
