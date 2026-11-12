-- =============================================================================
-- M6 Phase A — Live seed migration (SolarDB / solar_app)
-- =============================================================================
-- Purpose:
--   1) Relabel TKT_RESOLVED (preserve ref_data_id = 105)
--   2) Insert TKT_CLOSED via GENERATED ALWAYS AS IDENTITY (no forced id)
--   3) Insert COMPLAINT_MEDIA_MAX_COUNT by natural key when absent
--      (validate-only if the natural-key row already exists; never silent overwrite)
--
-- Pre-check evidence (2026-11-12, read-only):
--   MAX(ref_data_id)=187; TKT_RESOLVED=105; JOB_QUEUED=106; TKT_CLOSED absent;
--   COMPLAINT_MEDIA_MAX_COUNT absent; 11 DEV_* parameters present (ids 1–11);
--   ref_data identity next expected = 188 (do NOT hardcode; capture RETURNING).
--
-- Evidence retained in this script:
--   - created_by / updated_by are VARCHAR(50) NOT NULL DEFAULT 'SYSTEM' (01_schema.sql)
--   - Ticket status sort_order currently 1..6 (TKT_RAISED..TKT_RESOLVED); TKT_CLOSED uses 7
--
-- Safety:
--   - Mutating work in one transaction; RAISE EXCEPTION rolls back that unit
--   - Capture temp table: ON COMMIT PRESERVE ROWS (post-COMMIT reporting)
--   - No nextval / setval
--   - No OVERRIDING SYSTEM VALUE
--   - Does not rewrite DEV_* rows (different parameter_code)
--
-- EXECUTION: requires separate explicit approval.
-- =============================================================================

DROP TABLE IF EXISTS pg_temp.tmp_m6_phase_a_capture;

CREATE TEMP TABLE tmp_m6_phase_a_capture (
  step_name              text PRIMARY KEY,
  tkt_closed_ref_data_id bigint,
  tkt_closed_action      text,
  notes                  text
) ON COMMIT PRESERVE ROWS;

BEGIN;

SET LOCAL search_path TO solar_app, public;

-- Serialize against concurrent writers for the idempotent business insert window.
LOCK TABLE solar_app.ref_data IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE solar_app.ref_business_parameters IN SHARE ROW EXCLUSIVE MODE;

-- -----------------------------------------------------------------------------
-- Precondition checks (fail closed → full rollback)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_ticket_cat_cnt   integer;
  v_ticket_cat_id    bigint;
  v_resolved_cnt     integer;
  v_resolved_id      bigint;
  v_resolved_value   text;
  v_resolved_active  boolean;
  v_resolved_cat     text;
  v_queued_cnt       integer;
  v_queued_id        bigint;
  v_closed_cnt       integer;
  v_closed_id        bigint;
  v_closed_cat       text;
  v_closed_value     text;
  v_closed_active    boolean;
  v_closed_bad_cnt   integer;
