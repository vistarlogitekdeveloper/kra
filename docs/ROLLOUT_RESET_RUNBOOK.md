# Rollout / Handover Reset Runbook

How to bring the KRA module up clean for the demo and handover, verified against
the backend source (`vistar_CRM-main`, `src/modules/kra`, mounted at
`/api/v1/kra` by `src/app.js:146`).

**Headline: the monthly-review side resets itself. No code rewrite is needed.**
What does need doing is making sure the *inputs* to that regeneration exist,
and clearing the second review store the regeneration doesn't touch.

---

## 1. Why no rewrite is needed

`GET /reviews/monthly?year=&month=` calls `generateMonth` **before** it lists
(`monthly-reviews.service.js:309`, commented "Self-healing generation"). That
runs `topUpPeriod` (`monthly-reviews.repository.js:229`), which for every
**active** employee lacking a review that month inserts one with:

| Column | Value |
|---|---|
| `current_stage` | `SELF_RATING` |
| `payout_status` | `PENDING` |
| `incentive_eligible_amount` | the employee's **current** `monthly_incentive_amount` |
| KRA rows | snapshotted by `snapshotRows` — see §2 |

It is idempotent (`NOT EXISTS` + `ON CONFLICT DO NOTHING`), so existing reviews
and scores are never touched.

Three consequences worth knowing:

- **Deleting `kra.monthly_reviews` is safe and self-repairing.** Open the app and
  the period repopulates, everyone at Self-Rating, 0%, nothing rated.
- **The stale-incentive bug disappears for regenerated rows.** The snapshot is
  taken now, so it picks up the corrected amounts (Dinesh at ₹1,000, not
  ₹5,000). The bug only ever affected rows created *before* an edit.
- **The `409 RES_002` lock disappears too.** New rows are `SELF_RATING`, so the
  "Review is completed; scores are locked" guard never fires.

---

## 2. ⚠ The one real rollout risk: blank KRA sheets

`snapshotRows` (`monthly-reviews.repository.js:~190-222`) takes the review's KRA
rows from **two sources, in order**:

1. The employee's KRA assignment joined to a cycle where **`cyc.status = 'ACTIVE'`**
   (lines 199-204).
2. **Fallback:** the items of the employee's `default_template_id` (lines 206-213).

If neither yields rows, `source.length === 0` and **the review is created with
ZERO KRA rows** — a blank sheet with nothing to rate. The employee cannot
self-rate, and it looks like the app is broken.

So **before** anyone opens the app:

```sql
-- Must return at least one row, or assignments contribute nothing.
SELECT id, name, status FROM kra.review_cycles WHERE status = 'ACTIVE';

-- Employees who would generate a BLANK sheet: no active-cycle assignment AND
-- no default template. This must return ZERO rows.
SELECT e.employee_code, e.full_name
FROM kra.employees e
WHERE e.is_active = true
  AND e.default_template_id IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM kra.kra_assignments a
    JOIN kra.review_cycles c ON c.id = a.cycle_id
    WHERE a.employee_id = e.id AND c.status = 'ACTIVE')
ORDER BY 1;
```

If the second query returns anybody, fix it before the demo: set an ACTIVE
cycle with assignments for them, or give them a `default_template_id`.

**If you deleted the review cycles**, this is almost certainly your state — the
assignment path needs an ACTIVE cycle to match. Recreate one and re-assign, or
rely on default templates.

Also note `dashboard.service.js:14` (`ensureCycle`) throws
`NotFoundError('Review cycle')`, so **HR dashboard endpoints 404 with no cycle**.
A cycle is required for HR screens regardless of review generation.

---

## 3. The second store the regeneration does NOT touch

Review state lives in two places, and `topUpPeriod` only owns one:

| Store | Read by | Cleared by regeneration? |
|---|---|---|
| `kra.monthly_reviews` (+ `monthly_review_rows`, `monthly_row_scores`) | the Quarterly KRA Sheet, all `/reviews/monthly*` | self-heals ✅ |
| **legacy `kra.reviews`** (+ its scoring cells) | employee-facing surfaces via Prisma `prisma.review` (`employee.service.js:86`, `reviewsRepository`), and HR's `locationHeatmap` (`dashboard.service.js:200,216`) | **no ❌** |

