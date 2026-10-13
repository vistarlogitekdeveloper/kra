# Rating access — deadline windows with super-admin overrides

Status: design contract v2, 2026-10-02 (v1 + the fixes from an adversarial design
review). Both repos implement exactly this; if the code and this file disagree,
one of them is a bug.

## 1. What the product asked for

- **By default the date decides.** Each rating stage of a month closes at its own
  deadline in the month after the one being rated.
- **The super admin can override any time, per organisation, per stage, per
  month**: open a stage until a date or with no end date ("rate and edit", like a
  normal open window), close it, or put it back on the date rule.
- **July and August 2026 ship pre-opened** for every organisation and every stage
  until 31 Oct 2026 (end of day IST), replacing the hard-coded client reopen of
  4bc2c28. Because a reopen is "rate and edit", ratings already given in those two
  months can be changed until then — confirmed by the product owner.

An override changes **when** a stage accepts writes, never **what** is writable:
a COMPLETED (paid) review stays locked (except the existing blank-SELF backfill of
e8715339), and locked management scores need an unlock first.

"Role-wise" means per **rating stage**, which is how seats are already modelled:

| Stage (wire) | Seat |
| --- | --- |
| `SELF_RATING` | the employee |
| `REPORTING_MANAGER_RATING` | the reporting manager (under `ADMIN_ONLY`: management, for the leftover KRAs) |
| `ACCOUNT_HR_RATING` | HR |
| `FINANCE_RATING` | Accounts |
| `MANAGEMENT_REVIEW` | management sign-off |

`INCENTIVE_PAYOUT` is not a rating and is not gated, but note that mark-paid needs
the review at `MANAGEMENT_REVIEW` or later, which in practice means management
signed off (Save & Lock) while its window was open. A month management missed
needs a super-admin reopen of Management review before it can be paid.

## 2. The rule — one resolver, used for enforcement AND display

Month `M = (year, month)` is rated during the following month `N`.
All instants are **IST (UTC+05:30, no DST)**, the timezone the reminder job uses.

```
opensAt    = N-01 00:00:00.000 IST            -- the month has ENDED
deadlineAt = N-D  23:59:59.999 IST            -- D = deadlineDayFor(stage, flow),
                                                 clamped to N's length
```

`deadlineDayFor(stage, flow)` = `notifications/config.js → deadlineDayForStage`
(published 10 / 12 / 12 / 13 / 15 for SELF / ACCOUNT_HR / FINANCE / RM /
MANAGEMENT, env overridable), except that under `ADMIN_ONLY`
`REPORTING_MANAGER_RATING` uses the `MANAGEMENT_REVIEW` day — that seat IS
management, whose own column stays open to the 15th. A configured day that is not
an integer in 1..31 falls back to the published day (logged). Env changes are not
audited.

### Rework (derived from stage records, never from the cursor)

The cursor (`current_stage`) is moved by every save, so it cannot carry state.
With `rec[S]` = the review's stage record for S (one row per review and stage):

```
selfReturned = rec[RM].returned = true
               AND (rec[SELF] absent OR rec[SELF].submitted_at < rec[RM].submitted_at)
               AND current_stage <> 'COMPLETED'
rmReworkDue  = rec[RM].returned = true
               AND rec[SELF].submitted_at > rec[RM].submitted_at
               AND current_stage <> 'COMPLETED'
```

`selfReturned` = the manager sent it back and the employee has not resubmitted.
It ends when the employee resubmits. `rmReworkDue` = the employee resubmitted and
the manager has not approved since. It ends when the manager approves, which
writes `returned = false`.

### Precedence, first match wins

| # | Condition | `source` | `closed` | `closesAt` |
| --- | --- | --- | --- | --- |
| 1 | override `CLOSED` | `CLOSED` | `true` | `null` |
| 2 | SELF and `selfReturned`, or RM and `rmReworkDue` | `RETURNED` | `false` | `null` (no end) |
| 3 | override `OPEN`, `open_until` null | `OPENED` | `false` | `null` (no end) |
| 4 | override `OPEN`, `open_until > deadlineAt` | `OPENED` | `false` | `open_until` |
| 5 | otherwise (incl. an `OPEN` whose `open_until <= deadlineAt`) | `DEADLINE` | `false` | `deadlineAt` |