BEGIN
  SELECT COUNT(*)
  INTO v_ticket_cat_cnt
  FROM solar_app.ref_data_categories AS c
  WHERE c.category_code = 'TICKET_STATUSES'
    AND c.active_ind IS TRUE;

  IF v_ticket_cat_cnt <> 1 THEN
    RAISE EXCEPTION
      'M6 Phase A precondition failed: expected exactly 1 active TICKET_STATUSES category; found %',
      v_ticket_cat_cnt;
  END IF;

  SELECT c.category_id
  INTO STRICT v_ticket_cat_id
  FROM solar_app.ref_data_categories AS c
  WHERE c.category_code = 'TICKET_STATUSES'
    AND c.active_ind IS TRUE;

  -- Exact row count for TKT_RESOLVED (all categories).
  SELECT COUNT(*)
  INTO v_resolved_cnt
  FROM solar_app.ref_data AS d
  WHERE d.data_code = 'TKT_RESOLVED';

  IF v_resolved_cnt <> 1 THEN
    RAISE EXCEPTION
      'M6 Phase A precondition failed: expected exactly 1 row with data_code TKT_RESOLVED; found %',
      v_resolved_cnt;
  END IF;

  SELECT d.ref_data_id, d.data_value, d.active_ind, c.category_code
  INTO STRICT v_resolved_id, v_resolved_value, v_resolved_active, v_resolved_cat
  FROM solar_app.ref_data AS d
  JOIN solar_app.ref_data_categories AS c
    ON c.category_id = d.category_id
  WHERE d.data_code = 'TKT_RESOLVED';

  IF v_resolved_cat IS DISTINCT FROM 'TICKET_STATUSES' THEN
    RAISE EXCEPTION
      'M6 Phase A precondition failed: TKT_RESOLVED is under category % (expected TICKET_STATUSES)',
      v_resolved_cat;
  END IF;

  IF v_resolved_id <> 105 THEN
    RAISE EXCEPTION
      'M6 Phase A precondition failed: TKT_RESOLVED ref_data_id=% (expected 105)',
      v_resolved_id;
  END IF;

  IF v_resolved_active IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION
      'M6 Phase A precondition failed: TKT_RESOLVED (105) is not active';
  END IF;

  -- Exact row count for JOB_QUEUED under JOB_STATUSES (active).
  SELECT COUNT(*)
  INTO v_queued_cnt
  FROM solar_app.ref_data AS d
  JOIN solar_app.ref_data_categories AS c
    ON c.category_id = d.category_id
  WHERE c.category_code = 'JOB_STATUSES'
    AND d.data_code = 'JOB_QUEUED'
    AND d.active_ind IS TRUE;

  IF v_queued_cnt <> 1 THEN
    RAISE EXCEPTION
      'M6 Phase A precondition failed: expected exactly 1 active JOB_QUEUED under JOB_STATUSES; found %',
      v_queued_cnt;
  END IF;

  SELECT d.ref_data_id
  INTO STRICT v_queued_id
  FROM solar_app.ref_data AS d
  JOIN solar_app.ref_data_categories AS c
    ON c.category_id = d.category_id
  WHERE c.category_code = 'JOB_STATUSES'
    AND d.data_code = 'JOB_QUEUED'
    AND d.active_ind IS TRUE;

  IF v_queued_id <> 106 THEN
    RAISE EXCEPTION
      'M6 Phase A precondition failed: JOB_QUEUED ref_data_id=% (expected 106)',
      v_queued_id;
  END IF;

  -- Validate ALL rows with data_code = TKT_CLOSED across ALL categories.
  SELECT COUNT(*)
  INTO v_closed_cnt
  FROM solar_app.ref_data AS d
  WHERE d.data_code = 'TKT_CLOSED';

  IF v_closed_cnt > 1 THEN
    RAISE EXCEPTION
      'M6 Phase A conflict: duplicate data_code TKT_CLOSED rows found (count=%)',
      v_closed_cnt;
  END IF;

  SELECT COUNT(*)
  INTO v_closed_bad_cnt
  FROM solar_app.ref_data AS d
  JOIN solar_app.ref_data_categories AS c
    ON c.category_id = d.category_id
  WHERE d.data_code = 'TKT_CLOSED'
    AND c.category_code IS DISTINCT FROM 'TICKET_STATUSES';

  IF v_closed_bad_cnt > 0 THEN
    RAISE EXCEPTION
      'M6 Phase A conflict: TKT_CLOSED exists under unexpected category (rows=%)',
      v_closed_bad_cnt;
  END IF;

  IF v_closed_cnt = 1 THEN
    SELECT d.ref_data_id, c.category_code, d.data_value, d.active_ind
    INTO STRICT v_closed_id, v_closed_cat, v_closed_value, v_closed_active
    FROM solar_app.ref_data AS d
    JOIN solar_app.ref_data_categories AS c
      ON c.category_id = d.category_id
    WHERE d.data_code = 'TKT_CLOSED';

    IF v_closed_cat IS DISTINCT FROM 'TICKET_STATUSES' THEN
      RAISE EXCEPTION
        'M6 Phase A conflict: TKT_CLOSED exists with unexpected category %',
        v_closed_cat;
    END IF;

    IF v_closed_value IS DISTINCT FROM 'Closed' THEN
      RAISE EXCEPTION
        'M6 Phase A conflict: TKT_CLOSED id=% has label % (expected Closed)',
        v_closed_id,
        v_closed_value;
    END IF;

    IF v_closed_active IS DISTINCT FROM TRUE THEN
      RAISE EXCEPTION
        'M6 Phase A conflict: TKT_CLOSED id=% exists but active_ind=%',
        v_closed_id,
        v_closed_active;
    END IF;

    INSERT INTO tmp_m6_phase_a_capture (step_name, tkt_closed_ref_data_id, tkt_closed_action, notes)
    VALUES (
      'TKT_CLOSED',
      v_closed_id,
      'already_present_validated',
      format(
        'No insert performed; existing TKT_CLOSED ref_data_id=%s validated under TICKET_STATUSES',
        v_closed_id
      )
    );
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 1) Relabel TKT_RESOLVED — preserve ref_data_id = 105 and other attributes
-- -----------------------------------------------------------------------------
UPDATE solar_app.ref_data AS d
SET
  data_value = 'Resolved – Awaiting User Confirmation',
  updated_by = 'SYSTEM',
  updated_on = CURRENT_TIMESTAMP
