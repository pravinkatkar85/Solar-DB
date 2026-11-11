// Specification and SQL-source tests for Site KYC functions.
// These tests do not connect to PostgreSQL and do not install functions.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const loader = readFileSync(join(root, 'SQLScripts/02_functions.sql'), 'utf8');
const getSource = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_get_kyc_document_details.sql'),
  'utf8',
);
const createSource = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_create_kyc_document_details.sql'),
  'utf8',
);
const updateSource = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_update_kyc_document_details.sql'),
  'utf8',
);
const siteUpdateSource = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_update_site_details.sql'),
  'utf8',
);
const siteGetSource = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_get_site_details.sql'),
  'utf8',
);

function resolveMaxBytes(devParamBytes) {
  const brdCeiling = 2097152;
  if (devParamBytes != null && devParamBytes > 0 && devParamBytes < brdCeiling) {
    return Math.trunc(devParamBytes);
  }
  return brdCeiling;
}

function reviewDecision(action, comment) {
  if (action !== 'APPROVE' && action !== 'REJECT') return { ok: false, reason: 'action' };
  if (action === 'REJECT' && (!comment || !String(comment).trim())) {
    return { ok: false, reason: 'comment' };
  }
  return {
    ok: true,
    statusCode: action === 'REJECT' ? 'ACTION_REQUIRED' : 'KYC_APPROVED',
    comment: action === 'REJECT' ? String(comment).trim() : null,
  };
}

/** Mirrors the ownership / admin visibility rules in fn_get_kyc_document_details. */
function listVisibleDocuments({
  roleCode,
  sessionCustomerId,
  documents,
  siteId = null,
  statusCode = null,
}) {
  const isAdmin = roleCode === 'ROLE_ADMIN';
  if (!isAdmin && sessionCustomerId == null) return [];
  return documents.filter((doc) => {
    if (!isAdmin && doc.customerId !== sessionCustomerId) return false;
    if (siteId != null && doc.siteId != null && doc.siteId !== siteId) return false;
    if (statusCode != null && doc.statusCode !== statusCode) return false;
    return true;
  });
}

const sampleDocs = [
  {
    kycDocumentId: '1',
    customerId: 10,
    siteId: 1,
    statusCode: 'KYC_PENDING',
    customerCode: 'CUST-A',
  },
  {
    kycDocumentId: '2',
    customerId: 20,
    siteId: 2,
    statusCode: 'KYC_PENDING',
    customerCode: 'CUST-B',
  },
  {
    kycDocumentId: '3',
    customerId: 10,
    siteId: 1,
    statusCode: 'KYC_APPROVED',
    customerCode: 'CUST-A',
  },
  {
    kycDocumentId: '4',
    customerId: 20,
    siteId: null,
    statusCode: 'ACTION_REQUIRED',
    customerCode: 'CUST-B',
  },
];

describe('specification: KYC upload size (no database)', () => {
  it('uses the BRD 2 MB ceiling when no development parameter exists', () => {
    assert.equal(resolveMaxBytes(null), 2097152);
  });

  it('can tighten the ceiling with DEV_KYC_UPLOAD_MAX_BYTES', () => {
    assert.equal(resolveMaxBytes(1048576), 1048576);
  });

  it('does not raise the BRD ceiling when a larger parameter is present', () => {
    assert.equal(resolveMaxBytes(5_000_000), 2097152);
  });
});

describe('specification: KYC admin review (no database)', () => {
  it('requires a rejection comment for ACTION_REQUIRED', () => {
    assert.deepEqual(reviewDecision('REJECT', '   '), { ok: false, reason: 'comment' });
    assert.deepEqual(reviewDecision('REJECT', 'Bill unreadable'), {
      ok: true,
      statusCode: 'ACTION_REQUIRED',
      comment: 'Bill unreadable',
    });
  });

  it('approves without a rejection comment', () => {
    assert.deepEqual(reviewDecision('APPROVE', 'ignored'), {
      ok: true,
      statusCode: 'KYC_APPROVED',
      comment: null,
    });
  });
});

describe('specification: KYC list visibility (no database)', () => {
  it('lets ROLE_ADMIN see documents across multiple customers without customer_details', () => {
    const rows = listVisibleDocuments({
      roleCode: 'ROLE_ADMIN',
      sessionCustomerId: null,
      documents: sampleDocs,
    });
    assert.equal(rows.length, 4);
    assert.deepEqual(
      rows.map((row) => row.customerId).sort(),
      [10, 10, 20, 20],
    );
  });

  it('lets a customer see only their own documents', () => {
    const rows = listVisibleDocuments({
      roleCode: 'ROLE_CUSTOMER',
      sessionCustomerId: 10,
      documents: sampleDocs,
    });
    assert.equal(rows.length, 2);
    assert.equal(rows.every((row) => row.customerId === 10), true);
  });

  it('blocks a non-admin from another customer documents', () => {
    const rows = listVisibleDocuments({
      roleCode: 'ROLE_CUSTOMER',
      sessionCustomerId: 10,
      documents: sampleDocs,
      siteId: 2,
    });
    assert.equal(rows.length, 0);
  });

  it('filters by status_code for admin queues', () => {
    const pending = listVisibleDocuments({
      roleCode: 'ROLE_ADMIN',
      sessionCustomerId: null,
      documents: sampleDocs,
      statusCode: 'KYC_PENDING',
    });
    assert.equal(pending.length, 2);
    assert.equal(pending.every((row) => row.statusCode === 'KYC_PENDING'), true);
  });

  it('returns an empty list for a non-admin with no customer record', () => {
    const rows = listVisibleDocuments({
      roleCode: 'ROLE_CUSTOMER',
      sessionCustomerId: null,
      documents: sampleDocs,
    });
    assert.deepEqual(rows, []);
  });
});

