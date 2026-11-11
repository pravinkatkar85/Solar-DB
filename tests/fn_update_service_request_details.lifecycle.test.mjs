// Specification and SQL-source tests for cancel, lapse, and reschedule.
// These tests do not connect to PostgreSQL and do not execute
// solar_app.fn_update_service_request_details. The function was not installed.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const source = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_update_service_request_details.sql'),
  'utf8',
);
const loader = readFileSync(join(root, 'SQLScripts/02_functions.sql'), 'utf8');

function closeBooking({ requestStatus, visitCompleted, reservation }) {
  const closed = ['SR_COMPLETED', 'SR_CANCELLED', 'SR_LAPSED'].includes(requestStatus)
    || visitCompleted
    || reservation === 'CONSUMED';
  if (closed) return { change: false, release: false };
  return { change: true, release: reservation === 'RESERVED' };
}

function milestoneAfterClose({ milestoneStatus, claimEnd, today, otherActive }) {
  if (milestoneStatus === 'MS_COMPLETED') {
    return { status: 'MS_COMPLETED', link: 'unchanged', claimEnd };
  }
  if (otherActive) return { status: milestoneStatus, link: 'kept', claimEnd };
  return {
    status: claimEnd < today ? 'MS_LAPSED' : 'MS_DUE',
    link: 'cleared',
    claimEnd,
  };
}

function rescheduleDecision({
  quoteAvailable,
  confirmedAmount,
  serverAmount,
  confirmedSlab = 10,
  serverSlab = 10,
}) {
  if (!quoteAvailable) return { apply: false, confirmationRequired: false };
  if (confirmedAmount == null || confirmedSlab == null) {
    return { apply: false, confirmationRequired: true };
  }
  if (confirmedAmount !== serverAmount || confirmedSlab !== serverSlab) {
    return { apply: false, confirmationRequired: true };
  }
  return { apply: true, confirmationRequired: false };
}

describe('specification: cancel, lapse, and reschedule (no database)', () => {
  it('releases only a reserved credit on an uncompleted booking', () => {
    assert.deepEqual(
      closeBooking({ requestStatus: 'SR_OPEN', visitCompleted: false, reservation: 'RESERVED' }),
      { change: true, release: true },
    );
    assert.deepEqual(
      closeBooking({ requestStatus: 'SR_ASSIGNED', visitCompleted: false, reservation: null }),
      { change: true, release: false },
    );
  });

  it('does not release a consumed credit or a completed visit', () => {
    assert.equal(
      closeBooking({ requestStatus: 'SR_OPEN', visitCompleted: false, reservation: 'CONSUMED' }).change,
      false,
    );
    assert.equal(
      closeBooking({ requestStatus: 'SR_OPEN', visitCompleted: true, reservation: 'RESERVED' }).release,
      false,
    );
    assert.equal(
      closeBooking({ requestStatus: 'SR_COMPLETED', visitCompleted: false, reservation: 'RESERVED' }).change,
      false,
    );
  });

  it('sets the milestone from the claim window and leaves a completed milestone alone', () => {
    assert.deepEqual(
      milestoneAfterClose({ milestoneStatus: 'MS_DUE', claimEnd: '2026-11-02', today: '2026-11-02', otherActive: false }),
      { status: 'MS_DUE', link: 'cleared', claimEnd: '2026-11-02' },
    );
    assert.equal(
      milestoneAfterClose({ milestoneStatus: 'MS_DUE', claimEnd: '2026-11-01', today: '2026-11-02', otherActive: false }).status,
      'MS_LAPSED',
    );
    assert.equal(
      milestoneAfterClose({ milestoneStatus: 'MS_COMPLETED', claimEnd: '2026-11-01', today: '2026-11-02', otherActive: false }).status,
      'MS_COMPLETED',
    );
    assert.equal(
      milestoneAfterClose({ milestoneStatus: 'MS_BOOKED', claimEnd: '2026-11-01', today: '2026-11-02', otherActive: true }).link,
      'kept',
    );
  });

  it('applies a reschedule only when the confirmed amount matches the server fee', () => {
    assert.deepEqual(
      rescheduleDecision({ quoteAvailable: true, confirmedAmount: null, serverAmount: 0 }),
      { apply: false, confirmationRequired: true },
    );
    assert.deepEqual(
      rescheduleDecision({ quoteAvailable: true, confirmedAmount: 750, serverAmount: 0 }),
      { apply: false, confirmationRequired: true },
    );
    assert.deepEqual(
      rescheduleDecision({ quoteAvailable: true, confirmedAmount: 0, serverAmount: 0 }),
      { apply: true, confirmationRequired: false },
    );
    assert.equal(
      rescheduleDecision({ quoteAvailable: false, confirmedAmount: 0, serverAmount: 0 }).apply,
      false,
    );
    assert.deepEqual(
      rescheduleDecision({
        quoteAvailable: true,
        confirmedAmount: 750,
        serverAmount: 750,
        confirmedSlab: 4,
        serverSlab: 9,
      }),
      { apply: false, confirmationRequired: true },
    );
  });
});

describe('SQL source contract (no database, function not executed)', () => {
  it('releases reserved rows only and does not move the claim window or a completed milestone', () => {
    assert.match(source, /reservation_status = 'RESERVED'/);
    assert.match(source, /SET reservation_status = 'RELEASED'/);
    assert.doesNotMatch(source, /reservation_status = 'CONSUMED'[\s\S]{0,120}RELEASED/);
    assert.match(source, /v_milestone_status IS DISTINCT FROM 'MS_COMPLETED'/);
    assert.match(source, /'MS_LAPSED'/);
    assert.match(source, /'MS_DUE'/);
    assert.doesNotMatch(source, /claim_window_end_on\s*=/);
    assert.match(source, /v_claim_end < CURRENT_DATE/);
    assert.match(source, /v_preferred_on > v_claim_end/);
  });

  it('confirms the recalculated fee before writing a reschedule', () => {
    const feeCall = source.indexOf('solar_app.fn_get_site_visit_charge');
    const confirmCheck = source.indexOf('v_confirmed_amount IS DISTINCT FROM v_quoted_amount');
    const slabCheck = source.indexOf('v_confirmed_slab_id IS DISTINCT FROM v_slab_id');
    const quoteUpdate = source.indexOf('quoted_charge_amount = v_quoted_amount');
    assert.ok(feeCall > 0);
    assert.ok(confirmCheck > feeCall);
    assert.ok(slabCheck > confirmCheck);
    assert.ok(quoteUpdate > slabCheck);
    assert.match(source, /confirmation_required/);
    assert.match(source, /confirmed_visit_charge_slab_id/);
    assert.match(source, /WHEN unique_violation THEN/);
    assert.doesNotMatch(source, /p_payload->>'quoted_charge_amount'/);
    assert.doesNotMatch(source, /p_payload->>'amc_contract_id'/);
    assert.match(source, /generate_series\(1, v_allowance\)/);
    assert.match(source, /IS DISTINCT FROM v_reservation_id/);
  });

  it('loads after booking and keeps the customer scope on the locked request', () => {
    const booking = loader.indexOf('solar_app.fn_create_service_request_details.sql');
    const update = loader.indexOf('solar_app.fn_update_service_request_details.sql');
    assert.ok(booking > 0);
    assert.ok(update > booking);
    assert.match(source, /request\.customer_id = v_customer_id/);
    assert.match(source, /FOR UPDATE/);
    assert.match(source, /data_code NOT IN \('SR_CANCELLED', 'SR_LAPSED'\)/);
  });
});