FROM solar_app.ref_data_categories AS c
WHERE c.category_id = d.category_id
  AND c.category_code = 'TICKET_STATUSES'
  AND d.data_code = 'TKT_RESOLVED'
  AND d.ref_data_id = 105
  AND d.active_ind IS TRUE
  AND d.data_value IS DISTINCT FROM 'Resolved – Awaiting User Confirmation';

DO $$
DECLARE
  v_cnt   integer;
  v_value text;
BEGIN
  SELECT COUNT(*)
  INTO v_cnt
  FROM solar_app.ref_data AS d
  WHERE d.ref_data_id = 105
    AND d.data_code = 'TKT_RESOLVED'
    AND d.active_ind IS TRUE;

  IF v_cnt <> 1 THEN
    RAISE EXCEPTION
      'M6 Phase A failed: expected exactly 1 active TKT_RESOLVED at id 105 after update; found %',
      v_cnt;
  END IF;

  SELECT d.data_value
  INTO STRICT v_value
  FROM solar_app.ref_data AS d
  WHERE d.ref_data_id = 105
    AND d.data_code = 'TKT_RESOLVED'
    AND d.active_ind IS TRUE;

  IF v_value IS DISTINCT FROM 'Resolved – Awaiting User Confirmation' THEN
    RAISE EXCEPTION
      'M6 Phase A failed: TKT_RESOLVED (105) label is % after update',
      v_value;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 2) Insert TKT_CLOSED via identity (no ref_data_id) when absent
--     Capture the actual id from RETURNING (never hardcode 188).
--     sort_order = 7: next after existing TICKET_STATUSES sort_order 1..6.
-- -----------------------------------------------------------------------------
WITH inserted AS (
  INSERT INTO solar_app.ref_data (
    category_id,
    data_code,
    data_value,
    data_desc,
    parent_ref_data_id,
    sort_order,
    extra_json,
    active_ind,
    created_by,
    updated_by
  )
  SELECT
    c.category_id,
    'TKT_CLOSED',
    'Closed',
    NULL,
    NULL,
    7,
    '{}'::jsonb,
    TRUE,
    'SYSTEM',
    'SYSTEM'
  FROM solar_app.ref_data_categories AS c
  WHERE c.category_code = 'TICKET_STATUSES'
    AND c.active_ind IS TRUE
    AND NOT EXISTS (
      SELECT 1
      FROM solar_app.ref_data AS x
      WHERE x.data_code = 'TKT_CLOSED'
    )
  RETURNING ref_data_id
)
INSERT INTO tmp_m6_phase_a_capture (step_name, tkt_closed_ref_data_id, tkt_closed_action, notes)
SELECT
  'TKT_CLOSED',
  inserted.ref_data_id,
  'inserted',
  format(
    'RETURNING captured live TKT_CLOSED ref_data_id=%s — freeze into stable/ref_data_id_overrides.json as TICKET_STATUSES.TKT_CLOSED',
    inserted.ref_data_id
  )
FROM inserted
ON CONFLICT (step_name) DO UPDATE
SET
  tkt_closed_ref_data_id = EXCLUDED.tkt_closed_ref_data_id,
  tkt_closed_action = EXCLUDED.tkt_closed_action,
  notes = EXCLUDED.notes;

DO $$
DECLARE
  v_closed_cnt integer;
  v_id         bigint;
  v_value      text;
  v_cat        text;
  v_action     text;
  v_capture_id bigint;
