# SUPER_ADMIN — backend change request

The Flutter client now carries a full `SUPER_ADMIN` tier. **The API does not
honour it yet.** This is the exact server-side work that makes it real.

Backend reference read for this spec:
`D:\Vistar\vistar_CRM\src\modules\kra` (compiled `dist/` only — no TypeScript
sources are present in that checkout, so line references are to the built JS).

---

## 1. Why nothing works today

| Fact | Where | Consequence |
| --- | --- | --- |
| `SUPER_ADMIN` is in the storable role enum | `dist/features/employees/employees.types.js` — `RoleEnum` | A user can be *assigned* the role |
| `SUPER_ADMIN` appears in **zero** route guards | `grep SUPER_ADMIN dist/**/*.routes.js` → no hits | The role unlocks nothing |
| `requireRoles` is a flat exact-match | `dist/middleware/rbac.middleware.js` — `roles.includes(req.user.role)` | No hierarchy, no wildcard, no bypass |
| `'ADMIN'` is **not** in `RoleEnum` | same file as above | `requireRoles('ADMIN', …)` is largely dead |

**Net effect: a `SUPER_ADMIN` is strictly *less* privileged than `HR_ADMIN`.**
Every guarded endpoint requires `HR_ADMIN` or `ADMIN`, and a super admin is
neither, so it gets `403 Role SUPER_ADMIN is not authorized for this action`.

That is why the client work is behind the API, not ahead of a working feature.

---

## 2. Minimum change — make the role real

### 2a. Add `SUPER_ADMIN` to every guard that admits `HR_ADMIN`

`requireRoles` has no hierarchy, so each call site must name the role. Files
under `dist/features/*/`*`.routes.js`:

| Route | Current guard | Should be |
| --- | --- | --- |
| `POST /employees` | `requireRoles('HR_ADMIN')` | `+ 'SUPER_ADMIN'` |
| `PATCH /employees/:id` | `requireRoles('HR_ADMIN')` | `+ 'SUPER_ADMIN'` |
| `DELETE /employees/:id` | `requireRoles('HR_ADMIN')` | `+ 'SUPER_ADMIN'` |
| `POST /employees/:id/set-password` | `requireRoles('ADMIN', 'HR_ADMIN')` | `+ 'SUPER_ADMIN'` |
| everything gated `hrOnly` | `requireRoles('HR_ADMIN', 'ADMIN')` | `+ 'SUPER_ADMIN'` |

Sweep the rest the same way:

```bash
grep -rn "requireRoles(" src/modules/kra/dist/features --include=*.routes.js
```

**Preferred alternative — give `requireRoles` a hierarchy** so this never has to
be repeated for the next tier:

```js
const IMPLIES = { SUPER_ADMIN: ['HR_ADMIN', 'ADMIN', 'MANAGEMENT', 'HR', 'FINANCE'] };
function requireRoles(...roles) {
  return (req, _res, next) => {
    if (!req.user) return next(new UnauthorizedError());
    const held = [req.user.role, ...(IMPLIES[req.user.role] ?? [])];
    if (!roles.some((r) => held.includes(r))) {
      return next(new ForbiddenError(`Role ${req.user.role} is not authorized for this action`));
    }
    next();
  };
}
```

One edit, every route, and it matches what the client already assumes. Note it
also hands `SUPER_ADMIN` the HR and Finance **rating seats** — see §5.

### 2b. Return the role unchanged

`/auth/login` and `/auth/me` must return `"SUPER_ADMIN"` verbatim. The client
maps unknown role strings to `EMPLOYEE` (least privilege), so any renaming or
normalising on the way out silently demotes the super admin to a plain employee.

---

## 3. Organizations — the feature that does not exist

The client cannot create, edit, or assign organizations today because **there is
no API for it**, not because of a permission check.

**What exists:** `model Organization` in `prisma/schema.prisma:88` —
`id`, `name`, `slug`, `logoUrl`, `createdAt`, `updatedAt`, with relations to
`employees`, `projectLocations`, `reviewCycles`, `kraTemplates`,
`kraAssignments`. `organizationId` threads through ~732 places.

**What is missing:** any `organizations` route, controller, or service. The only
references anywhere are a notification job aggregating org IDs that already have
reviews (`notifications/queries.js:279` — `organizationsWithReviews`).

### 3a. The architectural blocker

`organizationId` is **signed into the JWT** from the user's own employee record:

```js
// dist/features/auth/auth.service.js:86
const accessToken = await new SignJWT({ email, role, organizationId })
```

Every repository then scopes queries by that claim. So a client can never
*choose* which organization it is acting on — and "assign a user to a new
organization" is not merely ungated, it is unrepresentable in the current model.

Making a super admin genuinely org-wide requires one of:

1. **Org-scoped requests** — accept an explicit `organizationId` (header or
   path prefix) and honour it *only* for `SUPER_ADMIN`, defaulting to the JWT
   claim for everyone else. Least invasive; every repository call must take the
   resolved value rather than reading the claim directly.
2. **Org switching** — a `POST /auth/switch-organization` that re-issues the
   token pair with a different `organizationId`, permitted only for
   `SUPER_ADMIN`. Simpler to audit; the client holds one active org at a time.

Option 2 fits the existing code far better: `issueTokenPair` already takes
`organizationId` as a parameter, so it is a new guarded route plus a membership
check, not a rewrite of every query.

### 3b. Endpoints to add

