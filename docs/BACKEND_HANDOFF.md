# Backend Handoff — KRA module

Consolidated brief for the backend team covering every gap found while wiring the
Flutter app to the live API (`https://vistar-crm.onrender.com/api/v1/kra`), plus the
deploy-day checklist for the monthly-review cutover.

**Status at time of writing (8 Jul 2026):**

| # | Item | Status |
|---|------|--------|
| P1 | Employee password create / update / reset | ❌ Not started — interim DB script exists (`scripts/set-employee-passwords.js` in the CRM repo) |
| P2 | `passwordHash` / `samlNameId` leak on `GET /employees` | ❌ Not started |
| P3 | KRA template delete / edit + soft-delete name reuse | ❌ Not started — blocks re-importing "BD Manager KRA" / "Regional Manager KRA" |
| P4 | Assignment `cycleId` requirement | ✅ Worked around client-side (app auto-resolves the active cycle) — FYI only |
| P5 | Monthly-review API | 🟡 **Built** on branch `feat/kra-monthly-reviews` (vistar_CRM repo, migration 069) — **not merged / not deployed**; live still 404s |

The Flutter client is already prepared on branch `chirag`:
- `ApiMonthlyReviewRepository` implements the Priority 5 contract exactly.
- The employee form already sends `password` + `forcePasswordReset` on create **and** edit (Priority 1 lands → works with zero client changes).
- The swap is gated by `monthlyBackendEnabledProvider` in
  `lib/features/reviews/presentation/providers/monthly_review_providers.dart` (currently `false`).

---

## The prompt (self-contained — hand to the backend owner as-is)

