// Specification and SQL-source tests for confirmed booking and credit reservation.
// These tests do not connect to PostgreSQL and do not execute
// solar_app.fn_create_service_request_details. The function was not installed.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const source = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_create_service_request_details.sql'),
  'utf8',
);
const loader = readFileSync(join(root, 'SQLScripts/02_functions.sql'), 'utf8');

function nextCreditSeq(allowance, heldSequences) {
  for (let seq = 1; seq <= allowance; seq += 1) {
    if (!heldSequences.includes(seq)) return seq;
  }
  return null;
}

function bookingDecision({
  quoteStatus,
  entitlementReason,
  pricingConfigured = true,
  freeSlab,
  creditSeq,
}) {
  const quoted = quoteStatus === 'AVAILABLE' && entitlementReason !== 'CREDIT_HOLD_UNAVAILABLE';
  if (!quoted) {
    if (pricingConfigured === false && quoteStatus !== 'AVAILABLE') {
      return {
        book: true,
        coverage: null,
        reserve: false,
        quotedAmount: null,
        quoteConfirmed: false,
      };
    }
    return { book: false };
  }
  if (freeSlab) {
    return { book: true, coverage: 'FREE_SLAB', reserve: false, quotedAmount: 'slab', quoteConfirmed: true };
  }
  if (creditSeq != null) {
    return { book: true, coverage: 'AMC_CREDIT', reserve: true, quotedAmount: 0, quoteConfirmed: true };
  }
  return { book: true, coverage: 'PAID_SLAB', reserve: false, quotedAmount: 'slab', quoteConfirmed: true };
}

describe('specification: booking coverage (no database)', () => {
  it('does not book when the fee is unavailable', () => {
    assert.deepEqual(
      bookingDecision({ quoteStatus: 'UNAVAILABLE', entitlementReason: 'DISTANCE_UNKNOWN', freeSlab: false, creditSeq: null }),
      { book: false },
    );
  });

  it('does not substitute a paid booking when the credit hold cannot be checked', () => {
    assert.equal(
      bookingDecision({
        quoteStatus: 'AVAILABLE',
        entitlementReason: 'CREDIT_HOLD_UNAVAILABLE',
        freeSlab: false,
        creditSeq: null,
      }).book,
      false,
    );
  });

  it('does not reserve a credit for a free pricing slab', () => {
    assert.deepEqual(
      bookingDecision({ quoteStatus: 'AVAILABLE', entitlementReason: 'FREE_PRICING_SLAB', freeSlab: true, creditSeq: 1 }),
      { book: true, coverage: 'FREE_SLAB', reserve: false, quotedAmount: 'slab', quoteConfirmed: true },
    );
  });

  it('reserves one exact sequence and stores a zero confirmed quote', () => {
    assert.deepEqual(
      bookingDecision({ quoteStatus: 'AVAILABLE', entitlementReason: 'WITHIN_SNAPSHOT_ALLOWANCE', freeSlab: false, creditSeq: 1 }),
      { book: true, coverage: 'AMC_CREDIT', reserve: true, quotedAmount: 0, quoteConfirmed: true },
    );
  });

  it('books the paid slab when no sequence remains', () => {
    assert.deepEqual(
      bookingDecision({ quoteStatus: 'AVAILABLE', entitlementReason: 'NO_CREDIT_REMAINING', freeSlab: false, creditSeq: null }),
      { book: true, coverage: 'PAID_SLAB', reserve: false, quotedAmount: 'slab', quoteConfirmed: true },
    );
  });

  it('books without a fee when approved office or slab configuration is absent', () => {
    assert.deepEqual(
      bookingDecision({
        quoteStatus: 'UNAVAILABLE',
        entitlementReason: 'DISTANCE_UNKNOWN',
        pricingConfigured: false,
        freeSlab: false,
        creditSeq: null,
      }),
      { book: true, coverage: null, reserve: false, quotedAmount: null, quoteConfirmed: false },
    );
  });

  it('does not book an unverified fee when pricing configuration exists', () => {
    assert.deepEqual(
      bookingDecision({
        quoteStatus: 'UNAVAILABLE',
        entitlementReason: 'MISSING_SITE_COORDINATES',
        pricingConfigured: true,
        freeSlab: false,
        creditSeq: null,
      }),
      { book: false },
    );
  });

  it('does not replace an available quote with an unpriced booking when the credit hold is unknown', () => {
    assert.equal(
      bookingDecision({
        quoteStatus: 'AVAILABLE',
        entitlementReason: 'CREDIT_HOLD_UNAVAILABLE',
        pricingConfigured: false,
        freeSlab: false,
        creditSeq: null,
      }).book,
      false,
    );
  });

  it('reuses the lowest released sequence instead of adding one to the held count', () => {
    const held = [2];
    assert.equal(nextCreditSeq(2, held), 1);
    assert.notEqual(nextCreditSeq(2, held), held.length + 1);
    assert.equal(nextCreditSeq(2, [1, 2]), null);
  });

  it('keeps the claim-by date itself claimable', () => {
    const claimEnd = '2026-11-02';
    const preferredOn = '2026-11-02';
    assert.equal(preferredOn > claimEnd, false);
    assert.equal('2026-11-03' > claimEnd, true);
  });
});

