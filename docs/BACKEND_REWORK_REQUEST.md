# Backend Change Request — Rework + Manager Rating Ceiling

Paste-ready brief for whoever owns the KRA backend (`vistar-crm`,
`src/modules/kra`, mounted at `/api/v1/kra` by `src/app.js:146`).

Three changes, all in the monthly-reviews feature. The Flutter client is waiting
on #1 and #2 before its UI can be built; #3 hardens a rule the client currently
enforces on its own.

---

## The prompt

> You are working on the Vistar KRA backend (`/api/v1/kra`), specifically
> `src/modules/kra/dist/features/monthly-reviews/`. Note this module ships as
> compiled `dist` JS with no TypeScript source and no build step (`npm start` is
> `node src/server.js`), so edit the `dist` files directly. `src/modules/kra_testing/`
> mirrors this module and is NOT mounted — keep it in sync or leave it, but don't
> edit it instead of `modules/kra`.
>
> Do not change review scoring or incentive calculation, the `{ success, data }`
> envelope, or any existing field name. A frontend depends on all three.
>
> ### Change 1 — let the reporting manager send a self-rating back for rework
>
> A reporting manager reviewing their team member's self-rating may find an
> anomaly (e.g. everything claimed at 100%) and needs to return it to the
> employee for revision. Today only management can return work.
>
> In `monthly-reviews.service.js`, `submitStage` currently computes:
>
> ```js
> // Management review can return the work to the reporting manager.
> const isReturn = stage === 'MANAGEMENT_REVIEW' && body.approved === false;
> ...
> if (isReturn) {
>     await monthlyReviewsRepository.setCurrentStage(tx, id, 'REPORTING_MANAGER_RATING');
> }
> ```
>
> Generalise it to a one-step-back return:
>
> ```js
> // A rater can hand the work back exactly ONE step by submitting with
> // approved === false:
> //   * Management review  → back to the reporting manager.
> //   * Reporting manager  → back to the employee's SELF_RATING.
> // Any other stage ignores `approved` and advances as usual.
> const returnTo = body.approved === false
>     ? (stage === 'MANAGEMENT_REVIEW' ? 'REPORTING_MANAGER_RATING'
>         : stage === 'REPORTING_MANAGER_RATING' ? 'SELF_RATING'
>             : null)
>     : null;
> const isReturn = returnTo !== null;
> ...
> if (isReturn) {
>     await monthlyReviewsRepository.setCurrentStage(tx, id, returnTo);
> }
> ```
>
> Requirements:
>
> - **Keep `assertCanAct` as the gate.** Only the review's own reporting manager
>   may submit `REPORTING_MANAGER_RATING`, so only they can return it. Do not
>   role-gate this — it is a relationship, and a reporting manager may hold any
>   role.
> - **`body.comment` is the reason** and must be recorded on the stage record, as
>   it already is. The employee needs to see why it came back.
> - **Do not fire the incentive snapshot on a return.** The existing guard
>   `if (stage === 'REPORTING_MANAGER_RATING' && !isReturn)` already handles this
>   correctly once `isReturn` is generalised — please don't refactor it away.
> - **Do not delete the employee's existing self scores.** They revise them; they
>   should not start from a blank sheet.
> - Returning a review already at `SELF_RATING` should be a harmless no-op or a
>   clear 409, not a crash.
>
> ### Change 2 — make a return distinguishable from a submission
>
> This is what actually blocks the UI. The client treats *the presence of a stage
> record* as proof that stage was submitted. After a return, the
> `REPORTING_MANAGER_RATING` record exists, so the client would show the manager's
> stage as **submitted** when in fact the work went backwards. The same flaw
> already applies to management returns today.
>
> Add an explicit marker to each stage record in the review payload:
>
> ```json
> "stageRecords": {
>   "REPORTING_MANAGER_RATING": {
>     "actorId": "...",
>     "actorName": "Amol Laxman Veer",
>     "submittedAt": "2026-08-10T06:12:00.000Z",
>     "comment": "Every KRA is at 100% — please revisit inventory accuracy.",
>     "returned": true
>   }
> }
> ```
>
> `returned` is `true` when that submission sent the review **back** a stage, and
> `false`/absent for a normal forward submission. Persist it on
> `kra.monthly_stage_records` (an `ADD COLUMN IF NOT EXISTS returned BOOLEAN
> DEFAULT false` follows the same pattern the module already uses for
> `management_locked_at`).
>
> Please also surface it on the LIST endpoint (`GET /reviews/monthly?year=&month=`)
> in whatever way fits — a boolean like `reworkRequested` on the summary row is
> enough — so a manager's list can badge "sent back" without fetching each review.
>
> The client already parses `stageRecords` with `actorId`, `actorName`,
> `submittedAt` and `comment`, so adding `returned` needs no other new fields.
>
> ### Change 3 — enforce the manager's rating ceiling server-side
>
> Business rule: **a reporting manager's score for a KRA may not exceed the
> employee's own score for that same KRA and month.** A manager moderates a
> self-assessment; they do not inflate it.
>
> The client now enforces this in its rating UI, but a client-side cap is not a
> rule — a stale build or a direct API call bypasses it. Please enforce it on
> writes for `stage === 'REPORTING_MANAGER_RATING'`, in **both**
> `POST /reviews/monthly/:id/save-scores` and `POST /reviews/monthly/:id/submit-stage`:
>
> - For each row in `rowScores`, reject if the submitted value exceeds that row's
>   existing `SELF_RATING` value.
> - If the row has **no** self score yet, reject: the employee rates first.
> - Use a 4xx with a specific code and name the offending rows in `error.details`
>   so the UI can point at them, consistent with how `VAL_001` reports field
>   errors today.
> - Enforce per row, on write only. Do not retroactively rewrite or reject
>   existing data that already violates this.
>
> ### Acceptance criteria
>
> 1. `POST /reviews/monthly/:id/submit-stage` as the review's reporting manager
>    with `{ "stage": "REPORTING_MANAGER_RATING", "approved": false, "comment": "..." }`
>    → 200, and `GET /reviews/monthly/:id` then shows `currentStage: "SELF_RATING"`.
> 2. The employee's self scores are unchanged by that call, and the employee can
>    save new self scores afterwards (no 409).
> 3. That review's `stageRecords.REPORTING_MANAGER_RATING` carries
>    `returned: true` and the comment.
> 4. A normal forward submit (`approved` omitted or `true`) still advances to
>    `ACCOUNT_HR_RATING` and records `returned: false`.
> 5. Someone who is NOT that review's reporting manager gets 403 for the same
>    call.
> 6. Management's existing return (`MANAGEMENT_REVIEW` + `approved: false`) still
>    goes back to `REPORTING_MANAGER_RATING` — no regression.
> 7. `save-scores` for `REPORTING_MANAGER_RATING` with a value above the row's
>    self score → 4xx naming that row; equal to the self score → 200.
> 8. `save-scores` for `REPORTING_MANAGER_RATING` on a row with no self score
>    → 4xx.
> 9. The incentive snapshot is NOT taken on a return (`manager_weighted_pct`
>    unchanged by the call in criterion 1).

---

## Note on an existing local edit

`monthly-reviews.service.js` in the working checkout already contains one
uncommitted change from earlier debugging: the `COMPLETED` score lock was
narrowed so a review whose `current_stage` is `COMPLETED` but which has **no
scores** accepts a self-rating, while a genuinely scored one stays locked. That
was needed because a half-finished data reset left headers at `COMPLETED` with
their score rows deleted, permanently blocking self-rating with a
`409 RES_002`. Please keep it, and run `node --check` on the file before
deploying — it has not been machine-validated.

## Frontend work waiting on this

Once changes 1 and 2 are deployed, the client adds:

- a **Send back for rework** action for the reporting manager on the quarterly
  KRA sheet, with a required reason (strings are already in `app_strings.dart`)
- a "Returned for rework" state plus the manager's reason on the employee's
  sheet and home card, read from `stageRecords[...].returned` + `comment`
- a "sent back" badge on the manager's monthly list, from the summary flag

Change 3 needs no client work — it is a safety net behind the cap the client
already applies, though the client will surface the error detail if a write is
rejected.
