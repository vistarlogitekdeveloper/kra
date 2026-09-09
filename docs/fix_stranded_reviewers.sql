-- ============================================================================
-- Reassign KRAs that no rater in the ADMIN_ONLY flow can score.
--
--   Symptom: on an administrators-only organisation, some KRA rows cannot be
--   rated by HR, Accounts or anyone else. A score entered against them appears
--   to save (HTTP 200) and is gone on the next refresh.
--
--   Cause: the row is assigned to the REPORTING MANAGER, a seat the
--   administrators-only flow removes. writeRowScores enforces the assignment
--   in raw SQL — a Review-cycle rater may only score a row assigned to them —
--   and, in its own words, "Mismatches are silently skipped". The insert's
--   WHERE EXISTS matches nothing, zero rows are written, and no error is
--   raised. Its only escape hatch is reviewer_group IS NULL.
--
--   Fix: point those KRAs at a seat the flow actually has. This is the correct
--   data state regardless — an administrators-only organisation has no manager
--   rater, so a KRA assigned to one is a misconfiguration.
--
-- READ THE SELECTS FIRST. Nothing here writes until you uncomment step 3/4.
-- ============================================================================

-- ── 1. Which organisations are on the administrators-only flow? ─────────────
SELECT id, name, slug, review_flow
FROM   kra.organizations
ORDER  BY review_flow DESC, name;

-- ── 2. Stranded KRAs for one employee ──────────────────────────────────────
-- Replace VLPL9988 with the employee code you are testing.
-- Any row listed here CANNOT be rated by anybody today.
SELECT e.employee_code,
       e.name              AS employee,
       o.name              AS organization,
       o.review_flow,
       mr.year, mr.month,
       rr.id               AS review_row_id,
       rr.name             AS kra,
       rr.reviewer_group   AS assigned_to
FROM   kra.monthly_review_rows rr
JOIN   kra.monthly_reviews mr ON mr.id = rr.review_id
JOIN   kra.employees       e  ON e.id  = mr.employee_id
JOIN   kra.organizations   o  ON o.id  = mr.organization_id
WHERE  e.employee_code = 'VLPL9988'
  AND  o.review_flow   = 'ADMIN_ONLY'
  AND  upper(coalesce(rr.reviewer_group, '')) IN
       ('REPORTING_MANAGER', 'MANAGER', 'RM')
ORDER  BY mr.year, mr.month, rr.display_order;

-- ── 2b. Same question, across the whole organisation ───────────────────────
-- Run this before going live on the new flow: it is the full blast radius.
SELECT o.name AS organization, e.employee_code, e.name AS employee,
       rr.name AS kra, count(*) AS affected_months
FROM   kra.monthly_review_rows rr
JOIN   kra.monthly_reviews mr ON mr.id = rr.review_id
JOIN   kra.employees       e  ON e.id  = mr.employee_id
JOIN   kra.organizations   o  ON o.id  = mr.organization_id
WHERE  o.review_flow = 'ADMIN_ONLY'
  AND  upper(coalesce(rr.reviewer_group, '')) IN
       ('REPORTING_MANAGER', 'MANAGER', 'RM')
GROUP  BY o.name, e.employee_code, e.name, rr.name
ORDER  BY o.name, e.employee_code, rr.name;

-- ── 3. Fix the SOURCE: the KRA assignment ──────────────────────────────────
-- Do this one FIRST. monthly_review_rows are a SNAPSHOT of the assignment, so
-- fixing only the snapshot (step 4) leaves the next generated month broken
-- again. 'HR' is the natural destination — the administrators-only flow's
-- primary rater. Use 'ACCOUNTS' instead for anything commercial.
--
-- UPDATE kra.kra_assignment_items ai
-- SET    reviewer_group = 'HR'
-- FROM   kra.kra_assignments a
-- JOIN   kra.employees     e ON e.id = a.employee_id
-- JOIN   kra.organizations o ON o.id = e.organization_id
-- WHERE  ai.assignment_id = a.id
--   AND  o.review_flow    = 'ADMIN_ONLY'
--   AND  upper(coalesce(ai.reviewer_group, '')) IN
--        ('REPORTING_MANAGER', 'MANAGER', 'RM');

-- ── 4. Fix the ALREADY-GENERATED months ────────────────────────────────────
-- The snapshot does not re-read the assignment, so existing monthly rows keep
-- the old value and stay unrateable. Scoped to organisations on the new flow so
-- it cannot touch a STANDARD tenant, where the manager rating is legitimate.
--
-- UPDATE kra.monthly_review_rows rr
-- SET    reviewer_group = 'HR'
-- FROM   kra.monthly_reviews mr
-- JOIN   kra.organizations o ON o.id = mr.organization_id
-- WHERE  rr.review_id  = mr.id
--   AND  o.review_flow = 'ADMIN_ONLY'
--   AND  upper(coalesce(rr.reviewer_group, '')) IN
--        ('REPORTING_MANAGER', 'MANAGER', 'RM');

-- ── 5. Confirm ─────────────────────────────────────────────────────────────
-- Re-run step 2b. Zero rows means every KRA on every administrators-only
-- organisation now has a rater who can actually save a score.
--
-- Any score already entered against REPORTING_MANAGER_RATING is untouched by
-- this and stays in monthly_row_scores. It is simply no longer the stage the
-- flow reads, which is the intended outcome of moving off the manager rating.
