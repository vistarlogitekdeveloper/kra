# Backend Change Request — Self-Rating Submit, Manager Email, Profile PATCH

Paste-ready brief for the KRA backend (`vistar-crm`, `src/modules/kra`, mounted
at `/api/v1/kra` by `src/app.js:146`).

Everything here blocks a frontend feature that is either requested or already
written. Verified against the live source, not assumed.

## Already done — do not redo

Checked before writing this, because several earlier requests have landed:

| Item | Status |
|---|---|
| `MANAGEMENT` + `SUPER_ADMIN` roles | ✅ in the Prisma enum, the zod `RoleEnum` (`employees.types.js:15`) and the lazy DB widener (`employees.repository.js:24`) |
| `hasReports` on login | ✅ `auth.service.js:58,120` |
| `/manager/team` scoped by reporting line | ✅ filtered to `managerId: actor.id` |
| Rework return + `returned` flag | ✅ |
| Manager rating ceiling (`VAL_MANAGER_CEILING`) | ✅ |
| KRA row re-snapshot on re-assignment | ✅ `resyncRowsIfUntouched` |

---

## The prompt

> You are working on the Vistar KRA backend (`/api/v1/kra`), in
> `src/modules/kra/dist/`. This module ships as compiled `dist` JS with no
> TypeScript source and no build step (`npm start` is `node src/server.js`), so
> edit the `dist` files directly. `src/modules/kra_testing/` mirrors it and is NOT
> mounted — don't edit that one instead.
>
> Do not change the incentive formula, the `{ success, data }` envelope, or any
> existing field name. A Flutter client depends on all three.
>
> ### Change 1 — let an employee explicitly SUBMIT their self-rating
>
> The client needs a Submit button that finalises the self-rating. Today that is
> impossible, because two rules collide:
>
> * `assertCanAct` (`monthly-reviews.service.js:266`) rejects a submit whose stage
>   isn't the review's current stage:
>   `if (header.current_stage !== stage) throw ConflictError(...)`.
> * `saveScores` auto-advances the cursor off `SELF_RATING` the moment the
>   employee saves any score (`monthly-reviews.service.js:563-572`):
>
>   ```js
>   const furthest = await monthlyReviewsRepository.furthestScoredRatingStage(tx, id);
>   let target = furthest;
>   if (target === 'SELF_RATING')
>       target = 'REPORTING_MANAGER_RATING';
>   ```
>
> So by the time the employee presses Submit the review is already at
> `REPORTING_MANAGER_RATING`, and `submit-stage` with `SELF_RATING` returns 409
> **every time**.
>
> **Required:** stop promoting `SELF_RATING` → `REPORTING_MANAGER_RATING` in
> `saveScores`. Delete those two lines (565-566) so `target` stays whatever the
> scores actually prove. Saving a self score should leave the cursor at
> `SELF_RATING`; the employee's explicit `POST /reviews/monthly/:id/submit-stage`
> with `{ "stage": "SELF_RATING" }` is what advances it (the existing `nextStage`
> path already does that correctly).
>
> Keep the rest of that block exactly as-is: never advance past
> `MANAGEMENT_REVIEW`, never move backwards, never touch a `COMPLETED` review.
>
> **Why this is safe for dashboards.** The comment on that block says the
> auto-advance exists "so dashboards reading current_stage keep pace". That is
> already handled elsewhere and does not depend on the cursor moving: `toSummary`
> derives `displayStage` as the furthest of `current_stage` and the scored stage
> (`monthly-reviews.service.js:64-66`), and the client prefers `displayStage` over
> the cursor for exactly this reason. A review sitting at `SELF_RATING` with self
> scores present still reports progress correctly.
>
> ### Change 2 — email the reporting manager when a self-rating is submitted
>
> On a successful `submit-stage` with `stage: "SELF_RATING"`, send one email:
>
> * **To:** the employee's reporting manager (`employees.manager_id` → their
>   `email`).
> * **CC:** HR, following the convention the other modules use — a fixed list
>   from an env var with a code default, so it changes without a deploy:
>
>   ```js
>   const ALWAYS_CC = (process.env.KRA_ALWAYS_CC_EMAILS || 'hr@vistarlogitek.com')
>     .split(',').map((s) => s.trim()).filter(Boolean);
>   ```
>
>   (Mirrors `LR_ALWAYS_CC_EMAILS` in `lr-management/services/lrPaymentEmail.service.js`.)
> * **Content:** who submitted, their employee code, and which month — e.g.
>   *"Milind Vijay Ingole (VLPL0767) has submitted their self-rating for August
>   2026."* Include a link if you have a suitable base URL; otherwise plain text
>   is fine.
>
> SMTP is already configured and working in this module —
> `dist/shared/utils/mailer.js`, using `SMTP_HOST / SMTP_PORT / SMTP_SECURE /
> SMTP_USER / SMTP_PASS / SMTP_FROM`. But that helper currently exports only
> `sendPasswordResetEmail` and takes a single `toEmail` with **no CC support**, so
> extend it (e.g. add `sendSelfRatingSubmittedEmail(to, cc, {...})`, or generalise
> a shared `send({to, cc, subject, text})`). Reuse the existing transport rather
> than creating a second one.
>
> **Requirements:**
>
> * **Delivery failure must NOT fail the submit.** The employee's rating is
>   already committed; a bounced mail cannot roll that back. Wrap the send so it
>   logs and swallows, exactly as `mailer.js` already does for password resets.
> * Send AFTER the transaction commits, so no email goes out for a submit that
>   then rolled back.
> * Skip silently (with a log) when the employee has no manager, or the manager
>   has no email address — several employees share role mailboxes and some rows
>   have `email` null.
> * Send exactly one mail per submit, not one per KRA row.
>
> ### Change 3 — add `PATCH /employee/profile`
>
> The client already builds and sends this request, and has done for a while, but
> **the route does not exist**: `employee.routes.js` declares only GETs plus
> `POST /reviews/:reviewId/self-rate`. So an employee editing their phone number
> sees a success path client-side and the value never persists.
>
> Add `PATCH /employee/profile`, accepting **only** `phone`, and returning the
> updated profile in the same shape as the existing `GET /employee/profile` (the
> client parses the response and refreshes its cache from it).
>
> * `Employee.phone` already exists as `String?` in the Prisma schema — **no
>   migration needed**.
> * Scope it to the caller: an employee may only patch their OWN row. Take the id
>   from the auth context, never from the body.
> * Reject any other field. The client already refuses to send anything but
>   `phone`/`photoUrl`, and the server should be the real boundary.
> * `photoUrl` is NOT in scope — see below.
>
> ### Acceptance criteria
>
> 1. Employee saves a self score → `GET /reviews/monthly/:id` still reports
>    `currentStage: "SELF_RATING"`, and `displayStage` still reflects the score.
> 2. `POST /reviews/monthly/:id/submit-stage` `{ "stage": "SELF_RATING" }` as the
>    review owner → 200, and the review then reads
>    `currentStage: "REPORTING_MANAGER_RATING"`.
> 3. Someone who is not the review owner gets 403 for that call.
> 4. That submit sends one email to the reporting manager with HR in CC.
> 5. With SMTP deliberately misconfigured, the same submit still returns 200 —
>    the failure is logged only.
> 6. A submit for an employee with no manager (or a manager with no email) still
>    returns 200.
> 7. `PATCH /employee/profile` `{ "phone": "9876543210" }` → 200, and a
>    subsequent `GET /employee/profile` returns the new number.
> 8. `PATCH /employee/profile` `{ "role": "SUPER_ADMIN" }` → rejected.
> 9. Existing flows unaffected: manager rating still advances to
>    `ACCOUNT_HR_RATING`, the rework return still works, `mark-paid` still
>    completes.
>
> Run `node --check` on each file you touch before deploying.