```
GET    /organizations              list          SUPER_ADMIN
POST   /organizations              create        SUPER_ADMIN   { name, slug, logoUrl? }
GET    /organizations/:id          read          SUPER_ADMIN
PATCH  /organizations/:id          update        SUPER_ADMIN   { name?, slug?, logoUrl? }
DELETE /organizations/:id          soft-delete   SUPER_ADMIN
POST   /auth/switch-organization   re-issue JWT  SUPER_ADMIN   { organizationId }
```

Notes for whoever builds this:

- `slug` is `@unique` — return a typed conflict (`409`), not a raw Prisma error,
  so the client can show "that slug is taken" against the field.
- **Do not hard-delete.** `Organization` is the parent of employees, locations,
  cycles, templates and assignments; a cascade would erase review history.
  Add `deletedAt`/`isActive` and exclude from listings.
- The envelope must match the rest of the API — `{ success, data, meta? }` —
  or `unwrapObject` / `unwrapList` on the client will reject it.
- Every mutation should write an audit-log entry; `audit-log` already carries
  `organizationId`.

---

## 4. Rollout order — this sequence matters

There is a **bootstrap trap**. `FeatureFlags.roleTiers` makes role-granting
super-admin-only; turning it on before anyone holds `SUPER_ADMIN` leaves *nobody*
able to grant roles, and also takes management review offline (`HR_ADMIN` drops
out of the `managementReview` seat).

1. **Backend:** add `SUPER_ADMIN` to the guards (§2a) and confirm `/auth/me`
   returns it verbatim (§2b).
2. **Data:** while `roleTiers` is still off, have an existing `HR_ADMIN` assign
   `SUPER_ADMIN` to the intended user(s), and `MANAGEMENT` to the management
   tier. The employee form only offers those two values once the flag is on, so
   do it via the API or directly in the database.
3. **Verify:** sign in as that user and confirm the HR console, org-wide review
   roster, and management sign-off all load without a 403.
4. **Only then** deploy with `--dart-define=ROLE_TIERS=true`.
5. **Later, independently:** organizations (§3), then the client console for it.

---

## 5. Two things worth deciding, not just building

**Separation of duties.** The client now puts `SUPER_ADMIN` on *every*
org-level stage: the HR rating seat, the Finance rating seat, the management
sign-off, and the incentive payout. The codebase deliberately kept those apart —
`ReviewStage.managementReview` carries the comment that it is "deliberately NOT
the same seat as the HR rater: HR would otherwise approve its own input." A
super admin can now rate a KRA *and* approve its own rating *and* release the
payout. That is what "give him all the access" asks for, and it is a legitimate
break-glass tier — but it is a real control weakening, and if these accounts are
meant for day-to-day use rather than emergencies, consider excluding
`SUPER_ADMIN` from the two *rating* seats while keeping the administrative ones.

**BLOCKER for step 4 — the Designation dropdown is an ungated role grant.**
`_canGrantRoles` (`employee_form_screen.dart:82-88`) hides only the *Access
roles* field. The **Designation** dropdown next to it (`:633-642`) has no gate at
all, and `role` is derived from it unconditionally (`:331-334`) and PATCHed
whenever it changes. `_roleFromDesignation` (`:167-187`) maps
`Founder & CEO` / `Director` / `Chairman` to **`HR_ADMIN`** today, and to
**`MANAGEMENT`** once `roleTiers` is on.

So anyone who can edit an employee can grant the top tier by picking a job
title, bypassing the gate whose stated purpose is that "handing out roles —
including their own — is a privilege-escalation path". It is *latent* today
(HR admins already hold the Access-roles field while `roleTiers` is off) and
**activates precisely when `ROLE_TIERS=true`** — the flag meant to close that
path. Fix this before step 4, or flipping the flag will look like it locked
role-granting down while leaving the back door open.

Suggested fix: gate the derived `role` rather than the widget — when
`!_canGrantRoles`, send the designation but keep `_original.role`, so a title
change never moves someone's access.

**Privilege escalation is now concentrated, not removed.** `isSuperAdmin` is the
only thing gating the role picker. Once `roleTiers` is on, a super admin can
grant `SUPER_ADMIN` to anyone, including themselves — by design, but it means
that one compromised account is unrecoverable without database access. Audit
logging on role changes is the mitigation, and it should be in place before
step 4 above.

---

## 6. What the client already does

No further Flutter work is required for §2; it is wired and tested.

| Change | File |
| --- | --- |
| `superAdmin` is its own `UserRole`; `'SUPER_ADMIN'` maps to it | `lib/features/auth/data/models/user.dart` |
| `isSuperAdmin` covers `superAdmin` + legacy `admin` | same |
| `toApiString()` spelled out per case — it was `name.toUpperCase()`, which sent `HRADMIN` / `BDMANAGER` / `WAREHOUSEMGR` | same |
| HR console + manager workspace + reviews area admit it | `lib/core/router/app_router.dart` |
| Holds all four org-level pipeline stages | `lib/features/reviews/data/models/review_stage.dart` |
| Org-wide review roster | `lib/features/reviews/presentation/providers/monthly_review_providers.dart` |
| Management sign-off / lock / reopen | `lib/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart` |
| 18 assertions incl. wire round-trip for every role | `test/features/auth/super_admin_access_test.dart` |

Not built, because it needs §3 first: the organization console (create / edit /
assign / switch). There is no endpoint to call.

> `feature_flags.dart` also references `docs/ACCESS_CONTROL_DESIGN.md` §8 and
> `docs/BACKEND_CHANGE_REQUEST.md`. Both were deleted in an earlier merge; those
> pointers are dangling and this file supersedes them for the role-tier work.
