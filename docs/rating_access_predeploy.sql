-- =============================================================================
-- Rating access — pre-deploy check (read-only)
--
-- Run this against PRODUCTION (pgAdmin: run all, top to bottom) BEFORE the
-- backend with migration 169 is deployed. Nothing here writes.
--
-- Why: from the moment that backend deploys, every rating stage of every month
-- closes at its own deadline (self 10th, HR & Accounts 12th, reporting manager
-- 13th, management 15th of the month after, IST) unless a super admin opens it.
-- Migration 169 pre-opens July and August 2026 for every organisation and stage
-- until 31 Oct 2026. Everything else that was still in progress closes on
-- arrival. These queries list what that would strand, so the super admin can
-- reopen it on day one from Organizations → Rating access.
--
-- See docs/RATING_ACCESS.md §5.
-- =============================================================================

-- ── 1. Months before July 2026 that management never signed off ─────────────
-- Payout needs the review at MANAGEMENT_REVIEW or later, which in practice means
-- management saved and locked it. Without a Management-review reopen these can
-- no longer be signed off or paid.
SELECT o.name                         AS organisation,
       r.year,
       r.month,
       COUNT(*)                       AS reviews,
       COUNT(*) FILTER (WHERE r.management_locked_at IS NULL)            AS not_locked,
       COUNT(*) FILTER (WHERE r.payout_status = 'PENDING')               AS payout_pending,
       COUNT(*) FILTER (WHERE r.current_stage NOT IN
                        ('MANAGEMENT_REVIEW', 'INCENTIVE_PAYOUT', 'COMPLETED')) AS not_at_management
FROM kra.monthly_reviews r
JOIN kra.organizations o ON o.id = r.organization_id
WHERE (r.year, r.month) < (2026, 7)
  AND r.current_stage <> 'COMPLETED'
GROUP BY o.name, r.year, r.month
ORDER BY o.name, r.year, r.month;

-- ── 2. Months before July 2026 with KRAs nobody rated ────────────────────────
-- Per stage, how many rows still have no score. Under the new rule these stay
-- unrated unless the stage is reopened.
SELECT o.name                         AS organisation,
       r.year,
       r.month,
       COUNT(*) FILTER (WHERE NOT EXISTS (
         SELECT 1 FROM kra.monthly_row_scores s
         WHERE s.row_id = rw.id AND s.stage = 'SELF_RATING' AND s.value IS NOT NULL)) AS self_unrated_rows,
       COUNT(*) FILTER (WHERE NOT EXISTS (
         SELECT 1 FROM kra.monthly_row_scores s
         WHERE s.row_id = rw.id AND s.stage = 'MANAGEMENT_REVIEW' AND s.value IS NOT NULL)) AS management_unrated_rows
FROM kra.monthly_reviews r
JOIN kra.organizations o ON o.id = r.organization_id
JOIN kra.monthly_review_rows rw ON rw.review_id = r.id
WHERE (r.year, r.month) < (2026, 7)
  AND r.current_stage <> 'COMPLETED'
GROUP BY o.name, r.year, r.month
HAVING COUNT(*) > 0
ORDER BY o.name, r.year, r.month;

-- ── 3. September 2026, if production lands after its deadlines ───────────────
-- September is rated in October: self until 10 Oct, HR & Accounts 12 Oct,
-- reporting manager 13 Oct, management 15 Oct (IST). If the deploy is later than
-- a date below, that stage of September is closed on arrival.
SELECT o.name                         AS organisation,
       COUNT(*)                       AS reviews,
       COUNT(*) FILTER (WHERE r.current_stage = 'SELF_RATING')             AS still_at_self,
       COUNT(*) FILTER (WHERE r.management_locked_at IS NULL)              AS not_signed_off
FROM kra.monthly_reviews r
JOIN kra.organizations o ON o.id = r.organization_id
WHERE r.year = 2026 AND r.month = 9
GROUP BY o.name
ORDER BY o.name;

-- ── 4. After the deploy: confirm the July/August pre-open landed ─────────────
-- Expect (number of organisations) × 5 stages × 2 months rows, all OPEN until
-- 2026-10-31 18:29:59.999+00 (= 23:59:59.999 IST).
SELECT year, month, mode, open_until, COUNT(*) AS rows
FROM kra.rating_access_overrides
WHERE year = 2026 AND month IN (7, 8)
GROUP BY year, month, mode, open_until
ORDER BY year, month;
