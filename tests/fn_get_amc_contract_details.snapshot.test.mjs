// Specification and SQL-source tests for snapshot entitlement display.
// These tests do not connect to PostgreSQL and do not execute
// solar_app.fn_get_amc_contract_details.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const source = readFileSync(
  join(root, 'DB-Objects/SQLFunctions/solar_app.fn_get_amc_contract_details.sql'),
  'utf8',
);

function wholeCount(value) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) return null;
  if (value !== Math.trunc(value)) return null;
  return value;
}

function radiusKm(value) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) return null;
  return value;
}

function displayedAllowance(snapshot, livePlan) {
  const stored = snapshot ?? {};
  return {
    freeVisitCount: Object.hasOwn(stored, 'free_visit_count') ? wholeCount(stored.free_visit_count) : null,
    freeVisitRadiusKm: Object.hasOwn(stored, 'free_visit_radius_km') ? radiusKm(stored.free_visit_radius_km) : null,
    livePlanIgnored: livePlan,
  };
}

describe('specification: snapshot allowance on the coverage list (no database)', () => {
  it('uses snapshot count and radius and does not fall back to the live plan', () => {
    assert.deepEqual(
      displayedAllowance(
        { free_visit_count: 2, free_visit_radius_km: 10 },
        { free_visit_count: 9, free_visit_radius_km: 50 },
      ),
      { freeVisitCount: 2, freeVisitRadiusKm: 10, livePlanIgnored: { free_visit_count: 9, free_visit_radius_km: 50 } },
    );
  });

  it('returns null when a snapshot key is missing or unusable', () => {
    assert.deepEqual(
      displayedAllowance({}, { free_visit_count: 4, free_visit_radius_km: 25 }),
      { freeVisitCount: null, freeVisitRadiusKm: null, livePlanIgnored: { free_visit_count: 4, free_visit_radius_km: 25 } },
    );
    assert.equal(displayedAllowance({ free_visit_count: '2', free_visit_radius_km: 10 }).freeVisitCount, null);
    assert.equal(displayedAllowance({ free_visit_count: 1.5, free_visit_radius_km: -1 }).freeVisitRadiusKm, null);
  });
});

describe('SQL source contract (no database, function not executed)', () => {
  it('reads the two entitlement fields from the snapshot and keeps expiry order', () => {
    assert.match(source, /plan_snapshot_json->'free_visit_count'/);
    assert.match(source, /plan_snapshot_json->'free_visit_radius_km'/);
    assert.doesNotMatch(source, /plan\.free_visit_count/);
    assert.doesNotMatch(source, /plan\.free_visit_radius_km/);
    assert.match(source, /plan\.includes_cleaning/);
    assert.match(source, /ORDER BY listed\.expiry_on, listed\.site_name/);
  });
});
