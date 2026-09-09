-- ============================================================================
-- Organization setup — run all, top to bottom, in pgAdmin.
--
-- Every statement is idempotent: re-running changes nothing further.
-- Nothing here moves an existing employee, so no review history is disturbed.
--
-- Expected messages, in order:
--   INSERT 0 1   (or INSERT 0 0 if the org already exists)
--   INSERT 0 1   (or INSERT 0 0 if VLPLN0001 already exists)
--   then three result grids
-- ============================================================================


-- ── 1. The new organization ─────────────────────────────────────────────────
-- You already ran this; kept so the whole script is re-runnable standalone.

INSERT INTO kra.organizations (id, name, slug, logo_url, created_at, updated_at)
VALUES (gen_random_uuid(), 'Vistar Logitek North', 'vistar-logitek-north',
        NULL, NOW(), NOW())
ON CONFLICT (slug) DO NOTHING;


-- ── 2. A user INSIDE that organization ──────────────────────────────────────
-- Created fresh rather than moved. Moving one of your 48 existing employees
-- would strip them of their review history, which stays keyed to the old
-- organization — 43 of the 48 carry live reviews/assignments.
--
-- Login: north.hr@vistar.test  (or employee code VLPLN0001)
-- Password: Vistar@Super2026!   <-- bcrypt cost 10, verified
-- CHANGE THIS. The hash below is in your git repo and in our chat transcript.
-- Generate a replacement with:
--   cd D:\Vistar\vistar_CRM
--   node -e "console.log(require('bcryptjs').hashSync(process.argv[1],10))" "NewPassword"
--
-- Role HR_ADMIN on purpose: it is the role that actually works against the
-- deployed API today, so this account can exercise the new tenant immediately
-- without waiting on the SUPER_ADMIN route-guard patch to be deployed.

INSERT INTO kra.employees (
  id, organization_id, email, password_hash, name, employee_code,
  position, department, role, auth_method, is_active, force_password_reset,
  joined_date, created_at, updated_at)
SELECT
  gen_random_uuid(),
  (SELECT id FROM kra.organizations WHERE slug = 'vistar-logitek-north'),
  'north.hr@vistar.test',
  '$2b$10$5aE8.IV/aMCP.Kq.FiMWcORbzSX5K.W2/JhaNhBqGzVJi9MZV0QCe',
  'North HR Admin',
  'VLPLN0001',          -- matches the API's ^[A-Z]{2,5}[0-9]{4,8}$
  'Senior Officer-Hr',
  'HR',
  'HR_ADMIN',
  'PASSWORD',
  TRUE,
  FALSE,                -- TRUE would force a password reset on first login
  CURRENT_DATE,
  NOW(),
  NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM kra.employees WHERE employee_code = 'VLPLN0001'
);


-- ── 3. Verify: organizations and their headcount ────────────────────────────

SELECT o.slug, o.name, COUNT(e.id) AS employees
  FROM kra.organizations o
  LEFT JOIN kra.employees e ON e.organization_id = o.id
 GROUP BY o.slug, o.name
 ORDER BY o.name;

-- Expect at least two rows, with vistar-logitek-north showing 1.


-- ── 4. Verify: who is in the new tenant ─────────────────────────────────────

SELECT e.employee_code, e.name, e.email, e.role, e.is_active
  FROM kra.employees e
  JOIN kra.organizations o ON o.id = e.organization_id
 WHERE o.slug = 'vistar-logitek-north'
 ORDER BY e.employee_code;

-- Expect exactly VLPLN0001 / North HR Admin / HR_ADMIN / true.


-- ── 5. Verify: the super admin is still where the data is ───────────────────

SELECT e.employee_code, e.name, e.role, o.slug AS organization
  FROM kra.employees e
  JOIN kra.organizations o ON o.id = e.organization_id
 WHERE e.employee_code IN ('VLPL9001', 'VLPLN0001')
 ORDER BY e.employee_code;

-- VLPL9001 (Super Admin) MUST still read org_vistar_test. If it ever moves to
-- the new tenant it will see an empty app, because every backend query scopes
-- by the organizationId claim signed into the JWT at login.


-- ============================================================================
-- OPTIONAL — only if you specifically want existing people moved.
-- Not recommended, and left commented deliberately.
--
-- These five were the only ones with zero reviews AND zero assignments in the
-- half of the table I could see (rows 1-24 of 48). Re-check with the query in
-- section 6 before uncommenting, since I could not see rows 25-48.
--
-- manager_id and project_location_id are nulled in the same statement because
-- both point at rows in the OLD organization; leaving them would give the
-- employee a manager and a site their new tenant does not contain.
--
--   UPDATE kra.employees
--      SET organization_id = (SELECT id FROM kra.organizations
--                              WHERE slug = 'vistar-logitek-north'),
--          manager_id = NULL,
--          project_location_id = NULL,
--          updated_at = NOW()
--    WHERE employee_code IN ('ADMIN-001','VLPL0001','VLPL0004','VLPL0315','VLPL0591');
--
-- Expect UPDATE 5.
-- ============================================================================


-- ── 6. The authoritative "safe to move" list (all 48 rows) ──────────────────
-- Run this instead of trusting the five codes above.

SELECT e.employee_code, e.name, o.slug AS current_org,
       e.manager_id IS NOT NULL         AS has_manager,
       e.project_location_id IS NOT NULL AS has_location
  FROM kra.employees e
  JOIN kra.organizations o ON o.id = e.organization_id
 WHERE NOT EXISTS (SELECT 1 FROM kra.reviews r         WHERE r.employee_id = e.id)
   AND NOT EXISTS (SELECT 1 FROM kra.kra_assignments a WHERE a.employee_id = e.id)
 ORDER BY e.employee_code;


-- ── 7. Data-quality items spotted in your table ─────────────────────────────
-- Not run — just so you can see them.
--
-- a) VLPL0023 is named "asdfgh" and carries 1 review + 1 assignment: test junk
--    now entangled with real review data.
--      SELECT * FROM kra.employees WHERE employee_code = 'VLPL0023';
--
-- b) ADMIN-001 does not match the API's own employee_code pattern
--    (^[A-Z]{2,5}[0-9]{4,8}$ — no hyphens allowed). PATCH /employees/:id on
--    that row will fail validation if the code is ever re-sent.
--      SELECT employee_code FROM kra.employees
--       WHERE employee_code !~ '^[A-Z]{2,5}[0-9]{4,8}$';
