# Moving ONE employee's KRA to a different reviewer

Worked example (the case this was written for):

| | |
|---|---|
| Employee | Dattatray Dadabhau Zanjad — `VLPL0883`, id `a914b68f-6efb-49bf-aac6-dbbb217b0d3e` |
| KRA | **Cost optimization**, weightage 5%, `displayOrder` 5 |
| Now | `reviewerGroup: "MANAGER"` — rated by the reporting manager (Amol Laxman Veer) |
| Wanted | rated by **Accounts** (Sagar), **for this employee only** |
| Review | `2217a3e1-caf7-4edb-bddd-0e7d601c25f2`, period 2026-09, stage SELF_RATING, no scores yet |

---

## How the reviewer is resolved (why this works)

`monthly_review_rows.reviewer_group` is what every screen reads, and it is
**self-healed on every review read**: `findRows()` calls
`refreshReviewerGroups(reviewId)` before selecting, which resolves each row by
`display_order` in this order:

1. `kra_assignment_items.reviewer_group` — the employee's own ACTIVE-cycle
   assignment item. **A per-employee override, and it wins.**
2. else the source template's `kra_template_items.score_source`.
3. else, no active assignment → the employee's `default_template_id` template's
   `score_source`.
4. else `'MANAGER'`.

Two consequences worth knowing:

- The row is refreshed server-side, so **every login sees the same value** —
  Accounts, HR and admin alike. Client-side patching could never achieve this:
  the template/assignment reads are `HR_ADMIN`/`ADMIN`-only.
- Because rule 1 exists, a per-employee override needs **no template edit** —
  but nothing in the app or the API can currently write it (see the backend
  request at the end).

Vocabulary: `score_source` is the enum `MANAGER | HR_FEED | OPS_FEED |
ACCOUNTS_FEED`. Accounts is **`ACCOUNTS_FEED`**. The row's `reviewer_group` is
free text and the readers accept `ACCOUNTS`, `ACCOUNT`, `ACCOUNTS_FEED` or
`FINANCE`; prefer `ACCOUNTS_FEED` so it matches the enum.

---

## Route A — one SQL statement (fastest, exact, no template churn)

Writes the rule-1 override. Verify first:

```sql
-- The employee's ACTIVE-cycle assignment and the item to change.
SELECT ai.id, ai.name, ai.sort_order, ai.reviewer_group
FROM kra.kra_assignment_items ai
WHERE ai.assignment_id = (
  SELECT a.id FROM kra.kra_assignments a
  JOIN kra.review_cycles cyc ON cyc.id = a.cycle_id
  WHERE a.employee_id = 'a914b68f-6efb-49bf-aac6-dbbb217b0d3e'
    AND cyc.status = 'ACTIVE'
  ORDER BY a.assigned_at DESC LIMIT 1)
ORDER BY ai.sort_order;
```

Expect 12 rows with `Cost optimization` at `sort_order` **5** — the same number
as the review row's `display_order`. If the SELECT returns **nothing**, this
employee has no active-cycle assignment, so rule 1 does not apply; use Route B.

```sql
UPDATE kra.kra_assignment_items
SET reviewer_group = 'ACCOUNTS_FEED'
WHERE assignment_id = (
        SELECT a.id FROM kra.kra_assignments a
        JOIN kra.review_cycles cyc ON cyc.id = a.cycle_id
        WHERE a.employee_id = 'a914b68f-6efb-49bf-aac6-dbbb217b0d3e'
          AND cyc.status = 'ACTIVE'
        ORDER BY a.assigned_at DESC LIMIT 1)
  AND name = 'Cost optimization';
```

Then just reopen the sheet — the next GET rewrites the row. Confirm:

```sql
SELECT name, display_order, reviewer_group FROM kra.monthly_review_rows
WHERE review_id = '2217a3e1-caf7-4edb-bddd-0e7d601c25f2' ORDER BY display_order;
```

Safe on live data: it touches one column on one row. Scores live in
`monthly_row_scores` and are neither read nor written here.

**Do not instead `PATCH /kra-assignments/:id` with `items[]`.** That path
`deleteMany`s every assignment item and recreates them through Prisma, whose
`KraAssignmentItem` model has no `reviewerGroup` field — so it would **wipe this
override and every other one**, silently. `AssignmentItemInputSchema` also has
no `reviewerGroup` key, and Zod strips unknown keys rather than erroring, so a
client sending one gets a 200 and no change.

