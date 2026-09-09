-- ============================================================================
-- Put every real user in "vistar-logitek", and give the super admin its own
-- home organization.
--
-- READ THIS FIRST — it is NOT what you asked for, and that is deliberate.
--
-- You asked to (a) give the super admin NO organization and (b) move all users
-- into vistar-logitek.
--
-- (a) is impossible: kra.employees.organization_id is `String` in the Prisma
--     schema, i.e. NOT NULL, with a required relation to kra.organizations.
--     The database will reject a null. It is also signed into the JWT at login
--     (auth.service.js issueTokenPair) and every repository query filters on
--     it, so a null would break every read that account makes.
--     -> The super admin instead gets a dedicated HOME org and reaches the
--        others via POST /organizations/switch (docs/backend_patch_organizations.js),
--        which re-issues its token for any organization it names. "Access to
--        all organizations" comes from the ROLE plus that route, never from
--        having no organization.
--
-- (b) done by MOVING 45 employees would strand their data. reviews,
--     kra_assignments, kra_templates, project_locations and review_cycles all
--     carry their own organization_id, independent of the employee. 43 of your
--     48 originals have live reviews or assignments. Moving the people and not
--     the data makes that history invisible to them — exactly what happened to
--     VLPL0591 earlier, at a scale of one.
--     -> This script RENAMES instead. vistar-test already holds all 45. Renaming
--        it to vistar-logitek reaches the same end state while touching 3 rows
--        instead of 45, and — crucially — organization_id never changes, so no
--        review strands and no issued token is invalidated.
--
-- End state:
--   vistar-logitek        <- the 45 real users (was vistar-test, renamed)
--                            plus ADMIN-001 and VLPL0004, folded in
--   vistar-platform       <- VLPL9001 (Super Admin) alone
--   vistar-logitek-north  <- VLPL0315 + VLPLN0001, untouched. Keep this: it is
--                            your second tenant, and you need one to prove
--                            cross-org isolation actually works.
--
-- Wrapped in a transaction. If any statement fails, nothing is applied.
-- ============================================================================

BEGIN;

-- ── 1. A home organization for the super admin ──────────────────────────────
-- Holds exactly one account and no business data, so nothing is scoped to it.

INSERT INTO kra.organizations (id, name, slug, logo_url, created_at, updated_at)
VALUES (gen_random_uuid(), 'Vistar Platform', 'vistar-platform', NULL, NOW(), NOW())
ON CONFLICT (slug) DO NOTHING;


-- ── 2. Move the super admin into it ─────────────────────────────────────────
-- Safe: VLPL9001 was created minutes ago and has 0 reviews and 0 assignments.
-- project_location_id is nulled because that location belongs to the org it is
-- leaving — a stale cross-org pointer is what the integrity check flags.

UPDATE kra.employees
   SET organization_id = (SELECT id FROM kra.organizations WHERE slug = 'vistar-platform'),
       project_location_id = NULL,
       manager_id = NULL,
       updated_at = NOW()
 WHERE employee_code = 'VLPL9001';

-- Expect UPDATE 1.


-- ── 3. Fold the 2 strays into the main tenant ───────────────────────────────
-- ADMIN-001 and VLPL0004 sit alone in the old vistar-logitek with 0 reviews and
-- 0 assignments. Moving them frees that slug for step 4 and puts them with
-- everyone else.

UPDATE kra.employees
   SET organization_id = (SELECT id FROM kra.organizations WHERE slug = 'vistar-test'),
       project_location_id = NULL,
       manager_id = NULL,
       updated_at = NOW()
 WHERE organization_id = (SELECT id FROM kra.organizations WHERE slug = 'vistar-logitek');

-- Expect UPDATE 2.


-- ── 4. Free the slug ────────────────────────────────────────────────────────
-- Renamed rather than deleted. organization_id is ON DELETE CASCADE across
-- employees, locations, cycles, templates and assignments — a DELETE here is
-- never worth the risk, even on an org that looks empty.

UPDATE kra.organizations
   SET slug = 'vistar-logitek-retired',
       name = 'Vistar Logitek (retired, empty)',
       updated_at = NOW()
 WHERE slug = 'vistar-logitek';

-- Expect UPDATE 1.


-- ── 5. Rename the real tenant ───────────────────────────────────────────────
-- THE WHOLE POINT. id is untouched, so every review, assignment, template,
-- location and cycle stays attached, and tokens already issued keep working.

UPDATE kra.organizations
   SET name = 'Vistar Logitek',
       slug = 'vistar-logitek',
       updated_at = NOW()
 WHERE slug = 'vistar-test';

-- Expect UPDATE 1.

COMMIT;


-- ── 6. Verify ───────────────────────────────────────────────────────────────

SELECT o.slug, o.name, COUNT(e.id) AS employees
  FROM kra.organizations o
  LEFT JOIN kra.employees e ON e.organization_id = o.id
 GROUP BY o.slug, o.name
 ORDER BY employees DESC;

-- Expect:
--   vistar-logitek           47
--   vistar-logitek-north      2
--   vistar-platform           1
--   vistar-logitek-retired    0


SELECT e.employee_code, e.name, e.role, o.slug AS organization
  FROM kra.employees e
  JOIN kra.organizations o ON o.id = e.organization_id
 WHERE e.role = 'SUPER_ADMIN';

-- Expect VLPL9001 alone in vistar-platform.


-- ── 7. Cross-org integrity — MUST return zero rows ──────────────────────────
-- Any row here is a record pointing at an organization its owner no longer
-- belongs to. Run it after every organization change.

SELECT 'assignment' AS kind, e.employee_code, oe.slug AS employee_org, oa.slug AS record_org
  FROM kra.kra_assignments a
  JOIN kra.employees e       ON e.id = a.employee_id
  JOIN kra.organizations oe  ON oe.id = e.organization_id
  JOIN kra.organizations oa  ON oa.id = a.organization_id
 WHERE a.organization_id <> e.organization_id
UNION ALL
SELECT 'review', e.employee_code, oe.slug, orr.slug
  FROM kra.reviews r
  JOIN kra.employees e       ON e.id = r.employee_id
  JOIN kra.organizations oe  ON oe.id = e.organization_id
  JOIN kra.organizations orr ON orr.id = r.organization_id
 WHERE r.organization_id <> e.organization_id
UNION ALL
SELECT 'manager', e.employee_code, oe.slug, om.slug
  FROM kra.employees e
  JOIN kra.employees m       ON m.id = e.manager_id
  JOIN kra.organizations oe  ON oe.id = e.organization_id
  JOIN kra.organizations om  ON om.id = m.organization_id
 WHERE m.organization_id <> e.organization_id
UNION ALL
SELECT 'location', e.employee_code, oe.slug, ol.slug
  FROM kra.employees e
  JOIN kra.project_locations l ON l.id = e.project_location_id
  JOIN kra.organizations oe    ON oe.id = e.organization_id
  JOIN kra.organizations ol    ON ol.id = l.organization_id
 WHERE l.organization_id <> e.organization_id
 ORDER BY kind, employee_code;


-- ============================================================================
-- If you truly want the super admin's data-less state to be enforced rather
-- than conventional, that is a backend change, not a SQL one:
--
--   1. prisma: organizationId String?  (nullable) + optional relation
--   2. every repository must then handle a null caller org — currently they
--      pass it straight into a Prisma `where`, so null would silently match
--      nothing and the account would see an empty app rather than everything
--   3. auth.service.issueTokenPair must sign a null claim
--
-- That is a large, high-risk change across ~13 repositories, and it buys
-- nothing the switch route does not already give you. Not recommended.
-- ============================================================================
