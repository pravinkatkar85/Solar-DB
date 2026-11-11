# solar_app.fn_get_site_details

Lists active `site_details` rows owned by the customer linked 1:1 to the signed-in user. The user is the single active session for `jwt_token_hash`. A payload `user_id` is not used to choose the customer.

There is no separate installation table. Status is `INSTALLATION_STATUSES.data_value`. The date is `commissioning_on`. Equipment capacity uses the existing wattage, inverter kW, and battery Ah columns. Module 3.1 KYC profile fields are included: DISCOM id/name, consumer number, meter number, sanctioned load kW, connection type, latitude, and longitude. `user_site_access_details` grants are not returned.

An optional `site_id` returns that one owned site, or 404. A user with no active customer row gets an empty list.

## Codes

- 200 installations loaded, including an empty list
- 400 payload, session hash, or site id
- 401 authentication is required
- 403 inactive or suspended account
- 404 the site is not owned by this customer
- 500 unexpected failure
