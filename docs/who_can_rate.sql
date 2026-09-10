-- ============================================================================
-- WHO CAN RATE THIS EMPLOYEE?
--
-- Read-only. Every statement is a SELECT; nothing here writes.
-- Replace VLPL8844 with whichever employee code you are asking about.
--
-- Under ADMIN_ONLY the seats divide like this:
--
--   KRA assigned to HR        -> ACCOUNT_HR_RATING       -> HR, HR_ADMIN
--   KRA assigned to Accounts  -> FINANCE_RATING          -> FINANCE only
--   anything else (Manager,   -> REPORTING_MANAGER_RATING-> MANAGEMENT
--     or never assigned)                                    (after the patch;
--                                                            see step 4)
--   then the quarter sign-off -> MANAGEMENT_REVIEW       -> MANAGEMENT, HR_ADMIN
--
-- SUPER_ADMIN holds every rating seat once install_rating_roles.mjs is applied.
-- ============================================================================


-- ── 1. Confirm the flow, the cycle and the reporting line ──────────────────
SELECT e.employee_code,
       e.name,
       e.position           AS designation,
       e.role,
       o.name               AS organization,
       o.review_flow,
       m.employee_code      AS manager_code,
       m.name               AS manager_name
FROM   kra.employees e
JOIN   kra.organizations o ON o.id = e.organization_id
LEFT   JOIN kra.employees m ON m.id = e.manager_id
WHERE  e.employee_code = 'VLPL8844';

-- review_flow must read ADMIN_ONLY. If it says STANDARD, everything below is
-- the wrong model — the employee self-rates first and their reporting manager
-- rates the leftover KRAs instead of management.


-- ── 2. His KRAs, and WHICH SEAT each one sits on ───────────────────────────
-- This is the authoritative answer: the rating is gated on
-- monthly_review_rows.reviewer_group, not on the template. The CASE mirrors
-- the server's own mapping in writeRowScores, so what this prints is exactly
-- what the API will enforce.
SELECT mr.year,
       mr.month,
       rr.display_order,
       rr.name                                        AS kra,
       COALESCE(NULLIF(rr.reviewer_group, ''), '(unset)') AS stored_reviewer,
       CASE
         WHEN upper(coalesce(rr.reviewer_group, '')) IN
              ('HR', 'HR_FEED', 'ACCOUNT_HR', 'ACCOUNT_HR_RATING')
           THEN 'ACCOUNT_HR_RATING  -> HR / HR_ADMIN'
         WHEN upper(coalesce(rr.reviewer_group, '')) IN
              ('ACCOUNTS', 'ACCOUNT', 'ACCOUNTS_FEED', 'FINANCE')
           THEN 'FINANCE_RATING     -> Accounts (FINANCE) only'
         ELSE 'REPORTING_MANAGER_RATING -> MANAGEMENT (the remainder)'
       END                                            AS who_rates_it
FROM   kra.monthly_review_rows rr
JOIN   kra.monthly_reviews mr ON mr.id = rr.review_id
JOIN   kra.employees e        ON e.id = mr.employee_id
WHERE  e.employee_code = 'VLPL8844'
ORDER  BY mr.year, mr.month, rr.display_order;

-- Expect three rows per month. If you get none, the monthly reviews have not
-- been generated for that cycle yet — only an HR_ADMIN can generate them.


-- ── 3. The PEOPLE who hold each seat, with their employee codes ────────────
-- Scoped to this employee's own organization, because every rating query is
-- filtered by the organizationId claim: someone in another tenant cannot rate
-- him however senior they are.
WITH subject AS (
  SELECT organization_id
  FROM   kra.employees
  WHERE  employee_code = 'VLPL8844'
)
SELECT CASE e.role
         WHEN 'HR'          THEN '1. HR KRAs'
         WHEN 'HR_ADMIN'    THEN '1. HR KRAs + the sign-off'
         WHEN 'FINANCE'     THEN '2. Accounts KRAs'
         WHEN 'MANAGEMENT'  THEN '3. The remaining KRAs + the sign-off'
         WHEN 'SUPER_ADMIN' THEN '4. Everything (after install_rating_roles)'
         ELSE e.role
       END              AS seat,
       e.employee_code,
       e.name,
       e.position       AS designation,
       e.role,
       e.is_active
