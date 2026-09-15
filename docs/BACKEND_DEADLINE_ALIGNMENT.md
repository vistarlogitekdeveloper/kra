# Backend request: align every deadline surface with the published schedule

The circulated schedule, which is now the single source of truth on both sides:

| Stage | Pipeline stage | Day of month |
|---|---|---|
| Self-Rating | `SELF_RATING` | **10th** |
| Account & HR Rating | `ACCOUNT_HR_RATING` + `FINANCE_RATING` | **12th** |
| Reporting Manager Rating | `REPORTING_MANAGER_RATING` | **13th** |
| Management Review | `MANAGEMENT_REVIEW` | **15th** |
| Incentive Payout | `INCENTIVE_PAYOUT` | **20th** |

## First: most of this is already right — please don't "fix" it

`src/modules/kra/notifications/config.js` already matches, and it was the app
that was wrong:

```js
SELF_DEADLINE_DAY:       10
REVIEWER_DEADLINE_DAY:   12   // HR (ACCOUNT_HR_RATING) and accounts (FINANCE_RATING)
MANAGER_DEADLINE_DAY:    13   // reporting manager gets an extra day
MANAGEMENT_DEADLINE_DAY: 15
```

The Flutter app was returning **13** for all three Review raters, so it showed
HR and Accounts a deadline one day later than the reminder emails were counting
down to. That is fixed on the client (`ReviewStage.deadlineDay`), and
`test/core/utils/deadline_schedule_test.dart` now pins the table so it cannot
drift again.

So this request is about the four places that still disagree — not about the
numbers above.

---

## 1. `deadlineDayForStage('INCENTIVE_PAYOUT')` returns 12

`notifications/config.js`:

```js
function deadlineDayForStage(stage) {
  if (stage === 'SELF_RATING') return config.SELF_DEADLINE_DAY;          // 10
  if (stage === 'REPORTING_MANAGER_RATING') return config.MANAGER_DEADLINE_DAY;   // 13
  if (stage === 'MANAGEMENT_REVIEW') return config.MANAGEMENT_DEADLINE_DAY;       // 15
  return config.REVIEWER_DEADLINE_DAY;  // 12 — the fall-through
}
```

Anything not named falls through to the HR/Accounts day. `INCENTIVE_PAYOUT`
therefore reports **12** instead of 20, as would any stage added later.

It is latent today because `REVIEW_STAGES` only contains the three raters, so
nothing calls it with `INCENTIVE_PAYOUT` — but it is a trap for whoever adds the
payout reminder (see §2).

**Please**: add `PAYOUT_DEADLINE_DAY: intEnv('KRA_PAYOUT_DEADLINE_DAY', 20)`,
give `INCENTIVE_PAYOUT` its own branch, and make the fall-through throw (or
return `null`) on an unknown stage rather than silently answering 12.

## 2. There is no Incentive Payout reminder at all

The job covers self-rating (days 5/8/10), the three raters (11/12) and — see §3
— management. Nothing fires for the 20th, so the payout deadline exists in the
schedule and on the employee's sheet but nowhere in the reminder pipeline.

**Please** add a payout reminder to whoever owns `INCENTIVE_PAYOUT` (Finance /
HR per `actorRoles`), on the same pattern as the reviewer digests.

## 3. The reporting manager never gets a reminder on their own deadline day

`jobs/reviewReminderJob.js`:

```js
// ---- (3b) Reviewer digests on day 11 / 12 ----
if (config.REVIEWER_REMINDER_DAYS.includes(istDay)) {      // [11, 12]
  ...
  const deadlineDay = deadlineDayForStage('REPORTING_MANAGER_RATING');  // 13
  ...
  isFinalCall: istDay === deadlineDay,                     // 12 === 13 → never true
```

The manager digest is nested inside the 11/12 gate, but the manager's deadline
is the 13th. Two consequences:

- `isFinalCall` is **never true** for a reporting manager, so the "final call"
  wording never reaches the one group that has an extra day.
- On the 13th — their actual deadline — managers get no reminder at all.

