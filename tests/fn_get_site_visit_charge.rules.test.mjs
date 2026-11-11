// Specification tests for the visit-fee rules.
// These tests do not connect to PostgreSQL and do not execute
// solar_app.fn_get_site_visit_charge. The SQL function was not installed.
//
// The decision helpers below mirror the authored SQL. A separate group
// checks that the SQL source still contains those predicates.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const source = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_get_site_visit_charge.sql'),
  'utf8',
);
const loader = readFileSync(join(root, 'SQLScripts/02_functions.sql'), 'utf8');

function roundHalfAwayFromZero(value, digits) {
  const negative = value.startsWith('-');
  const unsigned = negative ? value.slice(1) : value;
  const [whole, fraction = ''] = unsigned.split('.');
  const padded = `${fraction}${'0'.repeat(digits + 1)}`;
  let rounded = BigInt(`${whole}${padded.slice(0, digits)}`);
  if (padded[digits] >= '5') rounded += 1n;
  const raw = rounded.toString().padStart(digits + 1, '0');
  const point = raw.length - digits;
  const rendered = `${raw.slice(0, point)}.${raw.slice(point)}`;
  return negative ? `-${rendered}` : rendered;
}

function haversineKm(lat1, lon1, lat2, lon2) {
  const toRadians = (degrees) => degrees * Math.PI / 180;
  const latitudeDelta = toRadians(lat2 - lat1);
  const longitudeDelta = toRadians(lon2 - lon1);
  const chord = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) * Math.sin(longitudeDelta / 2) ** 2;
  const arc = 2 * Math.asin(Math.min(1, Math.sqrt(chord)));
  return roundHalfAwayFromZero((6371 * arc).toFixed(8), 2);
}

function selectContract(contracts, visitOn) {
  return contracts
    .filter((contract) => contract.active
      && contract.status === 'ACTIVE'
      && contract.startOn <= visitOn
      && contract.expiryOn >= visitOn)
    .sort((left, right) => right.startOn.localeCompare(left.startOn) || right.id - left.id)[0] ?? null;
}

function slabMatches(slab, visitOn, distanceKm, { purposeId, specific }) {
  if (!slab.active || slab.createdBy === 'DEV_SEED') return false;
  if (visitOn < slab.effectiveFrom) return false;
  if (slab.effectiveTo != null && visitOn > slab.effectiveTo) return false;
  if (distanceKm < slab.minKm) return false;
  if (slab.maxKm != null && distanceKm >= slab.maxKm) return false;
  return specific ? slab.purposeId === purposeId : slab.purposeId == null;
}

function selectSlab(slabs, visitOn, distanceKm, purposeId) {
  if (purposeId != null) {
    const specific = slabs.filter((slab) => slabMatches(slab, visitOn, distanceKm, { purposeId, specific: true }));
    if (specific.length > 1) return { quoteStatus: 'UNAVAILABLE', unavailableReason: 'AMBIGUOUS_SLAB' };
    if (specific.length === 1) return { quoteStatus: 'AVAILABLE', slab: specific[0] };
  }
  const general = slabs.filter((slab) => slabMatches(slab, visitOn, distanceKm, { purposeId, specific: false }));
  if (general.length > 1) return { quoteStatus: 'UNAVAILABLE', unavailableReason: 'AMBIGUOUS_SLAB' };
  if (general.length === 1) return { quoteStatus: 'AVAILABLE', slab: general[0] };
  return { quoteStatus: 'UNAVAILABLE', unavailableReason: 'MISSING_SLAB' };
}

function entitlement({ snapshot, distanceKm, heldCount, creditsKnown, freeSlab }) {
  if (freeSlab) return { eligible: false, reason: 'FREE_PRICING_SLAB' };
  if (!snapshot) return { eligible: false, reason: 'NO_ELIGIBLE_CONTRACT' };
  const count = snapshot.free_visit_count;
  const radius = snapshot.free_visit_radius_km;
  if (!Object.hasOwn(snapshot, 'free_visit_count') || count == null) {
    return { eligible: false, reason: 'MISSING_SNAPSHOT_COUNT' };
  }
  if (typeof count !== 'number' || count < 0 || !Number.isInteger(count)) {
    return { eligible: false, reason: 'INVALID_SNAPSHOT' };
  }
  if (!Object.hasOwn(snapshot, 'free_visit_radius_km') || radius == null) {
    return { eligible: false, reason: 'MISSING_SNAPSHOT_RADIUS' };
  }
  if (typeof radius !== 'number' || radius < 0) {
    return { eligible: false, reason: 'INVALID_SNAPSHOT' };
  }
  if (distanceKm == null) return { eligible: false, reason: 'DISTANCE_UNKNOWN' };
  if (distanceKm > Number(roundHalfAwayFromZero(radius.toFixed(8), 2))) {
    return { eligible: false, reason: 'OUTSIDE_SNAPSHOT_RADIUS' };
  }
  if (!creditsKnown) return { eligible: false, reason: 'CREDIT_HOLD_UNAVAILABLE' };
  const available = Math.max(0, count - heldCount);
  if (available <= 0) return { eligible: false, reason: 'NO_CREDIT_REMAINING', available };
  return { eligible: true, reason: 'WITHIN_SNAPSHOT_ALLOWANCE', available };
}