FROM   kra.employees e, subject s
WHERE  e.organization_id = s.organization_id
  AND  e.role IN ('HR', 'HR_ADMIN', 'FINANCE', 'MANAGEMENT', 'SUPER_ADMIN')
ORDER  BY seat, e.name;

-- An inactive person still appears here on purpose: "the only Accounts user is
-- deactivated" is the answer to "why can nobody rate the Accounts KRA".


-- ── 3b. Anyone holding a seat via the multi-role grant set ─────────────────
-- `roles` is a text[] maintained by raw SQL and is NOT a Prisma field, so a
-- user can hold FINANCE through it while their scalar `role` says something
-- else. Query 3 alone would miss them.
WITH subject AS (
  SELECT organization_id
  FROM   kra.employees
  WHERE  employee_code = 'VLPL8844'
)
SELECT e.employee_code, e.name, e.role AS primary_role, e.roles AS all_roles
FROM   kra.employees e, subject s
WHERE  e.organization_id = s.organization_id
  AND  e.roles && ARRAY['HR', 'HR_ADMIN', 'FINANCE', 'MANAGEMENT', 'SUPER_ADMIN']
  AND  e.role <> ANY (ARRAY['HR', 'HR_ADMIN', 'FINANCE', 'MANAGEMENT', 'SUPER_ADMIN'])
ORDER  BY e.name;

-- If this errors with "column roles does not exist", the lazy migration has
-- not run on this database yet — which simply means nobody holds a second
-- role, and query 3 is the whole answer.


-- ── 4. Which server patches are live? ──────────────────────────────────────
-- Not SQL — check the deployed files, because the answer to "can MANAGEMENT
-- rate?" is different before and after:
--
--   grep -c "MANAGEMENT" .../monthly-reviews.service.js   (ACTOR_ROLES)
--     0 in MANAGEMENT_REVIEW -> management is refused the sign-off (403)
--     needs: docs/install_rating_roles.mjs
--
--   grep -c "cannot rate the remaining KRAs" .../monthly-reviews.service.js
--     0 -> the leftover KRAs are still gated on the reporting-manager
--          RELATIONSHIP, so management cannot rate them and only the
--          employee's own manager can
--     needs: docs/install_admin_only_remainder.mjs
--
-- STATUS as of 2026-09-10: BOTH are applied and verified, along with
-- install_review_designation.mjs. So on an ADMIN_ONLY organisation:
--   HR KRA        -> HR, HR_ADMIN
--   Accounts KRA  -> FINANCE only
--   remaining KRA -> MANAGEMENT, HR_ADMIN, ADMIN
--   sign-off      -> MANAGEMENT, HR_ADMIN, ADMIN
-- Still NOT applied: install_review_month_shift.mjs (the API still reports
-- today's month as current; the client clamps it, so screens are correct).
--
-- Each needs an API RESTART to take effect — the files are patched on disk,
-- but a running process still holds the old code.


-- ── 5. Which employees will actually SHOW a designation? ───────────────────
-- The card renders the line only when `position` is non-empty, and the
-- designation field is OPTIONAL on the employee form — the payload omits
-- `position` entirely when it was left blank. So a null here is a data gap,
-- not a bug: fix it by editing the employee and picking a Designation.
WITH subject AS (
  SELECT organization_id FROM kra.employees WHERE employee_code = 'VLPL8844'
)
SELECT e.employee_code,
       e.name,
       e.role,
       COALESCE(NULLIF(TRIM(e.position), ''), '(none - card shows no line)')
         AS designation
FROM   kra.employees e, subject s
WHERE  e.organization_id = s.organization_id
  AND  e.is_active = true
ORDER  BY (NULLIF(TRIM(e.position), '') IS NULL) DESC, e.name;
