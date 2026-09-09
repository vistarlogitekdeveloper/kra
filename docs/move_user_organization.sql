-- ============================================================================
-- Move ONE existing user to another organization.
--
-- Replace the two placeholders and run top to bottom. Step 1 tells you whether
-- the move is safe; do not skip it.
--
--     :code  -> the employee_code, e.g. 'VLPL0315'
--     :slug  -> the destination org slug, e.g. 'vistar-logitek-north'
-- ============================================================================


-- ── 1. IS THIS SAFE? Run this first. ────────────────────────────────────────
--
-- A review is NOT stored against an organization directly — kra.reviews has no
-- organization_id. It hangs off a review_cycle, and the CYCLE belongs to the
-- org (review_cycles.organization_id). So an employee's review history is
-- structurally bound to the organization whose cycle produced it, and there is
-- no column to update to bring it along. Move the person and the history stays
-- behind — permanently, not just until someone fixes a foreign key.
--
-- kra_assignments DOES carry organization_id, so those can move (step 3).

SELECT e.employee_code,
       e.name,
       o.slug AS current_org,
       (SELECT COUNT(*) FROM kra.reviews r
         WHERE r.employee_id = e.id)                       AS reviews_that_CANNOT_move,
       (SELECT COUNT(*) FROM kra.kra_assignments a
         WHERE a.employee_id = e.id)                       AS assignments_that_can_move,
       e.manager_id IS NOT NULL                            AS has_manager,
       e.project_location_id IS NOT NULL                   AS has_location
  FROM kra.employees e
  JOIN kra.organizations o ON o.id = e.organization_id
 WHERE e.employee_code = 'VLPL0315';       -- <-- :code

-- reviews_that_CANNOT_move = 0  ->  safe, continue.
-- reviews_that_CANNOT_move > 0  ->  STOP. That history becomes invisible to
--                                   them and to their new manager. Prefer
--                                   creating a fresh account in the new org.


-- ── 2 + 3. The move ─────────────────────────────────────────────────────────
-- One transaction: employee, then their assignments. Either both land or
-- neither does.

BEGIN;

-- 2. The employee.
--
-- manager_id and project_location_id are nulled because both point into the
-- OLD org: the manager is not in the new tenant, and the location will not
-- even appear in the employee form's dropdown there. Reassign them afterwards
-- from within the destination organization.
UPDATE kra.employees
   SET organization_id     = (SELECT id FROM kra.organizations WHERE slug = 'vistar-logitek-north'),  -- <-- :slug
       manager_id          = NULL,
       project_location_id = NULL,
       updated_at          = NOW()
 WHERE employee_code = 'VLPL0315';         -- <-- :code

-- Expect UPDATE 1. If it says UPDATE 0 the code did not match — employee_code
-- is compared exactly, so check case and prefix.

-- 3. Their KRA assignments, so they do not end up orphaned in the old org.
-- This is the row type that stranded VLPL0591 the first time.
UPDATE kra.kra_assignments a
   SET organization_id = e.organization_id
  FROM kra.employees e
 WHERE a.employee_id = e.id
   AND e.employee_code = 'VLPL0315'        -- <-- :code
   AND a.organization_id <> e.organization_id;

COMMIT;


-- ── 4. Verify ───────────────────────────────────────────────────────────────

SELECT e.employee_code, e.name, o.slug AS organization,
       e.manager_id, e.project_location_id
  FROM kra.employees e
  JOIN kra.organizations o ON o.id = e.organization_id
 WHERE e.employee_code = 'VLPL0315';       -- <-- :code


-- ── 5. Cross-org integrity — MUST return zero rows ──────────────────────────
--
-- CORRECTED. An earlier version of this check queried r.organization_id on
-- kra.reviews; that column does not exist and the query would have errored.
-- Reviews are reached through their cycle instead.

SELECT 'assignment' AS kind, e.employee_code, oe.slug AS employee_org, oa.slug AS record_org
  FROM kra.kra_assignments a
  JOIN kra.employees e      ON e.id = a.employee_id
  JOIN kra.organizations oe ON oe.id = e.organization_id
  JOIN kra.organizations oa ON oa.id = a.organization_id
 WHERE a.organization_id <> e.organization_id

UNION ALL
-- A review whose CYCLE belongs to a different org than the employee does.
-- Expected and unfixable after a move: listed so you can see what was left
-- behind, not because it can be repaired by an UPDATE.
SELECT 'review (via cycle)', e.employee_code, oe.slug, oc.slug
  FROM kra.reviews r
  JOIN kra.employees e      ON e.id = r.employee_id
  JOIN kra.review_cycles c  ON c.id = r.review_cycle_id
  JOIN kra.organizations oe ON oe.id = e.organization_id
  JOIN kra.organizations oc ON oc.id = c.organization_id
 WHERE c.organization_id <> e.organization_id

UNION ALL
SELECT 'manager', e.employee_code, oe.slug, om.slug
  FROM kra.employees e
  JOIN kra.employees m      ON m.id = e.manager_id
  JOIN kra.organizations oe ON oe.id = e.organization_id
  JOIN kra.organizations om ON om.id = m.organization_id
 WHERE m.organization_id <> e.organization_id

UNION ALL
SELECT 'location', e.employee_code, oe.slug, ol.slug
  FROM kra.employees e
  JOIN kra.project_locations l ON l.id = e.project_location_id
  JOIN kra.organizations oe    ON oe.id = e.organization_id
  JOIN kra.organizations ol    ON ol.id = l.organization_id
 WHERE l.organization_id <> e.organization_id
 ORDER BY kind, employee_code;


-- ── Who is safe to move right now ───────────────────────────────────────────
-- Everyone with no reviews AND no assignments.

SELECT e.employee_code, e.name, o.slug AS current_org
  FROM kra.employees e
  JOIN kra.organizations o ON o.id = e.organization_id
 WHERE NOT EXISTS (SELECT 1 FROM kra.reviews r         WHERE r.employee_id = e.id)
   AND NOT EXISTS (SELECT 1 FROM kra.kra_assignments a WHERE a.employee_id = e.id)
 ORDER BY o.slug, e.employee_code;