```
CONTEXT
You own the KRA module of the Vistar CRM backend: Node/Express + Prisma +
PostgreSQL (multi-schema — KRA tables live in the `kra` Postgres schema).
Auth uses bcryptjs + JWT. The repo also hosts other apps (dpl, audit, lr,
cep). SCOPE: change ONLY the KRA module + its Prisma models/migrations.
Do not touch other modules. Migrations are hand-written schema-qualified
SQL files in /migrations, applied via per-item scripts in /scripts —
follow that convention.

════════════════════════════════════════════════════════════════════════
PRIORITY 1 — Employees can't get a usable password (blocks all logins)
════════════════════════════════════════════════════════════════════════
Symptoms: HR-created employees can never log in — /auth/login returns
AUTH_001 "Invalid credentials" for every one of them.

Root cause (verified in the compiled service):
  • employees.service.js `create()` IGNORES any password in the request and
    hashes a RANDOM token instead:
        const initial = generateSecureToken().slice(0, 16);
        passwordHash = await bcrypt.hash(initial, SALT_ROUNDS);
    So nobody ever knows the password.
  • CreateEmployeeSchema has NO `password` field, and
    UpdateEmployeeSchema = CreateEmployeeSchema.partial().omit({employeeCode}),
    so `password` is silently stripped on BOTH create and update. The update
    repository never writes `password_hash`.
  • There is NO set/reset-password route. auth.routes.js exposes only
    /login, /logout, /me, /refresh. A ResetPasswordSchema ({token, password})
    exists in auth.types.js but no route/handler is mounted for it.

Do this:
  1. Add `password: z.string().min(8).optional()` to CreateEmployeeSchema
     (and therefore UpdateEmployeeSchema). On create, if `password` is
     provided, hash THAT (not a random token); keep the random-token
     fallback only when it's omitted. On update, if `password` is provided,
     hash it and write `password_hash`; also allow `forcePasswordReset` to
     be set. (The Flutter employee form already sends `password` +
     `forcePasswordReset` on create and edit — no client change needed once
     this lands.)
  2. Add an admin-only endpoint to set a password directly, e.g.
     POST /employees/:id/set-password  { password }  (guard ADMIN/HR_ADMIN),
     for bulk/reset use.
  3. Mount the real forgot/reset-password flow (the ResetPasswordSchema is
     already defined): POST /auth/forgot-password {email} → issue a token,
     POST /auth/reset-password {token, password} → verify + set hash.
     Ensure the token is delivered securely (email), not returned in the body.

  (Interim tooling already exists: scripts/set-employee-passwords.js writes a
   bcrypt hash straight to kra.employees.password_hash — reference for the
   column/behaviour, not a replacement for the API fix.)

════════════════════════════════════════════════════════════════════════
PRIORITY 2 — GET /employees leaks password hashes
════════════════════════════════════════════════════════════════════════
Every record in GET /api/v1/kra/employees (HR-authenticated) includes the
bcrypt `passwordHash` and `samlNameId` in plaintext over the wire, e.g.
  "passwordHash":"$2b$10$V.0FuGQUkKlf…","samlNameId":null
Fix: map the employee entity to a response DTO that whitelists safe fields
(deny-by-default), or Prisma `omit`/`select` these on every read. Audit
sibling endpoints that embed the employee object (nested manager/report/
assignedBy on reviews, assignments, /manager/team) for the same leak.

════════════════════════════════════════════════════════════════════════
PRIORITY 3 — Admins can't delete/edit KRA templates that have been used
════════════════════════════════════════════════════════════════════════
Symptoms:
  • PATCH /kra-templates/:id → 500 (SRV_001) when a template's items are
    referenced by existing review rows: prisma.kraTemplateItem.deleteMany()
    hits a RESTRICT FK: review_rows.template_item_id → kra_template_items.
  • Deleting a template that any review used is blocked
    (reviews.template_id → kra_templates is also RESTRICT).
  • Soft-delete keeps the NAME reserved: after deleting a template you get
    409 RES_002 "Template already exists" when recreating the same name, and
    the row is invisible to GET /kra-templates (?isActive=false shows nothing
    either). This blocked re-importing "BD Manager KRA" / "Regional Manager
    KRA".

Do this (pick a coherent policy):
  1. Editing a used template must NOT blind deleteMany()+recreate items —
     diff the items: update changed, insert new, delete only items with no
     review_rows referencing them; version/keep referenced ones. No 500.
  2. Deleting a used template: EITHER soft-delete/archive (recommended:
     add is_archived/deleted_at, exclude from list/assignment, keep history,
     ZERO data loss) OR an admin `?force=true` hard cascade (migrate
     reviews.template_id and review_rows.template_item_id to ON DELETE
     CASCADE) — force + admin-guarded, and note it deletes the reviews.
  3. Fix name-uniqueness so a soft-deleted template does NOT block recreating
     the same name (scope the unique check to non-deleted rows, or reactivate
     an archived same-name template on recreate).

════════════════════════════════════════════════════════════════════════
PRIORITY 4 — KRA assignments hard-require a cycleId
════════════════════════════════════════════════════════════════════════
POST /kra-assignments and /kra-assignments/bulk 400 with VAL_001
"cycleId: expected string, received undefined" when no cycle is sent
(kra_assignments.cycle_id is NOT NULL, UNIQUE(employee_id, cycle_id)).
The app now auto-resolves the active review cycle client-side, so this is
FYI — but if the product is moving to monthly reviews, consider making
cycleId optional / introducing a month-scoped assignment model.

════════════════════════════════════════════════════════════════════════
PRIORITY 5 — Build the monthly-review backend (new feature)
════════════════════════════════════════════════════════════════════════
STATUS: implemented on branch feat/kra-monthly-reviews (migration 069,
endpoints below) — needs review, merge, and deploy. The spec is kept here
as the acceptance contract.

The Flutter app has a completed "monthly review" redesign that currently
runs on an in-memory mock because these endpoints aren't deployed
(/reviews/monthly* → 404). Ship them so the app flips from mock to live
with NO client changes. The client contract below IS the spec — match the
JSON exactly (it maps 1:1 to the app's models).

MODEL
Exactly ONE review per (employee, calendar month). Each advances through a
fixed 5-stage pipeline, each stage role-gated with a fixed day-of-month
deadline:

  Stage (wire enum)          Actor role(s)        Deadline
  SELF_RATING                EMPLOYEE             10th
  ACCOUNT_HR_RATING          HR_ADMIN, FINANCE    12th
  REPORTING_MANAGER_RATING   MANAGER              13th
  MANAGEMENT_REVIEW          ADMIN/HR_ADMIN       15th
  INCENTIVE_PAYOUT           FINANCE, HR_ADMIN    20th
  COMPLETED                  —                    —

A stage is actionable only when review.currentStage == that stage AND the
caller's role is in its actor set. Submitting a stage records the actor and
advances currentStage to the next. Rating stages (self, account/HR,
manager) write per-KRA-row scores; MANAGEMENT_REVIEW is approve (advance)
or return (send back to REPORTING_MANAGER_RATING); INCENTIVE_PAYOUT marks
the incentive paid → COMPLETED.

GENERATION
Generate one review per active employee at the start of each month at
SELF_RATING, snapshotting the employee's assigned KRA rows (name, category,
weightagePercent, maxScore, target, trackingMethod, displayOrder) and their
monthlyIncentiveAmount as the incentive ceiling. (Lazy-generate on first
GET for a month if you prefer over a cron.)

WIRE SHAPES (match verbatim)
Stage status enum: PENDING | IN_PROGRESS | SUBMITTED | SKIPPED
Payout status enum: PENDING | PAID | SKIPPED

MonthlyReviewSummary (list rows):
  { "id","employeeId","employeeName","employeeCode","employeeGrade",
    "managerName","year":2026,"month":6,"monthLabel":"June 2026",
    "currentStage":"SELF_RATING","currentStageStatus":"IN_PROGRESS",
    "finalScorePct":0,"incentiveEligibleAmount":8000 }

MonthlyReview (full):
  { "id","employeeId","employeeName","employeeCode","grade",
    "managerId","managerName","period":"2026-06",
    "currentStage":"REPORTING_MANAGER_RATING",
    "stageRecords":{ "SELF_RATING":{"actorId","actorName",
        "submittedAt":ISO,"comment":null}, ... },
    "rows":[ { "id","name","category","weightagePercent":40,"maxScore":10,
        "target","trackingMethod","displayOrder":0,
        "stageScores":{ "SELF_RATING":{"value":8,"remark":null}, ... } } ],
    "incentive":{ "eligibleAmount":8000,"computedScorePct":85,
        "payoutStatus":"PENDING","paidAt":null } }

ENDPOINTS (all return the standard { success, data } envelope; actorId/
actorName come from the JWT — do NOT trust them from the body)
  GET  /reviews/monthly?year=&month=&scopeRole=&scopeEmployeeId=
         &scopeManagerId=&currentStage=            → [MonthlyReviewSummary]
       (scope by the caller: EMPLOYEE→own, MANAGER→direct reports,
        HR_ADMIN/FINANCE/ADMIN→org-wide; currentStage filters payout view)
  GET  /reviews/monthly/:id                        → MonthlyReview (rows+records)
  POST /reviews/monthly/:id/submit-stage
         { "stage":"SELF_RATING",
           "rowScores": { "<rowId>": {"value":8,"remark":"..."} },  // rating stages
           "approved": true|false,                                  // management review
           "comment": "..." }                       → updated MonthlyReview
       (reject if stage != currentStage or role not permitted; approved=false
        returns the review to REPORTING_MANAGER_RATING)
  POST /reviews/monthly/:id/mark-paid               → updated MonthlyReview
       (only valid at INCENTIVE_PAYOUT; sets payout PAID, advances to COMPLETED)

SCHEMA
New `kra` tables (or reuse review*/review_month* with a monthly flag):
monthly_reviews (employee_id, year, month, current_stage, incentive_
eligible/computed/paid_at/payout_status; unique(employee_id,year,month)),
monthly_review_rows (review_id, kra metadata snapshot, display_order),
monthly_row_scores (row_id, stage, value, remark), monthly_stage_records
(review_id, stage, actor_id, submitted_at, comment). All FKs to employees
ON DELETE CASCADE/SET NULL so the employee-purge stays clean.

FLIP THE CLIENT
The app already has ApiMonthlyReviewRepository implemented against exactly
this contract (methods listMonthlyReviews / getReview / submitStage /
markPaid). Once these are live, the only client change is pointing
monthlyReviewRepositoryProvider at the API impl — no model or UI changes.

VERIFY
Generate a month → GET list per role (employee sees 1, manager sees team,
HR sees all) → submit self-rating (scores persist, advances to
ACCOUNT_HR_RATING) → manager rate → management approve → mark-paid →
COMPLETED; management "return" sends it back to the manager. Confirm
deadlines land on 10/12/13/15/20 and role gating rejects wrong-role submits.

CONSTRAINTS
  • KRA module only; don't modify dpl/audit/lr/cep code, schemas, or
    migrations.
  • Preserve the { success, data } / { success, error:{code,message} }
    envelope and existing auth. Keep `kra` schema qualifiers in SQL.
  • Any schema change ships as a numbered /migrations SQL file + apply
    script, matching the existing pattern.
```