## Route B — clone the template (no DB access needed, all in the app)

Editing the shared template in place would move the KRA to Accounts for
**everyone** on it. Cloning keeps it to one person:

1. **HR → Templates** → find this employee's template → **Clone**.
2. Open the clone → rename it so the exception is obvious
   (e.g. `Site Manager — Dattatray (VLPL0883)`) → set **Cost optimization**'s
   reviewer to **Accounts** → Save.
3. **HR → Assign KRA** → assign this employee to the cloned template.
4. Reopen the sheet. Rule 2 now yields `ACCOUNTS_FEED`.

Keep the clone's item **order** identical — matching is
`monthly_review_rows.display_order = sort_order`, so a reordered clone
re-labels the wrong KRA.

The cost is a template per exception. That is why Route A, and ultimately the
backend request below, is the better long-term answer.

### Not a route: editing the shared template

`PATCH /kra-templates/:id` diffs by item id and *does* persist `scoreSource`, so
it works — but it applies to every employee on that template, which is not what
was asked. It also 409s (`KRA in use by existing reviews`) if the item is
referenced by a legacy `kra.review_rows` row.

---

## Frontend change that had to land with this

Moving a KRA to Accounts used to strand it: the sheet's edit gate asked for the
literal `FINANCE` role, while everything that says *who must act* — badges,
chips, "needs your action" counts — resolves through `ReviewStage.actorRoles`,
where `FINANCE_RATING` is `{finance, hrAdmin}`. HR Admin holds the Accounts seat
deliberately (the commercial/HR-admin post covers Accounts rating, and one
`UserRole` cannot say "HR Admin AND Accounts"). So Sagar would have been told
the KRA needed his action and then handed a **read-only** cell, with nobody able
to rate it.

Both role-gated Review cells now resolve through `actorRoles` and the caller's
**full** role set — see `canRateReviewStage` in
`quarterly_kra_sheet_screen.dart` and
`test/features/reviews/review_stage_role_gate_test.dart`, which asserts the gate
and `actorRoles` agree for every role.

The reporting-manager cell is unchanged: that one is a relationship
(`review.managerId == scope.userId`), not a role.

---

## Backend request: first-class per-employee override

So HR can do this from the app instead of by SQL or by cloning a template.

**Why it isn't possible today:** `kra.kra_assignment_items.reviewer_group`
exists (added by the lazy `ensureReviewerGroupColumns()` top-up in
`monthly-reviews.repository.js`) and `refreshReviewerGroups()` already **prefers
it** over the template — but nothing can write it. Prisma's `KraAssignmentItem`
model has no such field, and `AssignmentItemInputSchema` does not accept it.

Please add a narrow endpoint rather than widening the items-replacement path,
which is destructive by design:

```
PATCH /api/v1/kra/kra-assignments/:id/items/reviewer
Roles: HR_ADMIN
Body: { "sortOrder": 5, "reviewerGroup": "ACCOUNTS_FEED" }
      // reviewerGroup in MANAGER | HR_FEED | ACCOUNTS_FEED, or null to clear
      // the override and fall back to the template
-> 200 { success: true, data: { assignmentId, sortOrder, reviewerGroup } }
```

Implementation notes:

- Write with raw SQL (`UPDATE kra.kra_assignment_items SET reviewer_group = $1
  WHERE assignment_id = $2 AND sort_order = $3`) or add `reviewerGroup` to the
  Prisma model first — the column is not in `schema.prisma` today.
- Call `ensureReviewerGroupColumns()` first, as the monthly-reviews repository
  does, so this works on a DB that has not been topped up yet.
- 404 if no item matches `(assignmentId, sortOrder)`; 409 if the assignment is
  `is_locked`.
- No propagation code is needed — `refreshReviewerGroups()` already runs on
  every review read.
- Please also **preserve `reviewer_group` across the existing items-replacement
  PATCH** (re-apply per-item overrides by `sort_order` after the recreate), or
  the next assignment edit silently discards every override. This is the actual
  bug behind "the KRA mapping keeps reverting".
- And return `reviewerGroup` on each item in `GET /kra-assignments` and
  `GET /kra-assignments/:id`, so the app can show the current value.

Once that ships, the app can put a reviewer picker on the KRA row for HR-tier
users; the read path (`kraReviewerMapProvider`, which already reads assignment
items before the template) needs no change.
