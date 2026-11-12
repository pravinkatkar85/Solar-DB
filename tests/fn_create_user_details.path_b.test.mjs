// Specification and SQL-source tests for Path B fn_create_user_details.
// These tests do not connect to PostgreSQL and do not install functions.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const loader = readFileSync(join(root, 'SQLScripts/02_functions.sql'), 'utf8');
const source = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_create_user_details.sql'),
  'utf8',
);
const pinUserSource = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_create_pin_user.sql'),
  'utf8',
);
const notificationSource = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_create_notification_details.sql'),
  'utf8',
);

function assertAdminAllowed(roleCode, activeInd, accountCode) {
  if (activeInd !== true || accountCode === 'ACCT_SUSPENDED') {
    return { ok: false, code: 403 };
  }
  if (roleCode !== 'ROLE_ADMIN') {
    return { ok: false, code: 403 };
  }
  return { ok: true, code: 200 };
}

function assertPinRejected(payload) {
  const pin = payload.pin == null ? '' : String(payload.pin).trim();
  const pinHash = payload.pin_hash == null ? '' : String(payload.pin_hash).trim();
  if (pin || pinHash) {
    return { ok: false, code: 400, message: 'PIN must not be set for Path B registration' };
  }
  return { ok: true };
}

function assertDuplicateMobile({ existingMobiles, mobile }) {
  if (existingMobiles.includes(mobile)) {
    return { ok: false, code: 409 };
  }
  return { ok: true };
}

function assertRequiredFields(payload) {
  const missing = [];
  for (const key of [
    'api_endpoint',
    'jwt_token_hash',
    'country_id',
    'national_number',
    'full_name',
    'customer_code',
    'order_no',
    'order_status_code',
    'currency_code',
    'sites',
  ]) {
    if (
      payload[key] == null ||
      (typeof payload[key] === 'string' && !payload[key].trim()) ||
      (Array.isArray(payload[key]) && payload[key].length === 0)
    ) {
      missing.push(key);
    }
  }
  return missing;
}

function assertPathBStatusCodes({ orderStatusCode, installationStatusCode }) {
  const orderOk =
    orderStatusCode === 'ORD_INSTALLED' || orderStatusCode === 'ORD_COMMISSIONED';
  const installOk =
    installationStatusCode === 'INST_INSTALLED' ||
    installationStatusCode === 'INST_COMMISSIONED';
  return orderOk && installOk;
}

function planPathBWrite(payload) {
  const sites = payload.sites ?? [];
  const equipmentCount = sites.reduce(
    (sum, site) => sum + (site.equipment?.length ?? 0),
    0,
  );
  const defaultSites = sites.filter((site) => site.is_default === true);
  return {
    user: {
      pinHash: null,
      adminRegistered: true,
      registrationSource: 'REG_ADMIN_POST_INSTALL',
      role: 'ROLE_CUSTOMER',
    },
    customerCode: payload.customer_code,
    siteCount: sites.length,
    equipmentCount,
    orderSource: 'MANUAL',
    orderStatusCode: payload.order_status_code,
    accessRole: 'ACCESS_OWNER',
    defaultCount: defaultSites.length === 0 ? 1 : defaultSites.length,
    notificationType: 'NTF_ACCOUNT_READY',
  };
}

describe('specification: Path B authorization and PIN rules (no database)', () => {
  it('allows only an active ROLE_ADMIN session', () => {
    assert.deepEqual(
      assertAdminAllowed('ROLE_ADMIN', true, 'ACCT_ACTIVE'),
      { ok: true, code: 200 },
    );
    assert.equal(assertAdminAllowed('ROLE_CUSTOMER', true, 'ACCT_ACTIVE').code, 403);
    assert.equal(assertAdminAllowed('ROLE_ADMIN', true, 'ACCT_SUSPENDED').code, 403);
  });

  it('rejects any admin-supplied PIN', () => {
    assert.equal(assertPinRejected({ pin: '1234' }).ok, false);
    assert.equal(assertPinRejected({ pin_hash: 'x' }).ok, false);
    assert.equal(assertPinRejected({}).ok, true);
  });

  it('detects duplicate mobile conflicts', () => {
    assert.equal(
      assertDuplicateMobile({
        existingMobiles: ['+919876543210'],
        mobile: '+919876543210',
      }).code,
      409,
    );
  });

  it('requires core Path B fields including sites', () => {
    const missing = assertRequiredFields({
      api_endpoint: '/api/admin/customers/create',
      jwt_token_hash: 'a'.repeat(64),
      country_id: '1',
      national_number: '9876543210',
      full_name: 'Demo',
      customer_code: 'CUST-1',
      order_no: 'ORD-1',
      order_status_code: 'ORD_COMMISSIONED',
      currency_code: 'INR',
      sites: [],
    });
    assert.deepEqual(missing, ['sites']);
  });

  it('accepts only Installed/Commissioned status codes from seed', () => {
    assert.equal(
      assertPathBStatusCodes({
        orderStatusCode: 'ORD_COMMISSIONED',
        installationStatusCode: 'INST_INSTALLED',
      }),
      true,
    );
    assert.equal(
      assertPathBStatusCodes({
        orderStatusCode: 'ORD_DRAFT',
        installationStatusCode: 'INST_COMMISSIONED',
      }),
      false,
    );
  });

  it('plans multi-site writes with NULL PIN and MANUAL order', () => {
    const plan = planPathBWrite({
      customer_code: 'CUST-42',
      order_status_code: 'ORD_COMMISSIONED',
      sites: [
        {
          site_name: 'Home',
          is_default: true,
          equipment: [{ equipment_type_code: 'EQ_PANEL' }],
        },
        {
          site_name: 'Farm',
          equipment: [
            { equipment_type_code: 'EQ_INVERTER' },
            { equipment_type_code: 'EQ_PANEL' },
          ],
        },
      ],
    });
    assert.equal(plan.user.pinHash, null);
    assert.equal(plan.user.adminRegistered, true);
    assert.equal(plan.user.registrationSource, 'REG_ADMIN_POST_INSTALL');
    assert.equal(plan.siteCount, 2);
    assert.equal(plan.equipmentCount, 3);
    assert.equal(plan.orderSource, 'MANUAL');
    assert.equal(plan.accessRole, 'ACCESS_OWNER');
    assert.equal(plan.notificationType, 'NTF_ACCOUNT_READY');
  });
});