This is exactly the 12-vs-13 split that the client had collapsed, showing up on
the backend side. **Please** either add 13 to `REVIEWER_REMINDER_DAYS` and gate
each stage's digest on its own day, or give the manager digest its own day list.
Deriving the reminder days from `deadlineDayForStage(stage)` rather than one
shared list would stop this recurring the next time a date moves.

## 4. Per-cycle deadline columns are unconstrained, and one rule contradicts the schedule

`ReviewCycle` carries four dates:

```prisma
selfRatingDeadline     DateTime @db.Date
managerReviewDeadline  DateTime @db.Date
opsScoringDeadline     DateTime @db.Date
financeScoringDeadline DateTime @db.Date
```

`review-cycles.service.js` validates only their relative order:

```js
selfRatingDeadline     >= endDate
managerReviewDeadline  >= selfRatingDeadline
opsScoringDeadline     >= managerReviewDeadline
financeScoringDeadline >= managerReviewDeadline   // ← contradicts the schedule
```

Two problems:

- **The finance rule is backwards.** Accounts is due on the **12th** and the
  reporting manager on the **13th**, so `financeScoringDeadline` should be on or
  *before* `managerReviewDeadline`. As written, a cycle entered to match the
  published schedule is **rejected**.
- **Nothing ties these dates to the monthly schedule.** HR can save a cycle
  whose `selfRatingDeadline` is the 3rd while every reminder and every screen
  counts to the 10th. Nothing reads these columns for the monthly pipeline
  today — the app parses them and ignores them — so they are a silent source of
  a second, conflicting answer.

**Please** decide which is authoritative and make the other follow:

- *Preferred*: treat the fixed monthly schedule as authoritative, derive these
  four dates from it when a cycle is created, and make them read-only —
  or drop them from the create/update payload entirely.
- *Otherwise*: if they are meant to be per-cycle overrides, say so, expose them
  on `GET /review-cycles`, and we will make the app count down to them instead
  of to its own constants. Either answer is workable; having both is not.

Also worth confirming: `opsScoringDeadline` refers to an Ops Excellence scoring
step that the app does not model at all — no KRA is ever assigned to Ops, and
the compliance report says so explicitly. If Ops scoring is genuinely part of
the process, it needs a stage; if not, that column is dead weight.

---

## 5. Please confirm no environment override is in play

Every day is `intEnv(...)`, so production can silently differ from the defaults:

```
KRA_SELF_DEADLINE_DAY, KRA_REVIEWER_DEADLINE_DAY, KRA_MANAGER_DEADLINE_DAY,
KRA_MANAGEMENT_DEADLINE_DAY, KRA_SELF_REMINDER_DAYS, KRA_REVIEWER_REMINDER_DAYS,
KRA_REMINDER_PERIOD_OFFSET_MONTHS
```

Please confirm none of these are set in the production environment to anything
other than 10 / 12 / 13 / 15. The client now hard-codes the schedule, so an
override would put the emails and the app back out of step — which is the
failure we just removed.

If overrides are meant to stay configurable, the better answer is to expose the
resolved schedule on an endpoint (e.g. `GET /kra/config/deadlines` →
`{ SELF_RATING: 10, ACCOUNT_HR_RATING: 12, FINANCE_RATING: 12,
REPORTING_MANAGER_RATING: 13, MANAGEMENT_REVIEW: 15, INCENTIVE_PAYOUT: 20 }`)
and we will read it at startup instead of hard-coding it.

---

## What the app does now, for reference

- `ReviewStage.deadlineDay` is the client's single source; every countdown,
  banner and notice resolves through it.
- The quarterly KRA sheet now shows each viewer their own stage's deadline —
  previously only the employee self-rate and manager-rate screens showed a date,
  so HR, Accounts and Management were never given one anywhere in the app.
- `PERIOD_OFFSET_MONTHS: 1` ("August's review is rated during September") is the
  backend's convention. The app treats a review's deadline as falling in the
  review's **own** calendar month. That difference has not bitten yet because
  the day numbers are what the copy shows, but if reminders and the app ever
  need to name the same *date*, this is where they will diverge — worth a
  sentence in your reply confirming which month the deadline belongs to.