```
isOpen(w, now) = !w.closed && now >= w.opensAt && (w.closesAt == null || now <= w.closesAt)
```

Rows 3–5 never look at `now`: an expired reopen is still `OPENED`, just closed.
**Status copy is always built from `isOpen` and the instants, never from `source`
alone.**

### Invariants

- **Nothing opens before the month has ended** (`opensAt` is always N-01 IST).
  An OPEN override on a running month is accepted (an extension planned ahead) but
  only takes effect once the month ends.
- **No role bypasses a closed window** — not HR_ADMIN, not SUPER_ADMIN.
- Who may rate (relationship / role), COMPLETED and the management lock are
  unchanged and still apply.
- **Self-first lasts only while SELF can still arrive.** A reviewer or management
  cell waits for that KRA's self score only while the month's SELF window is open
  (`isOpen(selfWindow, now)`). Once SELF is closed, a KRA with no self score is
  rated without it: the client lifts self-first for that row and the server's
  manager ceiling skips rows with no self score. Without this, a KRA left blank by
  the 10th could never be rated and would drop out of the weighted total.
- The client-only reach-backs (blank self-rating backfill for any ended month,
  management sign-off of any ended month, `RatingReopen`) do not exist when the
  server sends windows. e8715339's server-side blank-SELF exception to the
  COMPLETED lock stays, but runs AFTER the window check.

## 3. Server (vistar_CRM, `src/modules/kra`)

Branch `feat/kra-rating-access`, based on current `origin/main` (which already
contains e8715339; `release` is an ancestor of `main`, so promotion is the normal
fast-forward).

### 3.1 Tables

`migrations/169_kra_rating_access.sql` (authoritative, applied on deploy; no
`BEGIN/COMMIT` — the runner wraps each file; additive and idempotent) plus
`169_kra_rating_access_down.sql` (`DROP TABLE IF EXISTS` both tables). The same
DDL, without the seed, as a lazy `ensureRatingAccessTables()` guard in code.

```sql
CREATE TABLE IF NOT EXISTS kra.rating_access_overrides (
  id              TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES kra.organizations(id) ON DELETE CASCADE ON UPDATE CASCADE,
  stage           TEXT NOT NULL,
  year            INT  NOT NULL,
  month           INT  NOT NULL,
  mode            TEXT NOT NULL,
  open_until      TIMESTAMPTZ NULL,
  reason          TEXT NULL,
  created_by      TEXT NULL REFERENCES kra.employees(id) ON DELETE SET NULL,
  updated_by      TEXT NULL REFERENCES kra.employees(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT rating_access_overrides_stage_chk CHECK (stage IN ('SELF_RATING','REPORTING_MANAGER_RATING','ACCOUNT_HR_RATING','FINANCE_RATING','MANAGEMENT_REVIEW')),
  CONSTRAINT rating_access_overrides_month_chk CHECK (month BETWEEN 1 AND 12),
  CONSTRAINT rating_access_overrides_mode_chk  CHECK (mode IN ('OPEN','CLOSED')),
  CONSTRAINT rating_access_overrides_until_chk CHECK (mode = 'OPEN' OR open_until IS NULL),
  CONSTRAINT rating_access_overrides_uq UNIQUE (organization_id, stage, year, month)
);
CREATE INDEX IF NOT EXISTS rating_access_overrides_org_period_idx
  ON kra.rating_access_overrides (organization_id, year, month);

-- Append-only history, kept INSIDE the tenant. kra.audit_logs has no
-- organisation column and is read per the actor's home org, so it cannot be the
-- affected organisation's record of who opened or closed its months.
CREATE TABLE IF NOT EXISTS kra.rating_access_events (
  id              TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES kra.organizations(id) ON DELETE CASCADE ON UPDATE CASCADE,
  stage           TEXT NOT NULL,
  year            INT  NOT NULL,
  month           INT  NOT NULL,
  action          TEXT NOT NULL,      -- 'SET' | 'CLEARED'
  mode            TEXT NULL,          -- the mode set; null for CLEARED
  open_until      TIMESTAMPTZ NULL,
  reason          TEXT NULL,
  actor_id        TEXT NULL REFERENCES kra.employees(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT rating_access_events_action_chk CHECK (action IN ('SET','CLEARED'))
);
CREATE INDEX IF NOT EXISTS rating_access_events_org_idx
  ON kra.rating_access_events (organization_id, created_at DESC);
```