describe('SQL source: KYC and site profile functions', () => {
  it('registers the new functions in the loader', () => {
    assert.match(loader, /fn_update_site_details\.sql/);
    assert.match(loader, /fn_get_kyc_document_details\.sql/);
    assert.match(loader, /fn_create_kyc_document_details\.sql/);
    assert.match(loader, /fn_update_kyc_document_details\.sql/);
  });

  it('keeps create uploads at KYC_PENDING and ignores client status fields', () => {
    assert.match(createSource, /KYC_PENDING/);
    assert.match(createSource, /2097152/);
    assert.match(createSource, /DEV_KYC_UPLOAD_MAX_BYTES/);
    assert.match(createSource, /verified_by_user_id,\s*\n\s*rejection_comment/);
    assert.doesNotMatch(createSource, /p_payload->>'verification_status/);
    assert.doesNotMatch(createSource, /p_payload->>'rejection_comment/);
  });

  it('requires ROLE_ADMIN and ACTION_REQUIRED comment on reject', () => {
    assert.match(updateSource, /ROLE_ADMIN/);
    assert.match(updateSource, /ACTION_REQUIRED/);
    assert.match(updateSource, /Enter a rejection comment/);
    assert.match(updateSource, /APPROVE|REJECT/);
  });

  it('enqueues NTF_KYC_STATUS after a successful status change and rolls back on failure', () => {
    assert.match(updateSource, /fn_create_notification_details/);
    assert.match(updateSource, /NTF_KYC_STATUS/);
    assert.match(updateSource, /v_prev_status_id IS DISTINCT FROM v_target_status_id/);
    assert.match(updateSource, /KYC notification enqueue failed/);
  });

  it('lists DOCUMENT_TYPES and verification badges for the customer', () => {
    assert.match(getSource, /DOCUMENT_TYPES/);
    assert.match(getSource, /document_types/);
    assert.match(getSource, /status_code/);
    assert.match(getSource, /rejection_comment/);
  });

  it('resolves ROLE_ADMIN from the session user and allows cross-customer listing', () => {
    assert.match(getSource, /role_ref_data_id/);
    assert.match(getSource, /ROLE_ADMIN/);
    assert.match(getSource, /v_is_admin/);
    assert.match(getSource, /v_is_admin\s*\n\s*OR doc\.customer_id = v_customer_id/);
    assert.match(getSource, /customer_code/);
    assert.match(getSource, /billing_name/);
    assert.doesNotMatch(getSource, /p_payload->>'role/);
    assert.doesNotMatch(getSource, /p_payload->>'customer_id/);
  });

  it('keeps non-admin ownership on site_id and rejects invalid sessions', () => {
    assert.match(getSource, /Authentication is required/);
    assert.match(getSource, /session\.jwt_token_hash = v_token_hash/);
    assert.match(getSource, /site\.customer_id = v_customer_id/);
    assert.match(getSource, /This site was not found/);
  });

  it('supports optional status_code filtering with known verification codes only', () => {
    assert.match(getSource, /p_payload->>'status_code'/);
    assert.match(getSource, /KYC_PENDING', 'KYC_APPROVED', 'ACTION_REQUIRED/);
    assert.match(getSource, /DOCUMENT_VERIFICATION_STATUSES/);
    assert.match(getSource, /status_row\.data_code = v_status_code/);
  });

  it('allows admin listing when the admin has no customer_details row', () => {
    assert.match(
      getSource,
      /\(NOT v_is_admin\) AND v_customer_id IS NULL/,
    );
    assert.match(getSource, /v_is_admin := \(v_role_code IS NOT DISTINCT FROM 'ROLE_ADMIN'\)/);
  });

  it('updates only Module 3.1 site profile fields for the owning customer', () => {
    assert.match(siteUpdateSource, /discom_id/);
    assert.match(siteUpdateSource, /consumer_number/);
    assert.match(siteUpdateSource, /meter_number/);
    assert.match(siteUpdateSource, /sanctioned_load_kw/);
    assert.match(siteUpdateSource, /latitude/);
    assert.doesNotMatch(siteUpdateSource, /commissioning_on\s*=/);
    assert.doesNotMatch(siteUpdateSource, /installation_status_ref_data_id\s*=/);
  });

  it('returns DISCOM and GPS fields from site get', () => {
    assert.match(siteGetSource, /discom_name/);
    assert.match(siteGetSource, /consumer_number/);
    assert.match(siteGetSource, /sanctioned_load_kw/);
    assert.match(siteGetSource, /'latitude'/);
  });
});
