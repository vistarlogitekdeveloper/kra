-- ============================================================================
-- Per-organization review flow.
--
-- RUN THIS BEFORE docs/install_review_flow.mjs — that script patches code
-- which reads this column, and without it every organizations read would 500.
--
-- Two pipelines:
--   STANDARD    self -> (reporting manager | HR | Accounts) -> management
--               -> payout.  The original. THE DEFAULT.
--   ADMIN_ONLY  an HR rating and a management sign-off, entered by HR,
--               management or an admin. No self-rating, no manager rating, no
--               separate Accounts rating.
--
-- Every existing organization must keep running STANDARD, so the column
-- defaults to it AND is backfilled explicitly. The client also resolves
-- anything unknown or absent to STANDARD — three layers all failing in the
-- same safe direction, because the other direction would silently strip every
-- employee's self-rating in a live tenant.
-- ============================================================================

BEGIN;

-- Idempotent: safe to re-run.
ALTER TABLE kra.organizations
  ADD COLUMN IF NOT EXISTS review_flow TEXT NOT NULL DEFAULT 'STANDARD';

-- Belt and braces. The DEFAULT already covers existing rows, but an explicit
-- backfill means a row written by some other path cannot end up NULL or blank.
UPDATE kra.organizations
   SET review_flow = 'STANDARD'
 WHERE review_flow IS NULL OR review_flow = '';

-- Reject anything the app does not understand, at the database level. A typo
-- inserted by hand would otherwise reach the client, which would silently
-- treat it as STANDARD and hide the mistake.
ALTER TABLE kra.organizations
  DROP CONSTRAINT IF EXISTS organizations_review_flow_check;
ALTER TABLE kra.organizations
  ADD CONSTRAINT organizations_review_flow_check
  CHECK (review_flow IN ('STANDARD', 'ADMIN_ONLY'));

COMMIT;


-- ── Prisma ──────────────────────────────────────────────────────────────────
-- Add to `model Organization` in prisma/schema.prisma, then `npx prisma generate`:
--
--   reviewFlow String @default("STANDARD") @map("review_flow")
--
-- Left as TEXT with a CHECK rather than a Postgres enum on purpose: adding a
-- value to an enum type is irreversible (Postgres cannot drop one), whereas
-- this constraint can be replaced when a third flow arrives.


-- ── Verify ──────────────────────────────────────────────────────────────────

SELECT slug, name, review_flow
  FROM kra.organizations
 ORDER BY name;

-- Expect every existing row to read STANDARD.


-- ── Setting a flow ──────────────────────────────────────────────────────────
-- Prefer the Organizations screen once install_review_flow.mjs is applied and
-- the API restarted. By hand, if you need it before then:
--
--   UPDATE kra.organizations
--      SET review_flow = 'ADMIN_ONLY', updated_at = NOW()
--    WHERE slug = 'vistar-logitek-north';
--
-- Changing a flow does NOT alter reviews already in progress: existing rows
-- keep their scores and stage records. It changes who may enter ratings from
-- that point on.


-- ── Reverting one organization ──────────────────────────────────────────────
--   UPDATE kra.organizations
--      SET review_flow = 'STANDARD', updated_at = NOW()
--    WHERE slug = '<slug>';
--
-- Safe at any time, and the reason the column is worth having: a tenant that
-- tries the admin-only pipeline can go back with one statement.