Seed (migration only): every organisation × the five stages × 2026-07 and
2026-08, `OPEN`, `open_until = '2026-10-31 23:59:59.999+05:30'::timestamptz`,
reason `Pre-opened at rollout: pending July/August ratings`, ids `md5(...)` of
org/stage/period, `ON CONFLICT DO NOTHING`; plus one `SET` event per seeded row
(actor null) so the history explains the pre-open.

### 3.2 Module layout

New `dist/features/rating-access/`:

- `rating-access.rules.js` — pure: `RATING_STAGES`, `windowBounds`,
  `resolveWindow({stage, year, month, deadlineDay, override, returned})` (for RM
  `returned` means `rmReworkDue`), `isOpen`, `toWire`, `parsePeriod`, `istEndOfDay`,
  `formatIstDate`, `stageLabel(stage, flow)`, `closedMessage(window, now, flow)`.
- `rating-access.repository.js` — raw SQL via `database_1.prisma` (positional
  params; **bind `open_until` as a JS `Date` or with `$n::timestamptz`** — Prisma
  binds JS strings as text and Postgres will not assign text to timestamptz).
  `overridesForPeriod` returns rows, or **`null` on a read failure** (distinct from
  "none"). No cache: a change applies on the next request everywhere.
- `rating-access.service.js` — `deadlineDayFor`, `reworkState(header, records)`,
  `windowsForReview`, `assertRatingOpen`, guards for send-backs, the manager-ceiling
  relaxation helper, admin operations, and a clock seam for tests.
- `rating-access.routes.js` — pinned shape:
  `const ratingAccessRouter = Router({ mergeParams: true })`,
  `ratingAccessRouter.use(authenticate, requireRoles('SUPER_ADMIN'))`, routes in
  the order `/overrides`, `/history`, `/:period`, `/:period/:stage`, mounted with
  `app.use(\`${API_PREFIX}/organizations/:organizationId/rating-access\`, ratingAccessRouter)`.

### 3.3 Enforcement — `monthly-reviews.service.js`

`assertRatingOpen` throws when `!isOpen(window, now)`:

```js
new AppError(message, 403, 'AUTHZ_RATING_CLOSED', { ratingAccess: { stage, period, source, opensAt, closesAt } })
```

- **403, not 409** (the client reads 409 as "moved on"). `details` holds ONE
  nested object (a flat string replaces the message in `combinedMessage`).
- If the override read fails (`null`), writes are refused with
  `AppError('Couldn't check whether rating is open. Please try again.', 503, 'SRV_RATING_ACCESS_UNAVAILABLE')`
  — never resolved as "no override", which would reopen force-closed stages and
  close the July/August pre-open.
- Messages (shown verbatim by the app): `August 2026 can't be rated until the
  month ends.` / `Self-rating for August 2026 has been closed by the
  administrator.` / `Self-rating for August 2026 closed on 10 Sep 2026.` Stage
  labels: Self-rating, Reporting-manager rating (ADMIN_ONLY: Management rating),
  HR rating, Accounts rating, Management review.

