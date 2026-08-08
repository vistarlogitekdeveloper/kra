# Demo Reset Request — Clear Review History

Paste-ready brief for whoever owns the `vistar-crm` database. Goal: the KRA
module starts clean for a demo — no cycles, no reviews, no scores — while all
the setup a demo depends on stays exactly where it is.

Companion tooling: `scripts/reset-reviews.mjs` takes a JSON backup and reports
what exists. Run it **before** the truncate.

---

## The prompt

> I need the KRA review history cleared for a demo, on the `vistar-crm`
> database serving `/api/v1/kra`. This is a data reset, not a schema change —
> don't drop or alter anything.
>
> **Delete everything in these entities:**
>
> | Entity | Notes |
> |---|---|
> | Review cycles | `kra.review_cycles` (or equivalent) |
> | Monthly reviews | `kra.monthly_reviews` — the 5-stage pipeline the KRA sheet writes |
> | Per-KRA score rows | the child rows of monthly reviews (self / RM / HR / Finance / management scores) |
> | **Legacy reviews** | **`kra.reviews`** — see the warning below, this is the one that gets missed |
> | Legacy per-KRA rows | child rows of `kra.reviews` |
> | Incentive payout records | payout / settlement rows tied to reviews (NOT the per-employee `monthlyIncentiveAmount` on the employee record) |
>
> **Keep, untouched — the demo needs all of it:**
>
> - Employees and their login/auth rows, including `monthlyIncentiveAmount`,
>   grade, manager mapping and joining dates
> - KRA templates and their items
> - KRA assignments (which employee is rated on which KRAs)
> - Project locations
> - Bonus slabs
> - Departments / designations / any other master data
>
> **⚠ There are TWO review stores. Clearing one is not enough.**
>
> The KRA sheet writes `kra.monthly_reviews`, but `/employee/dashboard` still
> computes its state from the legacy `kra.reviews` table. If only the monthly
> table is cleared, every employee still sees a stale "Self-rating pending" card
> on their home screen while the sheet shows nothing — a half-reset that looks
> like a bug in the demo. Both must be emptied in the same operation.
>
> **Before you start — take a backup.** These rows carry real performance
> scores and settled incentive amounts and cannot be reconstructed:
>
> ```bash
> pg_dump "$DATABASE_URL" \
>   --table='kra.review_cycles' \
>   --table='kra.monthly_reviews*' \
>   --table='kra.reviews*' \
>   --data-only --format=custom \
>   --file=kra-reviews-backup-$(date +%F).dump
> ```
>
> **Find the dependent tables before truncating** — I've named the parents, but
> the child score tables should be discovered rather than guessed:
>
> ```sql
> SELECT
>   tc.table_schema, tc.table_name,          -- the child
>   ccu.table_schema AS refs_schema,
>   ccu.table_name   AS refs_table           -- the parent
> FROM information_schema.table_constraints tc
> JOIN information_schema.constraint_column_usage ccu
>   ON tc.constraint_name = ccu.constraint_name
> WHERE tc.constraint_type = 'FOREIGN KEY'
>   AND ccu.table_name IN ('reviews', 'monthly_reviews', 'review_cycles')
> ORDER BY 2;
> ```
>
> **Then truncate in one transaction**, children first so no FK is violated:
>
> ```sql
> BEGIN;
>
> -- Sanity: record what we're keeping, to compare afterwards.
> SELECT 'employees' AS t, count(*) FROM kra.employees
> UNION ALL SELECT 'kra_templates', count(*) FROM kra.kra_templates
> UNION ALL SELECT 'kra_assignments', count(*) FROM kra.kra_assignments
> UNION ALL SELECT 'project_locations', count(*) FROM kra.project_locations;
>
> -- Add every child table the FK query returned, ahead of its parent.
> TRUNCATE TABLE
>   kra.monthly_reviews,
>   kra.reviews,
>   kra.review_cycles
> CASCADE;
>
> -- Verify: these must all be 0 …
> SELECT 'monthly_reviews' AS t, count(*) FROM kra.monthly_reviews
> UNION ALL SELECT 'reviews', count(*) FROM kra.reviews
> UNION ALL SELECT 'review_cycles', count(*) FROM kra.review_cycles;
>
> -- … and the keep-list counts must be IDENTICAL to the first query.
> -- If any dropped, CASCADE reached too far — ROLLBACK.
>
> COMMIT;
> ```
>
> **`CASCADE` is the risk here.** It silently empties anything with an FK to
> these tables, which is what we want for score rows but not if something
> unexpected points at `review_cycles`. That's why the keep-list counts are
> taken before and re-checked inside the same transaction: if any of them
> change, `ROLLBACK` and tell me what the FK query returned instead of
> committing.
>
> Don't reset sequences or identity columns — new ids continuing from where the
> old ones stopped is fine and avoids colliding with anything cached.
>
> **Acceptance criteria.**
>
> 1. `GET /review-cycles` returns an empty list.
> 2. `GET /reviews/monthly?year=2026&month=7` (and any other month) returns
>    empty.
> 3. `GET /employee/dashboard` as any employee shows **no** current review and
>    no "Self-rating pending" card — this is the legacy-table check.
> 4. `GET /employees` still returns all 38, with grade, manager, joining date
>    and `monthlyIncentiveAmount` intact.
> 5. `GET /kra-templates` and `GET /kra-assignments` are unchanged.
> 6. `GET /locations` is unchanged.

---

## After the reset

1. Re-run the inventory to confirm from the client's side:

   ```bash
   KRA_EMAIL=... KRA_PASSWORD='...' node scripts/reset-reviews.mjs
   ```

   Expect `Review cycles: 0` and `Monthly reviews: 0`.

2. In the app, hard-reload and check as **three** roles, because they read
   different endpoints:
   - an employee → home screen shows no pending review (legacy table)
   - a manager → My Team shows no reviews
   - HR → the Review Dashboard is empty

3. Create the demo cycle in HR → Review Cycles, then confirm fresh monthly
   reviews appear for the demo month. KRA assignments were kept, so employees
   should still be rated on the right KRAs — worth verifying on one employee
   before demoing, since review generation from assignments is the step most
   likely to need a nudge after a wipe.

## What was NOT requested

The employee master data imported via `scripts/import-employees.mjs` stays.
If you also want the roster cleared, that's a separate request — and note the
import script can rebuild it in one command afterwards.
