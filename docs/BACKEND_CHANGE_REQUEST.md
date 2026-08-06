# Backend Change Request — Access Control

Paste-ready brief for whoever owns `vistar-crm` (`/api/v1/kra`). The Flutter
client is already built for everything below and ships the new behaviour behind
two disabled flags, so **no client release is needed** — we flip a config flag
once each change lands.

Design rationale: [ACCESS_CONTROL_DESIGN.md](ACCESS_CONTROL_DESIGN.md).
Prior audit: [BACKEND_RBAC_FINDINGS.md](BACKEND_RBAC_FINDINGS.md).

---

## The prompt

> You are working on the Vistar KRA backend (`/api/v1/kra`), which serves a
> Flutter client for monthly KRA reviews and incentive payouts. I need four
> changes to unblock the app's access-control model. Do not change review
> scoring or incentive calculation — those are correct and the client depends on
> the current numbers.
>
> **Change 1 — extend the role enum (blocking, highest priority).**
>
> `POST /employees` and `PATCH /employees/:id` validate `role` against:
>
> ```
> EMPLOYEE | MANAGER | OPS_EXCELLENCE | OPS | HR | HR_ADMIN | FINANCE
>         | BD_MANAGER | WAREHOUSE_MGR
> ```
>
> Add two values: **`MANAGEMENT`** and **`SUPER_ADMIN`**.
>
> `/auth/login` and `/auth/me` must return these same values in `role` for users
> who hold them. Persist them in whatever column `role` already uses; no new
> table needed.
>
> Why: our founder/CEO tier performs the Management review — stage 3, the
> approval/override that is the final word on a score and therefore on the
> incentive paid. Right now the only assignable role above `HR` is `HR_ADMIN`,
> so HR ends up approving its own stage-2 input, and we cannot separate the two.
> `SUPER_ADMIN` is needed because whoever can edit roles can grant themselves
> any role — that authority must sit above `HR_ADMIN`, not inside it.
>
> Reproduction of the current failure:
>
> ```
> PATCH /api/v1/kra/employees/b20cd948-4d02-4727-b115-a2f0cc74e424
> { "role": "ADMIN", "position": "Founder & CEO" }
>
> 400 { "success": false, "error": { "message": "Validation failed",
>       "code": "VAL_001", "details": { "role": ["Invalid option: expected one
>       of \"EMPLOYEE\"|\"MANAGER\"|…"] } } }
> ```
>
> **Change 2 — scope `GET /manager/team` by reporting line, not by role.**
>
> It must return only employees whose `managerId` is the calling user, for
> **every** role — including `HR_ADMIN`, `FINANCE`, `MANAGEMENT` and
> `SUPER_ADMIN`. A senior user with no direct reports gets an empty list (or the
> existing `NO_DIRECT_REPORTS` 403, which the client already handles as a normal
> empty state).
>
> Also add `managerId` to each member object:
>
> ```json
> { "id": "...", "employeeCode": "VLPL1463", "name": "...",
>   "managerId": "...", "currentReview": { "...": "..." } }
> ```
>
> Why: "My Team" means *the people who report to me*. It must return the same
> rows for an HR admin who manages three people as for a plain manager who
> manages three. Today the endpoint returns 200 for the HR tier and appears to
> return the whole org, so an HR-admin manager sees an org-wide list where their
> own team should be. The client cannot correct this — the member objects carry
> no `managerId` to filter on.
>
> **Change 3 — always send `hasReports`.**
>
> Include `hasReports: true|false` in the user object on `/auth/login` and
> `/auth/me`: true when at least one active employee has this user as their
> `managerId`.
>
> Why: it decides whether the My Team workspace is offered. It defaults to
> `false` client-side, so an omitted flag silently hides My Team from real
> managers.
>
> **Change 4 — accept a `roles` array (optional, do last).**
>
> Accept and return `roles: string[]` alongside the scalar `role` on the
> employees endpoints and in the auth payload:
>
> ```json
> { "role": "HR_ADMIN", "roles": ["HR_ADMIN", "FINANCE"] }
> ```
>
> `role` stays the primary (used for display and for deciding which employees a
> user can see); `roles` is the full grant set. Validate every element against
> the same enum as `role`, and keep `role` present and consistent (it should be
> one of `roles`) so older clients keep working.
>
> Why: one post can carry several responsibilities — a commercial/HR-admin who
> also rates the Accounts seat. This is genuinely optional; we have a workaround
> that covers today's people, so land changes 1–3 first.
>
> **Constraints.**
>
> - Keep the response envelope exactly as-is: `{ success, data, meta? }` /
>   `{ success: false, error: { code, message, details? } }`.
> - Don't rename existing fields or change decimal-as-string / ISO-8601 date
>   formats — the client parses both tolerantly and I don't want churn.
> - Don't touch review scoring, stage transitions, or incentive computation.
> - `role` must stay required and single-valued for backward compatibility.
>
> **Acceptance criteria.**
>
> 1. `PATCH /employees/:id { "role": "MANAGEMENT" }` → 200, and `/auth/me` for
>    that user returns `"role": "MANAGEMENT"`.
> 2. Same for `SUPER_ADMIN`.
> 3. An unchanged role value still saves exactly as before (no regression on the
>    other nine values).
> 4. `GET /manager/team` as an `HR_ADMIN` who manages 2 people returns exactly
>    those 2, each with a `managerId` equal to that user's id.
> 5. `GET /manager/team` as an `HR_ADMIN` who manages nobody returns an empty
>    list or `NO_DIRECT_REPORTS`, never the org.
> 6. `/auth/login` includes `hasReports`, true for a user with reports.
> 7. (If change 4 is done) `PATCH /employees/:id { "role": "HR_ADMIN",
>    "roles": ["HR_ADMIN","FINANCE"] }` → 200 and both come back on read.
> 8. An invalid role still returns `VAL_001` with the full accepted list.