| Endpoint | Rule (after org scoping and the who-gates, before any write / proof upload / ceiling check) |
| --- | --- |
| `POST /:id/save-scores` | `assertRatingOpen(body.stage)`, BEFORE e8715339's COMPLETED block. While `selfReturned` holds, the auto-advance of the cursor is skipped (otherwise the next save moves the cursor off SELF and the employee cannot resubmit). The manager ceiling skips rows with no self score when the SELF window is closed. |
| `POST /:id/submit-stage` (rating stages) | `assertRatingOpen(body.stage)`. `SELF_RATING` submit is accepted while `selfReturned` holds even if the cursor moved. RM send-back (`approved === false`) refused when SELF is force-CLOSED. MANAGEMENT send-back refused unless the RM window is open. `MANAGEMENT_REVIEW` submit (rowScores or approved:false) refused with 409 when `management_locked_at` is set — the same lock save-scores already enforces. |
| `POST /:id/lock-management`, `/:id/unlock-management` | `assertRatingOpen('MANAGEMENT_REVIEW')` |
| `POST /:id/mark-paid` | none |

The legacy cycle pipeline (`/reviews/:id/scores`, `/employee/reviews/:id/self-rate`,
`/manager/reviews/:id/manager-rate`) is out of scope.

### 3.4 Read contract for every role — embedded on the review

`toFull` (GET `/reviews/monthly/:id` and every save/submit response) adds:

```json
"serverNow": "2026-10-02T06:00:00.000Z",
"ratingAccess": {
  "SELF_RATING":              { "source": "OPENED", "closed": false, "opensAt": "2026-08-31T18:30:00.000Z", "closesAt": "2026-10-31T18:29:59.999Z", "deadlineAt": "2026-09-10T18:29:59.999Z" },
  "REPORTING_MANAGER_RATING": { "...": "..." },
  "ACCOUNT_HR_RATING":        { "...": "..." },
  "FINANCE_RATING":           { "...": "..." },
  "MANAGEMENT_REVIEW":        { "...": "..." }
}
```

Always all five stages, resolved for the review's own organisation, month and
rework state. If the override read fails, `ratingAccess` is **omitted** (the app
then keeps its old rules) and the failure is logged. `serverNow` lets the app
correct for a device clock that is off.

### 3.5 Super-admin API — `requireRoles('SUPER_ADMIN')`, organisation in the PATH

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| GET | `/organizations/:organizationId/rating-access/overrides` | — | bare list of current overrides, newest `updatedAt` first |
| GET | `/organizations/:organizationId/rating-access/history` | — | bare list of events, newest first (max 200) |
| GET | `/organizations/:organizationId/rating-access/:period` | — | month view |
| PUT | `/organizations/:organizationId/rating-access/:period/:stage` | `{ mode, openUntilDate?, reason? }` | month view |
| DELETE | `/organizations/:organizationId/rating-access/:period/:stage` | — | month view (idempotent) |

`:period` is `YYYY-MM`. `mode` is `OPEN` or `CLOSED`. `openUntilDate` is
`YYYY-MM-DD` (OPEN only), meaning end of that day IST; omitted or `null` means no
end. `reason` optional, trimmed, max 500, empty → null. Validation (400 `VAL_001`):
bad period / stage / mode; `openUntilDate` with `CLOSED`; an end of day already
past; an `openUntilDate` whose end of day is on or before the stage's deadline
(`"…already open until <date> by its deadline — pick a later date or leave it on
the deadline"`). Unknown organisation → 404 with code `RES_ORG_NOT_FOUND` (so the
app can tell it from a server that lacks the routes, which answers 404 `RES_001`).

Month view:

```json
{
  "organizationId": "org-1", "organizationName": "Vistar Logitek", "reviewFlow": "STANDARD",
  "period": "2026-08", "year": 2026, "month": 8, "serverNow": "…",
  "stages": [
    { "stage": "SELF_RATING",
      "window":   { "source": "OPENED", "closed": false, "opensAt": "…", "closesAt": "…", "deadlineAt": "…" },
      "override": { "id": "…", "stage": "SELF_RATING", "period": "2026-08", "mode": "OPEN", "openUntil": "…",
                    "reason": "…", "updatedAt": "…", "updatedById": "…", "updatedByName": "…" } }
  ]
}
```

