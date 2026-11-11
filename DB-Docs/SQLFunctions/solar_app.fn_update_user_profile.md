# solar_app.fn_update_user_profile

Updates the signed-in user's email and secondary mobile.

Both fields are optional. An empty value clears that field. A secondary number is the national number for the user's own country, checked with that country's length and pattern, then stored in E.164 form. Name, login mobile, role, emergency contact, language, push setting, and PIN are not changed. This is not the planned administrator function `fn_update_user_details`. Logs do not record the email or mobile number.

## Codes

- 200 account updated
- 400 payload, email, mobile, or language
- 401 authentication is required
- 403 inactive or suspended account
- 500 unexpected failure