The legacy table is reached through the Prisma `Review` model, not raw
`kra.reviews` SQL, which is why it is easy to miss. If it still holds rows after
you clear the monthly tables, employee-facing screens keep showing old state
while the KRA sheet shows none.

```sql
SELECT count(*) FROM kra.reviews;   -- expect 0 for a clean handover
```

Clear it (and its dependent score/cell rows) in the same transaction pattern as
[DEMO_RESET_REQUEST.md](DEMO_RESET_REQUEST.md) — back up first, discover child
tables via the FK query, and re-check the keep-list counts before `COMMIT`.

---

## 4. Reset sequence

1. **Back up** — `pg_dump` the review tables (see DEMO_RESET_REQUEST.md §backup).
2. **Clear** `kra.monthly_reviews` + children *(already done)* **and legacy
   `kra.reviews`** + children.
3. **Ensure an ACTIVE cycle** and run the §2 blank-sheet query until it returns
   zero rows.
4. **Hard-reload the app** (Ctrl+Shift+R). A plain navigation is not enough —
   `monthlyReviewListProvider` calls `ref.keepAlive()`, so lists survive
   navigation and only refetch on pull-to-refresh or a full reload.
5. **Open the monthly reviews list** for the demo month. This is what triggers
   regeneration. Expect every active employee at Self-Rating / 0%.

## 5. Verification — check all three roles

They read different endpoints, so one passing does not imply the others.

| Role | Screen | Expected |
|---|---|---|
| Employee | Home + My KRA | no pending-review card from stale state; sheet lists their KRAs with empty cells |
| Employee | My KRA | **KRA rows are present** — if the sheet is blank, §2 was not satisfied |
| Manager | My Team → Reviews | reports listed, all Self-Rating / 0%, no "Paid" badge |
| HR | Review Dashboard | every employee Self-Rating / 0%, ₹0 payable |
| HR | Employees | all 38 present with grade, manager, joining date, incentive |

Then rate one KRA end-to-end as an employee and confirm it saves (no `409`).

## 6. Client-side state to be aware of

- `invalidateReviewCaches()` now runs after any HR employee edit, so incentive
  and grade changes reach the review screens without a restart.
- The dashboard opens on the newest month **worth showing**; with everything
  empty it falls back to the current month, which is what you want for a demo.
- A review with no scores can no longer render as "Completed" or "Paid", so
  leftover header flags cannot produce a false payout badge mid-demo.

## 7. Backend change pending deploy

`monthly-reviews.service.js:497-501` narrows the completed-review lock so a
`COMPLETED` row with **no scores** accepts a self-rating, while a genuinely
scored one stays locked. With the tables wiped this is now a **safety net rather
than a necessity** (regenerated rows are `SELF_RATING`), so it can go out with
the next ordinary deploy.

Not yet syntax-checked by machine — run before deploying:

```bash
node --check src/modules/kra/dist/features/monthly-reviews/monthly-reviews.service.js
```

`src/modules/kra_testing/` mirrors this module and still has the original guard.
It is not mounted (`app.js:146` mounts `modules/kra`), but the two will drift.

## 8. Still outstanding for handover

- **Incentive snapshot staleness** for any review created *before* an amount
  change — regenerated rows are correct, but the underlying behaviour is
  unfixed. See the read-time re-resolution proposal (follow the existing
  `refreshReviewerGroups` pattern) in the notes on
  [ACCESS_CONTROL_DESIGN.md](ACCESS_CONTROL_DESIGN.md)'s sibling discussion.
- **`MANAGEMENT` / `SUPER_ADMIN` roles** — [BACKEND_CHANGE_REQUEST.md](BACKEND_CHANGE_REQUEST.md).
- **`/manager/team` scoping** by reporting line, and `hasReports` on login.