`stages` always lists the five stages in pipeline order; the window here is
org-level (no per-review rework state); `override` is null when none. An event
item: `{ id, stage, period, action, mode, openUntil, reason, actorId, actorName, createdAt }`.

Every PUT / DELETE appends a `kra.rating_access_events` row in the same
transaction, and writes `writeAudit({ actorId: user.id, action:
'RATING_ACCESS.SET' | 'RATING_ACCESS.CLEARED', entityType: 'RatingAccessOverride',
entityId: '<orgId>:<stage>:<period>', oldValues, newValues })` with the
organisation id but WITHOUT the free-text reason (that feed is read by HR admins of
the super admin's own organisation).

## 4. Client (krafrontend)

### 4.1 Model

- `RatingWindow { source, closed, opensAt, closesAt?, deadlineAt?, clockSkew }`;
  `isOpenAt(now)` evaluates `now + clockSkew` against the server instants;
  `RatingWindow.parseMap(raw, {serverNow, receivedAt})` keys by exact wire name.
- `MonthlyReview.ratingWindows` is non-null exactly when the payload HAS a
  `ratingAccess` map. `windowFor(stage)` returns the stage's window; **a stage
  missing from a present map is treated as closed**, never as "use the old rule".
  `clockSkew = serverNow − receivedAt` when `serverNow` is present.
- `copyWith` carries the windows.
- `selfRatingReturned` uses the record-based `selfReturned` definition (§2), on the
  legacy path too.
- Display of any window instant is in IST (`instant.toUtc() + 5h30m`, then
  `d MMM yyyy`), never `toLocal()`.

### 4.2 Gates — server windows when present, legacy rule when absent

`ratingWindows == null` (older backend): every gate keeps today's behaviour,
except that the client's `RatingReopen` grant mirrors the server seed — July and
August 2026 are open like the review month at EVERY stage, rate and edit
(ratings already given, reasons and attachments included), ending at
2026-10-31T18:29:59.999Z, the seed's end. When present, the window decides "when" and the reach-backs are not
consulted:

- `isCellOpenForEntry(..., window, selfWindow)`: `window.isOpenAt(now)` (no
  device-calendar `isRatableOn` check — `opensAt` already encodes it in IST); then
  for non-self stages under a flow with self-rating, the self score is required
  only while `selfWindow` is open.
- `canEditSelfRating(r, scope, now)`: SELF window open, then flow + identity.
- `managerCanSubmitReview`: RM window open; a returned RM record counts as "not
  submitted" (`record == null || record.returned`).
- Self submit: a month whose rework is due (`selfRatingReturned`) can be
  resubmitted despite its existing SELF record.
- `_returnableReviews`: RM window open, SELF not force-closed.
- Management Save & Lock / Reopen: actionable month = MANAGEMENT window open
  (legacy: as today). Lock targets = actionable and not locked; Reopen targets =
  actionable and locked; offer each when it has targets; hide the bar when no
  month is actionable; confirm copy names only the targets.
- Reason & proof tiles: the reviewer tile requires its stage window open.
- `_editCell`: the RM ceiling applies only when the KRA has a self score; with
  SELF closed and no self score the manager rates uncapped. `_editCell` and
  `_openJustification` re-check the window before opening an editor.
- `_reviewCell`: closed window → closed dash; open window waiting for a self score
  that can still arrive → Self tag; SELF closed and no self score → the reviewer
  can rate (if their window is open).
- Sheet copy when windows are present: the "you can rate…" scope line requires the
  stage's window open in at least one month in view; the due month(s) are the
  months whose SELF window is open and still have an unrated KRA; the deadline
  copy comes from the windows ("closes 10 Oct", "open until 31 Oct"); the header
  highlights the months whose window is open for the viewer's stage; the reopened
  notice lists months reopened by the administrator.
- One instant per build: the screen passes its clock into `_Sheet`.

Every write path (`_editCell`, `_openJustification`, `_submitSelfRating`,
`_submitManagerReview`, `_sendBackForRework`, `_lockManagementReview`,
`_reopenManagement`) refreshes the sheet after a failure as well as a success.
The multi-month loops skip-and-collect both 409 (moved on) and
`AUTHZ_RATING_CLOSED`, finish the remaining months, then report what happened.
Every message goes through the sanctioned error text helpers — never `$e`.

### 4.3 Super-admin screen

Route `/hr/organizations/:orgId/rating-access?period=YYYY-MM` (bad or missing
period → the open review month), pushed, outside the HR shell; router guard:
`/hr/organizations` and below are SUPER_ADMIN only (`hasRole(UserRole.superAdmin)`,
as an `AppRoutes` predicate with a test). Entered from each organisation card
(the action row must wrap at 360 px) and an HR-home quick action. Content:
organisation + flow (from the month view, NOT the acting org), month chips, one
card per stage in the org's flow with flow-aware labels mirroring the server's
`stageLabel`, a status line built from instants (open until / closed on / opens on /
reopened until / reopened, no end date / closed by the administrator / reopen
expired), Open until… (date picker; first date = today in IST; the picked y/m/d is
sent as-is, never via `toUtc()`; dates on or before the stage's deadline are
disabled or flagged) / Close now / Use deadline, bulk "Open all stages until…" and
"Use deadline for all" as sequential calls that stop and report on failure (bulk
open skips stages whose own deadline already covers the chosen date), and the
organisation's current overrides including expired ones (newest first). The
server's full change history (`GET …/history`, every SET and CLEARED with its
actor) is not yet shown on this screen — see §6. Loading, error (+ retry; 404
`RES_001` = not on the server yet, `RES_ORG_NOT_FOUND` = organisation not found),
empty history, content. Mode choice with `SegmentedButton` (no deprecated
`RadioListTile.groupValue`). After every change, invalidate the review caches so a
sheet underneath refreshes.

