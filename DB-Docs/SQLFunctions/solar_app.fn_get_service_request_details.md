# solar_app.fn_get_service_request_details

Lists active rows in `service_request_details` for the customer linked to the verified session. `user_site_access_details` grants are not used. Complaint tickets are a separate table and are not returned.

`service_request_id` is optional. When it is sent and the row is not owned, the result is 404. A customer with no row gets an empty list.

Returned fields: request number, site, service type, slot, status code and name, preferred date, assigned technician name and mobile, arrival status, completion notes, and created time.