BEGIN
  SELECT COUNT(*)
  INTO v_closed_cnt
  FROM solar_app.ref_data AS d
  WHERE d.data_code = 'TKT_CLOSED';

  IF v_closed_cnt <> 1 THEN
    RAISE EXCEPTION
      'M6 Phase A failed: expected exactly 1 TKT_CLOSED row after insert-or-validate; found %',
      v_closed_cnt;
  END IF;

  SELECT d.ref_data_id, d.data_value, c.category_code
  INTO STRICT v_id, v_value, v_cat
  FROM solar_app.ref_data AS d
  JOIN solar_app.ref_data_categories AS c
    ON c.category_id = d.category_id
  WHERE d.data_code = 'TKT_CLOSED';

  IF v_cat IS DISTINCT FROM 'TICKET_STATUSES' THEN
    RAISE EXCEPTION
      'M6 Phase A failed: TKT_CLOSED id=% under unexpected category %',
      v_id,
      v_cat;
  END IF;

  IF v_value IS DISTINCT FROM 'Closed' THEN
    RAISE EXCEPTION
      'M6 Phase A failed: TKT_CLOSED id=% has unexpected label %',
      v_id,
      v_value;
  END IF;

  SELECT t.tkt_closed_action, t.tkt_closed_ref_data_id
  INTO v_action, v_capture_id
  FROM tmp_m6_phase_a_capture AS t
  WHERE t.step_name = 'TKT_CLOSED';

  IF v_action IS NULL THEN
    RAISE EXCEPTION
      'M6 Phase A failed: TKT_CLOSED id=% exists but capture row was not recorded',
      v_id;
  END IF;

  IF v_capture_id IS DISTINCT FROM v_id THEN
    RAISE EXCEPTION
      'M6 Phase A failed: capture id % does not match live TKT_CLOSED id %',
      v_capture_id,
      v_id;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 3) COMPLAINT_MEDIA_MAX_COUNT
--    - If natural-key row exists: validate expected values; do NOT overwrite.
--    - If values conflict or unexpected versions exist: RAISE (rollback).
--    - If absent: INSERT without parameter_id (identity).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_code_cnt     integer;
  v_key_cnt      integer;
  v_name         text;
  v_type         text;
  v_num          numeric;
  v_text         text;
  v_bool         boolean;
  v_json         jsonb;
  v_unit         text;
  v_desc         text;
  v_admin        boolean;
  v_effective_to date;
  v_active       boolean;
BEGIN
  SELECT COUNT(*)
  INTO v_code_cnt
  FROM solar_app.ref_business_parameters
  WHERE parameter_code = 'COMPLAINT_MEDIA_MAX_COUNT';

  SELECT COUNT(*)
  INTO v_key_cnt
  FROM solar_app.ref_business_parameters
  WHERE parameter_code = 'COMPLAINT_MEDIA_MAX_COUNT'
    AND effective_from = DATE '2026-01-01';

  IF v_code_cnt > 1 THEN
    RAISE EXCEPTION
      'M6 Phase A conflict: unexpected multiple COMPLAINT_MEDIA_MAX_COUNT versions (count=%)',
      v_code_cnt;
  END IF;

  IF v_key_cnt > 1 THEN
    RAISE EXCEPTION
      'M6 Phase A conflict: duplicate natural-key COMPLAINT_MEDIA_MAX_COUNT / 2026-01-01 rows (count=%)',
      v_key_cnt;
  END IF;

  IF v_key_cnt = 1 THEN
    SELECT
      parameter_name,
      value_type,
      numeric_value,
      text_value,
      boolean_value,
      json_value,
      parameter_unit,
      parameter_desc,
      admin_manageable_ind,
      effective_to,
      active_ind
    INTO STRICT
      v_name,
      v_type,
      v_num,
      v_text,
      v_bool,
      v_json,
      v_unit,
      v_desc,
      v_admin,
      v_effective_to,
      v_active
    FROM solar_app.ref_business_parameters
    WHERE parameter_code = 'COMPLAINT_MEDIA_MAX_COUNT'
      AND effective_from = DATE '2026-01-01';

    IF v_name IS DISTINCT FROM 'Complaint media attachment maximum'
       OR v_type IS DISTINCT FROM 'NUMERIC'
       OR v_num IS DISTINCT FROM 4
       OR v_text IS NOT NULL
       OR v_bool IS NOT NULL
       OR v_json IS NOT NULL
       OR v_unit IS DISTINCT FROM 'COUNT'
       OR v_desc IS DISTINCT FROM 'Maximum photos/videos per complaint ticket (M6.2 OPEN-T3).'
       OR v_admin IS DISTINCT FROM TRUE
       OR v_effective_to IS NOT NULL
       OR v_active IS DISTINCT FROM TRUE
    THEN
      RAISE EXCEPTION
        'M6 Phase A conflict: existing COMPLAINT_MEDIA_MAX_COUNT (2026-01-01) values do not match approved contract; refusing overwrite';
    END IF;

    -- Existing row already matches; no UPDATE (avoid silent overwrite path).
    RETURN;
  END IF;

  IF v_code_cnt = 1 AND v_key_cnt = 0 THEN
    RAISE EXCEPTION
      'M6 Phase A conflict: COMPLAINT_MEDIA_MAX_COUNT exists with a different effective_from; refusing insert/overwrite';
  END IF;

  -- Absent: insert without parameter_id.
  INSERT INTO solar_app.ref_business_parameters (
    parameter_code,
    parameter_name,
    value_type,
    numeric_value,
    text_value,
    boolean_value,
    json_value,
    parameter_unit,
    parameter_desc,
    admin_manageable_ind,
    effective_from,
    effective_to,
    active_ind,
    created_by,
    updated_by
  ) VALUES (
    'COMPLAINT_MEDIA_MAX_COUNT',
    'Complaint media attachment maximum',
    'NUMERIC',
    4,
    NULL,
    NULL,
    NULL,
    'COUNT',
    'Maximum photos/videos per complaint ticket (M6.2 OPEN-T3).',
    TRUE,
    DATE '2026-01-01',
    NULL,
    TRUE,
    'SYSTEM',
    'SYSTEM'
  );