describe('SQL source: fn_create_user_details', () => {
  it('registers the function after notification helpers in the loader', () => {
    assert.match(loader, /fn_create_notification_details\.sql/);
    assert.match(loader, /fn_create_user_details\.sql/);
    const notificationIdx = loader.indexOf('fn_create_notification_details.sql');
    const pathBIdx = loader.indexOf('fn_create_user_details.sql');
    assert.ok(pathBIdx > notificationIdx);
  });

  it('does not modify Path A pin registration', () => {
    assert.match(pinUserSource, /CREATE OR REPLACE FUNCTION solar_app\.fn_create_pin_user/);
    assert.match(pinUserSource, /REG_SELF_APP/);
    assert.match(pinUserSource, /public\.crypt\(v_pin, public\.gen_salt\('bf', 10\)\)/);
    assert.doesNotMatch(source, /public\.crypt/);
    assert.doesNotMatch(source, /REG_SELF_APP/);
    assert.doesNotMatch(source, /fn_create_pin_user\(/);
  });

  it('enforces ROLE_ADMIN from the session and ignores client role ownership', () => {
    assert.match(source, /ROLE_ADMIN/);
    assert.match(source, /session\.jwt_token_hash = v_token_hash/);
    assert.match(source, /Only an administrator can register Path B customers/);
    assert.doesNotMatch(source, /p_payload->>'role/);
    assert.doesNotMatch(source, /p_payload->>'customer_id'/);
  });

  it('forces NULL PIN, admin_registered TRUE, and REG_ADMIN_POST_INSTALL', () => {
    assert.match(source, /PIN must not be set for Path B registration/);
    assert.match(source, /pin_hash,\s*\n\s*admin_registered/);
    assert.match(source, /NULL,\s*\n\s*TRUE,\s*\n\s*v_acct_status_id,\s*\n\s*v_source_id/);
    assert.match(source, /REG_ADMIN_POST_INSTALL/);
    assert.match(source, /admin_registered/);
  });

  it('creates customer, multi-site, equipment, MANUAL order, and site access', () => {
    assert.match(source, /INSERT INTO solar_app\.customer_details/);
    assert.match(source, /INSERT INTO solar_app\.site_details/);
    assert.match(source, /INSERT INTO solar_app\.equipment_details/);
    assert.match(source, /INSERT INTO solar_app\.order_details/);
    assert.match(source, /'MANUAL'/);
    assert.match(source, /ORD_INSTALLED/);
    assert.match(source, /ORD_COMMISSIONED/);
    assert.match(source, /INST_INSTALLED/);
    assert.match(source, /INST_COMMISSIONED/);
    assert.match(source, /INSERT INTO solar_app\.user_site_access_details/);
    assert.match(source, /ACCESS_OWNER/);
    assert.match(source, /Add at least one site/);
    assert.match(source, /Add equipment for sites/);
  });

  it('links sites to the created order and supports order lines', () => {
    assert.match(source, /SET order_id = v_order_id/);
    assert.match(source, /INSERT INTO solar_app\.order_line_details/);
  });

  it('enqueues NTF_ACCOUNT_READY through fn_create_notification_details and fails closed', () => {
    assert.match(source, /fn_create_notification_details/);
    assert.match(source, /NTF_ACCOUNT_READY/);
    assert.match(source, /Path B notification enqueue failed/);
    assert.match(notificationSource, /NOTIFICATION_TYPES/);
    assert.match(notificationSource, /recipient_user_id/);
  });

  it('returns 409 for duplicate mobile or customer code and logs without PIN values', () => {
    assert.match(source, /An account with this mobile number already exists/);
    assert.match(source, /This customer code already exists/);
    assert.match(source, /This order number already exists/);
    assert.match(source, /unique_violation/);
    assert.match(source, /log_sql_functions/);
    const logBlock = source.slice(source.indexOf('v_log_payload :='));
    assert.doesNotMatch(logBlock, /->>'pin'/);
    assert.doesNotMatch(logBlock, /'pin'/);
    assert.doesNotMatch(logBlock, /pin_hash/);
  });

  it('keeps writes inside one exception block for full rollback', () => {
    assert.match(source, /<<body>>/);
    assert.match(source, /EXCEPTION/);
    assert.match(source, /WHEN unique_violation THEN/);
    assert.match(source, /WHEN SQLSTATE 'P0001' THEN/);
    assert.match(source, /WHEN OTHERS THEN/);
  });
});