describe('specification: distance rounding before slab comparison (no database)', () => {
  it('rounds half away from zero to two decimals', () => {
    assert.equal(roundHalfAwayFromZero('9.995', 2), '10.00');
    assert.equal(roundHalfAwayFromZero('9.994', 2), '9.99');
    assert.equal(roundHalfAwayFromZero('1.005', 2), '1.01');
  });

  it('uses the rounded distance on a half-open band', () => {
    const slabs = [
      { id: 1, purposeId: null, minKm: 0, maxKm: 10, active: true, createdBy: 'SYSTEM', effectiveFrom: '2026-01-01', effectiveTo: null },
      { id: 2, purposeId: null, minKm: 10, maxKm: 25, active: true, createdBy: 'SYSTEM', effectiveFrom: '2026-01-01', effectiveTo: null },
    ];
    const rounded = Number(roundHalfAwayFromZero('9.995', 2));
    const selected = selectSlab(slabs, '2026-11-02', rounded, null);
    assert.equal(selected.slab.id, 2);
  });

  it('keeps an exact upper bound in the next band', () => {
    const slabs = [
      { id: 1, purposeId: null, minKm: 0, maxKm: 10, active: true, createdBy: 'SYSTEM', effectiveFrom: '2026-01-01', effectiveTo: null },
      { id: 2, purposeId: null, minKm: 10, maxKm: null, active: true, createdBy: 'SYSTEM', effectiveFrom: '2026-01-01', effectiveTo: null },
    ];
    assert.equal(selectSlab(slabs, '2026-11-02', 10, null).slab.id, 2);
    assert.equal(selectSlab(slabs, '2026-11-02', 9.99, null).slab.id, 1);
  });

  it('calculates a zero distance and a one-degree equator arc with radius 6371', () => {
    assert.equal(haversineKm(18.52, 73.85, 18.52, 73.85), '0.00');
    assert.equal(haversineKm(0, 0, 0, 1), '111.19');
  });
});