END $$;

DO $$
DECLARE
  v_cnt integer;
BEGIN
  SELECT COUNT(*)
  INTO v_cnt
  FROM solar_app.ref_business_parameters
  WHERE parameter_code = 'COMPLAINT_MEDIA_MAX_COUNT'
    AND effective_from = DATE '2026-01-01'
    AND active_ind IS TRUE
    AND value_type = 'NUMERIC'
    AND numeric_value = 4
    AND admin_manageable_ind IS TRUE
    AND parameter_unit = 'COUNT'
    AND effective_to IS NULL;

  IF v_cnt <> 1 THEN
    RAISE EXCEPTION
      'M6 Phase A failed: expected exactly 1 matching active COMPLAINT_MEDIA_MAX_COUNT row; found %',
      v_cnt;
  END IF;
END $$;

-- NOTE: No setval / nextval. Identity inserts advance the sequence themselves.

COMMIT;

-- -----------------------------------------------------------------------------
-- Post-commit reporting (temp table preserved via ON COMMIT PRESERVE ROWS)
-- Report captured TKT_CLOSED id only after successful COMMIT.
-- -----------------------------------------------------------------------------
SELECT
  step_name,
  tkt_closed_ref_data_id AS captured_tkt_closed_ref_data_id,
  tkt_closed_action,
  notes
FROM tmp_m6_phase_a_capture
WHERE step_name = 'TKT_CLOSED';

SELECT
  d.ref_data_id,
  c.category_code,
  d.data_code,
  d.data_value,
  d.sort_order,
  d.active_ind,
  d.created_by,
  d.updated_by
FROM solar_app.ref_data AS d
JOIN solar_app.ref_data_categories AS c
  ON c.category_id = d.category_id
WHERE d.data_code IN ('TKT_RESOLVED', 'TKT_CLOSED', 'JOB_QUEUED')
ORDER BY c.category_code, d.sort_order, d.ref_data_id;

SELECT
  parameter_id,
  parameter_code,
  parameter_name,
  value_type,
  numeric_value,
  parameter_unit,
  admin_manageable_ind,
  effective_from,
  effective_to,
  active_ind,
  created_by,
  updated_by
FROM solar_app.ref_business_parameters
WHERE parameter_code = 'COMPLAINT_MEDIA_MAX_COUNT'
ORDER BY parameter_id;

-- Freeze captured_tkt_closed_ref_data_id into:
--   Solar-DB/reference-data/stable/ref_data_id_overrides.json
--   key: "TICKET_STATUSES.TKT_CLOSED"
--
-- Optional session cleanup after the operator records the capture:
--   DROP TABLE IF EXISTS tmp_m6_phase_a_capture;