describe('SQL source contract (no database, function not executed)', () => {
  it('calls the fee function before writing and ignores client price authority', () => {
    const feeCall = source.indexOf('solar_app.fn_get_site_visit_charge');
    const requestInsert = source.indexOf('INSERT INTO solar_app.service_request_details');
    assert.ok(feeCall > 0);
    assert.ok(feeCall < requestInsert);
    assert.match(source, /'visit_on', to_char\(v_preferred_on, 'YYYY-MM-DD'\)/);
    assert.doesNotMatch(source, /p_payload->>'quoted_charge_amount'/);
    assert.doesNotMatch(source, /p_payload->>'amc_contract_id'/);
    assert.doesNotMatch(source, /p_payload->>'credit_seq'/);
    assert.doesNotMatch(source, /ref_amc_plans/);
  });

  it('locks the contract and allocates a free sequence without adding one to a count', () => {
    assert.match(source, /FOR UPDATE/);
    assert.match(source, /generate_series\(1, v_allowance\)/);
    assert.match(source, /reservation_status IN \('RESERVED', 'CONSUMED'\)/);
    assert.match(source, /'RESERVED'/);
    assert.doesNotMatch(source, /COUNT\(\*\)\s*\+\s*1/i);
    assert.match(source, /WHEN unique_violation THEN/);
  });

  it('stores the quote and rolls milestone races back with the request', () => {
    assert.match(source, /quoted_charge_amount/);
    assert.match(source, /fee_quote_snapshot_json/);
    assert.match(source, /quote_confirmed_on/);
    assert.match(source, /left\(office\.office_code, 4\) IS DISTINCT FROM 'DEV_'/);
    assert.match(source, /slab\.created_by IS DISTINCT FROM 'DEV_SEED'/);
    assert.match(source, /v_unquoted/);
    assert.match(source, /CASE WHEN v_unquoted THEN NULL ELSE clock_timestamp\(\) END/);
    assert.match(source, /'quote_confirmed', NOT v_unquoted/);
    assert.match(source, /v_preferred_on > v_claim_end/);
    assert.match(source, /MS_DUE/);
    assert.match(source, /ERRCODE = 'P0001'/);
    assert.match(source, /data_code = 'SR_OPEN'/);
  });

  it('loads the fee function before the booking function', () => {
    const fee = loader.indexOf('solar_app.fn_get_site_visit_charge.sql');
    const booking = loader.indexOf('solar_app.fn_create_service_request_details.sql');
    assert.ok(fee > 0);
    assert.ok(fee < booking);
  });
});
