# solar_app.fn_get_product_enquiry_details

Lists the signed-in user's own active product enquiries. The user is the single active session for `jwt_token_hash`. A payload `user_id` or `logged_in_user_id` that does not match that session returns 401 and is not used to choose the user.

## Request

`p_payload` JSON object:

- `api_endpoint` required, 1–255 characters
- `jwt_token_hash` required, 64 lowercase hex characters, supplied by the API from the bearer token

## Response

`status`, `code`, `message`, and `data`.

Success `data.enquiries` is an array ordered by newest first. Each item has `product_enquiry_id`, `enquiry_no`, `product_id`, `product_name`, `status_code`, `status_name`, `agent_name`, `agent_mobile`, `message_text`, `preferred_contact_window`, and `created_on`. `agent_name` and `agent_mobile` are empty when no active engineer is assigned. An empty list is success.

Internal remarks, the assigned agent, and other users' rows are not returned.

## Codes

- 200 enquiries loaded
- 400 payload or session hash is not valid
- 401 authentication is required
- 403 inactive or suspended account
- 500 unexpected failure