## 5. Rollout

1. **Pre-deploy check** (docs/rating_access_predeploy.sql): per organisation,
   reviews before 2026-07 not yet signed off / locked / paid, and — if production
   lands after 10 Oct — September stages whose deadline has passed. Decide which
   the super admin reopens on day one.
2. Ship the app first (safe on the old backend: legacy rules, and the legacy
   July/August grant ends with the seed). Publish the Android build the same day.
3. Backend PR to `vistar_CRM` main → UAT auto-deploys; migration 169 applies.
   Verify on UAT. Then fast-forward `release` to `main` and deploy production.
4. Announce the 10 / 12 / 13 / 15 IST deadlines before enforcement begins.

Old app builds against the new backend: cells stay offered after the deadline and
the save is refused with the server's message; a refused send-back shows a raw
error string (fixed in this build).

## 6. Out of scope (follow-ups)

- The super-admin screen lists current overrides; the full change history
  (`GET …/history`, kra.rating_access_events) is served and tested but has no
  screen yet. Until it does, query it directly or via the API.
- The multi-month loops (self submit, manager submit, send-back, lock, reopen)
  refresh the sheet on a "closed" refusal and show the server's message, but
  stop at the first refused month rather than skipping it and finishing the
  rest. The app only offers months whose windows are open, so this only bites
  when a window closes while the sheet is open.
- Reminder emails ignore overrides.
- Dashboards' "needs your action" and the employee home banner ignore windows.
- The legacy cycle pipeline and its screens.
- Ratings entered while a stage is open are not attributed to their author
  (`monthly_row_scores` has no actor column); the override history and audit entry
  are the mitigation for super-admin separation of duties.
- A SELF force-close strands reviews whose rework is in progress (CLOSED wins);
  the month view does not count them yet.
- KRA backend tests are not in CI (a `kra:test` npm script is added; wiring it into
  CI is the backend team's call).
