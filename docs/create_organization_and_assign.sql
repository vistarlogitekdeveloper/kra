-- Create an organization and assign users to it — pure SQL.
--
-- This is the path that works TODAY, with no code changes and nothing deployed.
--
-- Why SQL is needed at all:
--   * There is no organizations API (0 routes, 0 controller, 0 mount) — see
--     docs/backend_patch_organizations.js for the feature that adds one.
--   * CreateEmployeeSchema and UpdateEmployeeSchema do NOT accept
--     organizationId (verified: 0 occurrences in either), and
--     employees.controller.js passes req.user.organizationId on every call. So
--     the API always puts a new employee in the CALLER's organization and can
--     never move an existing one.
--
-- Table facts used below (prisma/schema.prisma):
--   kra.organizations  id (uuid pk), name, slug (UNIQUE), logo_url,
--                      created_at, updated_at
--   kra.employees      organization_id -> organizations.id, ON DELETE CASCADE

--------------------------------------------------------------------------------
-- 1. See what already exists
--------------------------------------------------------------------------------
SELECT o.id, o.slug, o.name, COUNT(e.id) AS employees
  FROM kra.organizations o
  LEFT JOIN kra.employees e ON e.organization_id = o.id
 GROUP BY o.id, o.slug, o.name
 ORDER BY o.name;


--------------------------------------------------------------------------------
-- 2. Create a new organization
--------------------------------------------------------------------------------
-- slug is UNIQUE, so ON CONFLICT keeps this re-runnable. Keep it URL-safe:
-- lowercase letters, digits, single hyphens.

INSERT INTO kra.organizations (id, name, slug, logo_url, created_at, updated_at)
VALUES (
  gen_random_uuid(),
  'Vistar Logitek North',        -- display name
  'vistar-logitek-north',        -- slug (UNIQUE, url-safe)
  NULL,                          -- logo_url
  NOW(),
  NOW()
)
ON CONFLICT (slug) DO NOTHING
RETURNING id, name, slug;

-- Note the returned id, or look it up by slug in the statements below.


--------------------------------------------------------------------------------
-- 3. Assign users to it
--------------------------------------------------------------------------------
-- Pick ONE of the following. Each resolves the org by slug, so you never paste
-- a UUID and never risk assigning to the wrong tenant.

-- 3a. One specific user, by employee code
UPDATE kra.employees
   SET organization_id = (SELECT id FROM kra.organizations
                           WHERE slug = 'vistar-logitek-north'),
       updated_at = NOW()
 WHERE employee_code = 'VLPL0042';

-- 3b. Several users at once
UPDATE kra.employees
   SET organization_id = (SELECT id FROM kra.organizations
                           WHERE slug = 'vistar-logitek-north'),
       updated_at = NOW()
 WHERE employee_code IN ('VLPL0042', 'VLPL0043', 'VLPL0044');

-- 3c. By email
UPDATE kra.employees
   SET organization_id = (SELECT id FROM kra.organizations
                           WHERE slug = 'vistar-logitek-north'),
       updated_at = NOW()
 WHERE lower(email) = lower('someone@vistar.test');


--------------------------------------------------------------------------------
-- 4. Verify
--------------------------------------------------------------------------------
SELECT e.employee_code, e.name, e.role, o.slug AS organization
  FROM kra.employees e
  JOIN kra.organizations o ON o.id = e.organization_id
 WHERE o.slug = 'vistar-logitek-north'
 ORDER BY e.employee_code;


--------------------------------------------------------------------------------
-- READ THIS BEFORE MOVING AN EXISTING USER
--------------------------------------------------------------------------------
-- Moving someone between organizations does NOT move their history, and the
-- app's org scoping will then hide it from them. Everything below is keyed by
-- organization_id independently of the employee:
--
--   kra.reviews, kra.kra_assignments, kra.kra_templates,
--   kra.project_locations, kra.review_cycles
--
-- Consequences of a bare organization_id update on an existing employee:
--   * their past reviews stay attached to the OLD organization and disappear
--     from their history;
--   * their project_location_id may now point at a location belonging to the
--     old org — the employee form's location dropdown will not contain it;
--   * their manager_id may now point at an employee in the old org, so the
--     reporting line crosses tenants and manager-scoped queries stop matching.
--
-- Safe usage: assign the organization when a user is NEW and has no reviews.
-- To check before moving:
--
--   SELECT
--     (SELECT COUNT(*) FROM kra.reviews r WHERE r.employee_id = e.id)         AS reviews,
--     (SELECT COUNT(*) FROM kra.kra_assignments a WHERE a.employee_id = e.id) AS assignments,
--     e.manager_id, e.project_location_id
--   FROM kra.employees e
--  WHERE e.employee_code = 'VLPL0042';
--
-- If reviews/assignments are non-zero, prefer creating a fresh record in the
-- new organization over moving the existing one, and clear manager_id /
-- project_location_id when you do move someone:
--
--   UPDATE kra.employees
--      SET organization_id = (SELECT id FROM kra.organizations WHERE slug = 'vistar-logitek-north'),
--          manager_id = NULL,
--          project_location_id = NULL,
--          updated_at = NOW()
--    WHERE employee_code = 'VLPL0042';


--------------------------------------------------------------------------------
-- Do not DELETE an organization
--------------------------------------------------------------------------------
-- kra.employees.organization_id is ON DELETE CASCADE, and so are locations,
-- cycles, templates and assignments. Deleting an organization erases every
-- employee in it and their entire review history. There is no soft-delete
-- column yet. If you need to retire a tenant, deactivate its people instead:
--
--   UPDATE kra.employees SET is_active = FALSE
--    WHERE organization_id = (SELECT id FROM kra.organizations WHERE slug = 'old-slug');
