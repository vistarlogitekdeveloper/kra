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
-- Until both are applied, on an ADMIN_ONLY organisation:
--   HR KRA        -> works today (HR / HR_ADMIN)
--   Accounts KRA  -> works today (FINANCE only; HR_ADMIN gets a 403)
--   remaining KRA -> only the reporting manager, NOT management
--   sign-off      -> only HR_ADMIN
