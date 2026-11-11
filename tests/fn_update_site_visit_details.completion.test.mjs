// Specification and SQL-source tests for site-visit completion.
// These tests do not connect to PostgreSQL and do not execute
// solar_app.fn_update_site_visit_details. The function was not installed.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const source = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_update_site_visit_details.sql'),
  'utf8',
);
const loader = readFileSync(join(root, 'SQLScripts/02_functions.sql'), 'utf8');

function completionDecision({ coverage, freeSlab, reservation, visitStatus }) {
  if (visitStatus === 'VISIT_COMPLETED') return { complete: false, consume: false, reason: 'duplicate' };
  if (['VISIT_CANCELLED', 'VISIT_NO_SHOW'].includes(visitStatus)) {
    return { complete: false, consume: false, reason: 'closed' };
  }
  const freeAgrees = freeSlab === (coverage === 'FREE_SLAB');
  if (!freeAgrees || !['FREE_SLAB', 'AMC_CREDIT', 'PAID_SLAB'].includes(coverage)) {
    return { complete: false, consume: false, reason: 'conflict' };
  }
  if (coverage === 'AMC_CREDIT') {
    if (reservation !== 'RESERVED') return { complete: false, consume: false, reason: 'conflict' };
    return { complete: true, consume: true, reason: 'amc' };
  }
  if (reservation != null) return { complete: false, consume: false, reason: 'conflict' };
  return { complete: true, consume: false, reason: coverage };
}

function milestoneOnComplete(status) {
  if (status === 'MS_DUE' || status === 'MS_BOOKED') return 'MS_COMPLETED';
  return status;
}

describe('specification: visit completion (no database)', () => {
  it('consumes the reserved credit only for an AMC quote', () => {
    assert.deepEqual(
      completionDecision({ coverage: 'AMC_CREDIT', freeSlab: false, reservation: 'RESERVED', visitStatus: 'VISIT_SCHEDULED' }),
      { complete: true, consume: true, reason: 'amc' },
    );
  });

  it('does not consume a credit for a free slab or a paid slab', () => {
    assert.equal(
      completionDecision({ coverage: 'FREE_SLAB', freeSlab: true, reservation: null, visitStatus: null }).consume,
      false,
    );
    assert.equal(
      completionDecision({ coverage: 'PAID_SLAB', freeSlab: false, reservation: null, visitStatus: null }).consume,
      false,
    );
  });

  it('refuses when the quote and the reservation disagree', () => {
    assert.equal(
      completionDecision({ coverage: 'FREE_SLAB', freeSlab: true, reservation: 'RESERVED', visitStatus: null }).reason,
      'conflict',
    );
    assert.equal(
      completionDecision({ coverage: 'AMC_CREDIT', freeSlab: false, reservation: null, visitStatus: null }).reason,
      'conflict',
    );
    assert.equal(
      completionDecision({ coverage: 'PAID_SLAB', freeSlab: false, reservation: 'RESERVED', visitStatus: null }).reason,
      'conflict',
    );
    assert.equal(
      completionDecision({ coverage: 'FREE_SLAB', freeSlab: false, reservation: null, visitStatus: null }).reason,
      'conflict',
    );
  });

  it('does not consume another credit when the visit is already completed', () => {
    assert.deepEqual(
      completionDecision({ coverage: 'AMC_CREDIT', freeSlab: false, reservation: 'CONSUMED', visitStatus: 'VISIT_COMPLETED' }),
      { complete: false, consume: false, reason: 'duplicate' },
    );
  });

  it('does not reopen a completed or lapsed milestone', () => {
    assert.equal(milestoneOnComplete('MS_DUE'), 'MS_COMPLETED');
    assert.equal(milestoneOnComplete('MS_BOOKED'), 'MS_COMPLETED');
    assert.equal(milestoneOnComplete('MS_COMPLETED'), 'MS_COMPLETED');
    assert.equal(milestoneOnComplete('MS_LAPSED'), 'MS_LAPSED');
  });
});

describe('SQL source contract (no database, function not executed)', () => {
  it('copies the confirmed quote and consumes the reserved row by id', () => {
    assert.match(source, /charge_amount = v_quoted_amount/);
    assert.match(source, /currency_code = v_quoted_currency/);
    assert.match(source, /visit_charge_slab_id = v_quoted_slab_id/);
    assert.match(source, /charge_rule_snapshot_json = v_quote_snapshot/);
    assert.match(source, /amc_credit_reservation_id = v_reservation_id/);
    assert.match(source, /reservation_status = 'RESERVED'/);
    assert.match(source, /reservation_status = 'CONSUMED'/);
    assert.doesNotMatch(source, /fn_get_site_visit_charge/);
    assert.doesNotMatch(source, /COUNT\(\*\)\s*\+\s*1/i);
    assert.doesNotMatch(source, /p_payload->>'(amc_contract_id|quoted_charge_amount|reservation_status)'/);
  });

  it('uses the one-visit constraint and does not reopen closed records', () => {
    assert.match(source, /WHEN unique_violation THEN/);
    assert.match(source, /'VISIT_COMPLETED'/);
    assert.match(source, /'SR_COMPLETED'/);
    assert.match(source, /v_milestone_status IN \('MS_DUE', 'MS_BOOKED'\)/);
    assert.doesNotMatch(source, /claim_window_end_on\s*=/);
    assert.match(source, /request\.customer_id = v_customer_id/);
  });

  it('locks only the visit row when reading status through a LEFT JOIN', () => {
    assert.match(
      source,
      /FROM solar_app\.site_visit_details AS visit\s+LEFT JOIN solar_app\.ref_data AS visit_status[\s\S]*?FOR UPDATE OF visit;/,
    );
    assert.doesNotMatch(
      source,
      /FROM solar_app\.site_visit_details AS visit\s+LEFT JOIN solar_app\.ref_data AS visit_status[\s\S]*?FOR UPDATE;/,
    );
  });

  it('loads after the booking lifecycle functions', () => {
    const booking = loader.indexOf('solar_app.fn_update_service_request_details.sql');
    const visit = loader.indexOf('solar_app.fn_update_site_visit_details.sql');
    assert.ok(booking > 0);
    assert.ok(visit > booking);
  });
});