---

## Rollout, once each change lands

Order matters — step 2 before step 3, or management review has no eligible actor.

| # | Step | Who |
|:--:|---|---|
| 1 | Ship backend change 1 | Backend |
| 2 | Assign roles: Sivadasan K + Prashant R. Tamhankar → `MANAGEMENT`; Swati Kotkar → `SUPER_ADMIN` | Whoever holds admin access today |
| 3 | Rebuild client with `--dart-define=ROLE_TIERS=true` | Frontend |
| 4 | Ship backend changes 2 + 3 | Backend |
| 5 | Client switches My Team to relationship scoping (small change, needs `managerId`) | Frontend |
| 6 | (Optional) backend change 4, then rebuild with `--dart-define=MULTI_ROLE=true` | Both |

### What flag flipping actually changes

`ROLE_TIERS=true`:

- Management sign-off becomes exclusive to `MANAGEMENT` (HR admins lose it, which
  is the point — Sagar keeps HR + Accounts only).
- Management job titles (Founder / CEO / Director / Chairman) derive `MANAGEMENT`
  instead of `HR_ADMIN`.
- `MANAGEMENT` and `SUPER_ADMIN` become selectable in the employee form.
- Granting roles narrows to the super admin alone.

`MULTI_ROLE=true`:

- The employee form persists every selected role as `roles`, not just the first.
- The "only the first role will be saved" warning disappears.

Both default to **false** = today's behaviour, and the test suite passes in both
states, so the flip is verifiable before it ships.

---

## Why the client waits on flags instead of just doing it

Gating management review on `MANAGEMENT` today would leave stage 3 with **no
eligible actor**, because nobody can be assigned that role — reviews would stall
before payout. Same for `SUPER_ADMIN`: restricting role-granting to a tier nobody
holds would leave no one able to assign roles at all, including the assignments
needed to bootstrap that tier. And sending an unrecognised `roles` field risks a
400 on *every* employee save, single-role ones included.

So each change is written, tested, and dormant until the server can back it.