---

## Interim DB scripts (in the vistar_CRM repo, `/scripts`)

Written this session; each refuses to run without an explicit `CONFIRM` env var and
touches **only** `kra.*` tables. They are stopgaps until the API fixes above land.

| Script | Guard | Purpose |
|---|---|---|
| `set-employee-passwords.js` | `CONFIRM=SET-EMP-PASSWORDS` | Set every active employee's password (default `Vistar@123`); optional `EMP_CODES` scoping |
| `kra-clear-slate.sql` / `.js` | `CONFIRM=RESET-KRA` | Delete all reviews, scores, payouts, assignments, and templates (dependency-ordered, one transaction) |
| `employees-purge.js` | `CONFIRM=PURGE-EMPLOYEES` | Hard-delete employees by `EMP_CODES`, protecting the seed `@vistar.test` accounts |

One-liner equivalent of the password script (precomputed bcrypt of `Vistar@123`):

```sql
UPDATE kra.employees
SET password_hash = '$2b$10$J1tpbi2HG8FFkOI9oh7N/ue.qeyGW9wzQuXFobjrfY3g1Ly9ugd4m',
    force_password_reset = false,
    auth_method = 'PASSWORD'
WHERE is_active = true;
```

---

## Deploy-day checklist (app cutover to the live monthly backend)

Order matters — data first, then the backend, then the client flip.

1. **DB prep** (whoever has DB access):
   - Run `set-employee-passwords.js` so all employees can log in.
   - Optionally run `kra-clear-slate.js` for the clean slate, then re-import the
     7 KRA templates (parsed data is ready; "BD Manager KRA" and
     "Regional Manager KRA" additionally need the Priority 3 name-reuse fix)
     and re-assign templates to employees.
2. **Backend**: review + merge `feat/kra-monthly-reviews`, deploy to Render,
   confirm `GET /api/v1/kra/reviews/monthly?year=2026&month=7` returns `200`
   with the envelope (today it 404s with `RES_001`).
3. **Client flip** (one line): in
   `lib/features/reviews/presentation/providers/monthly_review_providers.dart`
   change `monthlyBackendEnabledProvider` to `(ref) => true`.
4. **End-to-end verify** per role: employee self-rates → HR/finance rates →
   manager rates → management approves (and "return" path) → mark paid →
   COMPLETED; deadlines show 10/12/13/15/20; wrong-role submits are rejected.