---

## Explicitly out of scope: the profile picture

The app has an "add a photo" affordance on the edit-profile screen, but it is
**decorative** — a `Container` with an `Icon` and no `onTap`. There is no picker,
no upload, and no `photo_url` column on `Employee`.

So this is an unbuilt feature, not a save bug, and it needs a decision before any
code: where files are stored (S3/R2/local disk), size and type limits, whether
old images are cleaned up, and whether HR can change someone else's picture. It
is deliberately left out of this batch. Raise it separately if it's wanted for
the rollout.

## Still open from an earlier request

`incentive_eligible_amount` is still snapshotted once at generation and never
updated — verified: the column is INSERTed at `monthly-reviews.repository.js:244`
and read at `:513`, with no `UPDATE` anywhere. So editing an employee's monthly
incentive does not reach reviews that already exist.

Full brief, including the recommended read-time re-resolution for non-`PAID`
reviews, is in the notes accompanying that fix. Not urgent for the demo, since
regenerated reviews snapshot the current amount — but it recurs whenever HR
edits an amount mid-month.

## Frontend work waiting on this

Once changes 1–2 are deployed: a **Submit** button at the end of the self-rating
with a "your KRA is submitted successfully" confirmation, and the submitted state
reflected on the sheet. Once change 3 is deployed the phone field starts
persisting with no client change at all — the request is already correct.
