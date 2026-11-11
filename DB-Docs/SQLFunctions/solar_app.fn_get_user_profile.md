# solar_app.fn_get_user_profile

Returns the signed-in row in `user_details`, plus the active customer code and billing name when a customer row exists. It also returns the user's country phone code, national length, and pattern, and the secondary mobile without that country code.

The user is the single active session for `jwt_token_hash`. A payload `user_id` is not used to choose the row. The response does not include the PIN hash, OTP counters, lockout time, or session token.

## Codes

- 200 account loaded
- 400 payload or session hash
- 401 authentication is required
- 403 inactive or suspended account
- 500 unexpected failure
