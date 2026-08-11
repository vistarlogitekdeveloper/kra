# KRA Row Snapshot — Fix + Immediate Workaround

Employee Details shows the CURRENT KRA assignment while the Quarterly KRA Sheet
shows a DIFFERENT set of KRAs. Confirmed on Milind Ingole (VLPL0767), Yash
Thikekar (VLPL1432), Balasaheb Chavan (VLPL1223) and Dattatray Zanjad (VLPL0883).

**The assignment mapping is correct and there is no frontend bug.** The sheet is
rendering a stale snapshot.

---

## Cause

Review KRA rows are copied onto the review when it is generated, and never
revisited. `snapshotRows` has exactly two callers:

| Caller | When |
|---|---|
| `topUpPeriod` (`monthly-reviews.repository.js:250`) | review generation |
| `backfillRowsIfEmpty` (`:328`) | lazily on GET — **but only if the review has ZERO rows** (`if (existing[0].n > 0) return 0;`) |

Nothing re-snapshots a review that already has rows. So:

1. Reviews were regenerated — rows copied from whatever applied then (an earlier
   assignment, or the employee's `default_template_id`).
2. HR then assigned the correct template.
3. `topUpPeriod` skips employees who already have a review (`NOT EXISTS`), so
   those rows were never revisited.

Milind's weightages confirm it: Manager KRA is 5 / 50 / 10 / 5, his sheet reads
5 / 10 / 10 — a different template entirely.

This is the same failure mode as the stale `incentive_eligible_amount`:
generation-time snapshots that don't follow later edits.

---

## Fix now, without a deploy

The affected reviews are unrated, so deleting them is lossless — they regenerate
from the CURRENT assignment on the next list GET.

```sql
BEGIN;

-- Untouched reviews only: anything carrying a score row is left alone.
DELETE FROM kra.monthly_reviews r
WHERE NOT EXISTS (
  SELECT 1 FROM kra.monthly_review_rows rr
  JOIN kra.monthly_row_scores s ON s.row_id = rr.id
  WHERE rr.review_id = r.id
);

SELECT count(*) FROM kra.monthly_reviews;   -- sanity check before committing
COMMIT;
```

Then hard-reload the app and open the monthly reviews list — `generateMonth`
recreates them against each employee's current assignment.

Do it for **all** employees, not just the four reported: any employee whose
assignment changed after generation has the same stale sheet, reported or not.

First confirm an ACTIVE cycle exists and the assignments point at it — that is
what `snapshotRows` matches on, and without it you get blank sheets instead of
corrected ones.

---

## Permanent fix

Without this, the bug returns every time HR re-assigns a template after reviews
exist — and it fails silently, which is the dangerous part: HR sees the right
assignment on the employee record and has no reason to suspect the sheet
disagrees.

### 1. Add to `monthlyReviewsRepository` in `monthly-reviews.repository.js`

Place it immediately before `backfillRowsIfEmpty` (around line 313):

```js
    // Rows are COPIED onto a review when it is generated. If HR re-assigns a KRA
    // template afterwards, the review kept the OLD KRAs forever: the employee
    // record showed the new assignment while the sheet showed the old set, with
    // nothing on either screen to say they disagreed.
    //
    // So for a review NOBODY HAS TOUCHED, re-snapshot its rows when the
    // employee's current active-cycle assignment is newer than the review.
    // Called lazily on GET, like backfillRowsIfEmpty below.
    //
    // Deliberately conservative: it bails if the review has ANY score row at
    // all, even one whose value is null (a reviewer's explicit "N/A"). Those row
    // ids anchor real work and someone chose to mark them, so a sheet that has
    // been started is never rewritten underneath its reviewers. `updated_at` is
    // bumped afterwards so this settles in one pass instead of re-running on
    // every read.
    async resyncRowsIfUntouched(reviewId) {
        const touched = await database_1.prisma.$queryRawUnsafe(`SELECT count(*)::int AS n
       FROM kra.monthly_row_scores s
       JOIN kra.monthly_review_rows rr ON rr.id = s.row_id
       WHERE rr.review_id = $1`, reviewId);
        if (touched[0].n > 0)
            return 0;
        // A newer assignment than the review means the snapshot is out of date.
        // No active-cycle assignment leaves this alone for the backfill below.
        const cmp = await database_1.prisma.$queryRawUnsafe(`SELECT (r.updated_at IS NULL OR r.updated_at < a.assigned_at) AS stale
       FROM kra.monthly_reviews r
       JOIN kra.kra_assignments a ON a.employee_id = r.employee_id
       JOIN kra.review_cycles c ON c.id = a.cycle_id AND c.status = 'ACTIVE'
       WHERE r.id = $1
       ORDER BY a.assigned_at DESC
       LIMIT 1`, reviewId);
        if (cmp.length === 0 || cmp[0].stale !== true)
            return 0;
        const rev = await database_1.prisma.$queryRawUnsafe(`SELECT r.employee_id, e.default_template_id
       FROM kra.monthly_reviews r JOIN kra.employees e ON e.id = r.employee_id
       WHERE r.id = $1`, reviewId);
        if (rev.length === 0)
            return 0;
        return database_1.prisma.$transaction(async (tx) => {
            // Safe to drop: established above that no score row references these.
            await tx.$executeRawUnsafe(`DELETE FROM kra.monthly_review_rows WHERE review_id = $1`, reviewId);
            const n = await snapshotRows(tx, reviewId, rev[0].employee_id, rev[0].default_template_id);
            await tx.$executeRawUnsafe(`UPDATE kra.monthly_reviews SET updated_at = now() WHERE id = $1`, reviewId);
            return n;
        });
    },
```

### 2. Call it from `hydrate` in `monthly-reviews.service.js`

Line 325 currently reads:

```js
    await monthly_reviews_repository_1.monthlyReviewsRepository.backfillRowsIfEmpty(id);
```

Add the resync immediately before it, so a stale sheet self-corrects on the same
GET that renders it:

```js
    await monthly_reviews_repository_1.monthlyReviewsRepository.resyncRowsIfUntouched(id);
    await monthly_reviews_repository_1.monthlyReviewsRepository.backfillRowsIfEmpty(id);
```

Order matters: the resync handles "wrong rows", the backfill handles "no rows".

### Notes

- Do the same in `src/modules/kra_testing/` or accept the drift — it is not
  mounted (`app.js:146` mounts `modules/kra`).
- `node --check src/modules/kra/dist/features/monthly-reviews/monthly-reviews.repository.js`
  before deploying. **I could not validate this code** — see below.
- `updated_at` is bumped so the comparison stops matching after one pass. If
  anything else already touches `updated_at` on generation, use a dedicated
  `rows_synced_at` column instead (same `ADD COLUMN IF NOT EXISTS` pattern the
  module uses for `management_locked_at` and `returned`).

---

## Why this is a handover doc and not a commit

Claude Code's permission classifier blocked three attempts to edit
`vistar_CRM-main` (it permitted one edit earlier in the session, then began
refusing). So the code above is **untested and unlinted** — written against the
real file, but never parsed or run. Treat it as a patch to review, not a drop-in.

Granting write access to that path would let me apply and syntax-check it
directly.

## Verification

After either fix, Milind's sheet should list **Safety of the Facility (5%), Ops
Excellence reports (50%), Inventory accuracy (10%), Monthly review with
customer/Leadership (5%)** and the rest of the 10, matching his Employee Details.
Then spot-check Yash, Balasaheb and Dattatray.

For the permanent fix specifically: re-assign a different template to one test
employee whose review is untouched, reopen their sheet, and confirm the KRAs
change without any manual deletion.
