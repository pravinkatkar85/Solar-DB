# solar_app.fn_create_product_enquiry_details

`solar_app.fn_create_product_enquiry_details(p_payload JSONB) RETURNS JSONB`

The user is the single active session for `jwt_token_hash`. A different payload `user_id` or `logged_in_user_id` returns 401 and is not used.

Requires a published active product and `message_text` of 1–2000 characters. Optional `preferred_contact_window` (50) and `pincode_id`. `customer_id` is set when that user has an active `customer_details` row. Status is reference code `ENQ_OPEN`. `enquiry_no` is `ENQ-` plus the new `product_enquiry_id` in 8 digits.

Success `data` is `product_enquiry_id`, `enquiry_no`, and `product_id`. The log stores the endpoint, session id, and product id only.

`fn_create_notification_details` is not called because that function is not implemented. Lead conversion is not part of this function.
