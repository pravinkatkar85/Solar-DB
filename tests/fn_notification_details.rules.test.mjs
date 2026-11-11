// Specification and SQL-source tests for notification enqueue and inbox.
// These tests do not connect to PostgreSQL and do not install functions.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const loader = readFileSync(join(root, 'SQLScripts/02_functions.sql'), 'utf8');
const createSource = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_create_notification_details.sql'),
  'utf8',
);
const getSource = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_get_notification_details.sql'),
  'utf8',
);
const updateSource = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_update_notification_details.sql'),
  'utf8',
);
const kycUpdateSource = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_update_kyc_document_details.sql'),
  'utf8',
);

function recipientEligible({ activeInd, accountCode }) {
  return activeInd === true && accountCode !== 'ACCT_SUSPENDED';
}

function shouldNotifyKyc({ prevStatusId, targetStatusId, recipient }) {
  if (prevStatusId === targetStatusId) return false;
  if (!recipientEligible(recipient)) return false;
  return true;
}

function buildKycNotification({ action, comment, docTypeName }) {
  if (action === 'REJECT') {
    return {
      typeCode: 'NTF_KYC_STATUS',
      title: 'KYC reviewed',
      body: `Your ${docTypeName} document needs action. ${comment}`,
      includesComment: true,
    };
  }
  return {
    typeCode: 'NTF_KYC_STATUS',
    title: 'KYC reviewed',
    body: `Your ${docTypeName} document was approved.`,
    includesComment: false,
  };
}

function inboxVisibleTo({ sessionUserId, notifications }) {
  return notifications.filter((row) => row.recipientUserId === sessionUserId);
}

describe('specification: KYC notification rules (no database)', () => {
  it('builds an approved KYC notification for the customer', () => {
    const ntf = buildKycNotification({
      action: 'APPROVE',
      comment: null,
      docTypeName: 'Aadhaar Card / PAN Card',
    });
    assert.equal(ntf.typeCode, 'NTF_KYC_STATUS');
    assert.match(ntf.body, /approved/);
    assert.equal(ntf.includesComment, false);
  });

  it('includes the rejection comment for ACTION_REQUIRED', () => {
    const ntf = buildKycNotification({
      action: 'REJECT',
      comment: 'Bill unreadable',
      docTypeName: 'Latest Electricity Bill',
    });
    assert.match(ntf.body, /Bill unreadable/);
    assert.equal(ntf.includesComment, true);
  });

  it('targets only the owning customer recipient', () => {
    const recipientUserId = 42;
    const rows = inboxVisibleTo({
      sessionUserId: recipientUserId,
      notifications: [
        { notificationId: '1', recipientUserId: 42, typeCode: 'NTF_KYC_STATUS' },
        { notificationId: '2', recipientUserId: 99, typeCode: 'NTF_KYC_STATUS' },
      ],
    });
    assert.deepEqual(rows.map((row) => row.notificationId), ['1']);
  });

  it('skips notification when status did not change (retry)', () => {
    assert.equal(
      shouldNotifyKyc({
        prevStatusId: 10,
        targetStatusId: 10,
        recipient: { activeInd: true, accountCode: 'ACCT_ACTIVE' },
      }),
      false,
    );
  });

  it('skips inbox creation for inactive or suspended recipients', () => {
    assert.equal(
      shouldNotifyKyc({
        prevStatusId: 1,
        targetStatusId: 2,
        recipient: { activeInd: false, accountCode: 'ACCT_ACTIVE' },
      }),
      false,
    );
    assert.equal(
      shouldNotifyKyc({
        prevStatusId: 1,
        targetStatusId: 2,
        recipient: { activeInd: true, accountCode: 'ACCT_SUSPENDED' },
      }),
      false,
    );
  });

  it('notifies when status changes for an active recipient', () => {
    assert.equal(
      shouldNotifyKyc({
        prevStatusId: 1,
        targetStatusId: 2,
        recipient: { activeInd: true, accountCode: 'ACCT_ACTIVE' },
      }),
      true,
    );
  });
});

describe('SQL source: notification functions', () => {
  it('registers create/get/update before KYC update in the loader', () => {
    assert.match(loader, /fn_create_notification_details\.sql/);
    assert.match(loader, /fn_get_notification_details\.sql/);
    assert.match(loader, /fn_update_notification_details\.sql/);
    const createAt = loader.indexOf('fn_create_notification_details.sql');
    const kycUpdateAt = loader.indexOf('fn_update_kyc_document_details.sql');
    assert.ok(createAt >= 0 && kycUpdateAt > createAt);
  });

  it('creates inbox rows and optional push PENDING delivery', () => {
    assert.match(createSource, /NOTIFICATION_TYPES/);
    assert.match(createSource, /NTF_CH_PUSH/);
    assert.match(createSource, /NTF_DEL_PENDING/);
    assert.match(createSource, /push_notifications_enabled/);
    assert.match(createSource, /Recipient cannot receive notifications/);
    assert.doesNotMatch(createSource, /CREATE TRIGGER/);
  });

  it('scopes inbox list and mark-read to the session recipient', () => {
    assert.match(getSource, /recipient_user_id = v_user_id/);
    assert.match(getSource, /unread_count/);
    assert.match(getSource, /p_payload->>'recipient_user_id'/);
    assert.match(updateSource, /MARK_READ/);
    assert.match(updateSource, /MARK_ALL_READ/);
    assert.match(updateSource, /recipient_user_id = v_user_id/);
    assert.doesNotMatch(getSource, /CREATE TRIGGER/);
  });

  it('integrates KYC approve/reject with atomic notification enqueue', () => {
    assert.match(kycUpdateSource, /fn_create_notification_details/);
    assert.match(kycUpdateSource, /NTF_KYC_STATUS/);
    assert.match(kycUpdateSource, /v_prev_status_id IS DISTINCT FROM v_target_status_id/);
    assert.match(kycUpdateSource, /KYC notification enqueue failed/);
    assert.match(kycUpdateSource, /rejection_comment/);
    assert.match(kycUpdateSource, /ROLE_ADMIN/);
  });
});