describe('specification: contract, snapshot, and slab rules (no database)', () => {
  const contracts = [
    { id: 4, active: true, status: 'ACTIVE', startOn: '2026-01-01', expiryOn: '2026-12-31' },
    { id: 9, active: true, status: 'ACTIVE', startOn: '2026-06-01', expiryOn: '2027-05-31' },
    { id: 8, active: true, status: 'ACTIVE', startOn: '2026-06-01', expiryOn: '2027-05-31' },
    { id: 3, active: true, status: 'EXPIRED', startOn: '2026-08-01', expiryOn: '2027-07-31' },
    { id: 2, active: false, status: 'ACTIVE', startOn: '2026-09-01', expiryOn: '2027-08-31' },
  ];

  it('chooses the latest start date, then the greatest contract id', () => {
    assert.equal(selectContract(contracts, '2026-07-01').id, 9);
  });

  it('ignores a contract outside the proposed date', () => {
    assert.equal(selectContract(contracts, '2026-03-01').id, 4);
    assert.equal(selectContract(contracts, '2025-12-31'), null);
  });

  it('treats a missing snapshot key as unavailable and does not substitute another count', () => {
    assert.deepEqual(
      entitlement({ snapshot: { free_visit_radius_km: 10 }, distanceKm: 4, heldCount: 0, creditsKnown: true }),
      { eligible: false, reason: 'MISSING_SNAPSHOT_COUNT' },
    );
    assert.equal(
      entitlement({ snapshot: { free_visit_count: 2 }, distanceKm: 4, heldCount: 0, creditsKnown: true }).reason,
      'MISSING_SNAPSHOT_RADIUS',
    );
  });

  it('rejects a text snapshot count', () => {
    assert.equal(
      entitlement({
        snapshot: { free_visit_count: '2', free_visit_radius_km: 10 },
        distanceKm: 4,
        heldCount: 0,
        creditsKnown: true,
      }).reason,
      'INVALID_SNAPSHOT',
    );
  });

  it('reports no remaining credit without inventing one', () => {
    const result = entitlement({
      snapshot: { free_visit_count: 2, free_visit_radius_km: 10 },
      distanceKm: 10,
      heldCount: 2,
      creditsKnown: true,
    });
    assert.equal(result.reason, 'NO_CREDIT_REMAINING');
    assert.equal(result.available, 0);
  });

  it('does not call a credit eligible when the distance cannot be calculated', () => {
    assert.equal(
      entitlement({
        snapshot: { free_visit_count: 2, free_visit_radius_km: 10 },
        distanceKm: null,
        heldCount: 0,
        creditsKnown: true,
      }).reason,
      'DISTANCE_UNKNOWN',
    );
  });

  it('prefers one purpose slab over a general slab and honours effective dates', () => {
    const slabs = [
      { id: 10, purposeId: null, minKm: 0, maxKm: null, active: true, createdBy: 'SYSTEM', effectiveFrom: '2026-01-01', effectiveTo: null },
      { id: 11, purposeId: 30, minKm: 0, maxKm: null, active: true, createdBy: 'SYSTEM', effectiveFrom: '2026-06-01', effectiveTo: '2026-12-31' },
      { id: 12, purposeId: 30, minKm: 0, maxKm: null, active: true, createdBy: 'SYSTEM', effectiveFrom: '2027-01-01', effectiveTo: null },
      { id: 13, purposeId: null, minKm: 0, maxKm: null, active: true, createdBy: 'DEV_SEED', effectiveFrom: '2026-01-01', effectiveTo: null },
    ];
    assert.equal(selectSlab(slabs, '2026-11-02', 12.5, 30).slab.id, 11);
    assert.equal(selectSlab(slabs, '2026-05-01', 12.5, 30).slab.id, 10);
    assert.equal(selectSlab(slabs, '2026-11-02', 12.5, null).slab.id, 10);
  });

  it('leaves the fee unavailable when only a development slab matches', () => {
    const slabs = [
      { id: 20, purposeId: null, minKm: 0, maxKm: null, active: true, createdBy: 'DEV_SEED', effectiveFrom: '2026-01-01', effectiveTo: null },
    ];
    assert.equal(selectSlab(slabs, '2026-11-02', 4, null).unavailableReason, 'MISSING_SLAB');
  });

  it('does not consume entitlement when the selected slab is free', () => {
    assert.equal(
      entitlement({
        snapshot: { free_visit_count: 2, free_visit_radius_km: 10 },
        distanceKm: 4,
        heldCount: 0,
        creditsKnown: true,
        freeSlab: true,
      }).reason,
      'FREE_PRICING_SLAB',
    );
  });
});

describe('SQL source contract (no database, function not executed)', () => {
  it('registers the function and keeps the body read-only except the function log', () => {
    assert.match(loader, /solar_app\.fn_get_site_visit_charge\.sql/);
    const inserts = [...source.matchAll(/INSERT\s+INTO\s+solar_app\.([a-z_]+)/gi)].map((match) => match[1]);
    assert.deepEqual(inserts, ['log_sql_functions']);
    assert.doesNotMatch(source, /\b(UPDATE|DELETE)\b/i);
    assert.doesNotMatch(source, /ref_amc_plans/);
  });

  it('contains the approved distance, contract, slab, and credit predicates', () => {
    assert.match(source, /6371 \* 2 \* asin/);
    assert.match(source, /::NUMERIC, 2\)/);
    assert.match(source, /v_distance >= slab\.min_distance_km/);
    assert.match(source, /v_distance < slab\.max_distance_km/);
    assert.match(source, /ORDER BY contract\.start_on DESC, contract\.amc_contract_id DESC/);
    assert.match(source, /free_visit_count/);
    assert.match(source, /free_visit_radius_km/);
    assert.match(source, /reservation_status IN \('RESERVED', 'CONSUMED'\)/);
    assert.match(source, /created_by IS DISTINCT FROM 'DEV_SEED'/);
    assert.match(source, /left\(office\.office_code, 4\) IS DISTINCT FROM 'DEV_'/);
    assert.match(source, /to_regclass\('solar_app\.amc_credit_reservation_details'\)/);
  });
});
