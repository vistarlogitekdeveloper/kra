# Access Control & Role Wiring — Design

How roles, review seats and workspaces should fit together in the Vistar KRA app,
what is wired today, and the exact backend contract needed to finish it.

Companion to [BACKEND_RBAC_FINDINGS.md](BACKEND_RBAC_FINDINGS.md) (server-side
enforcement audit). This document is the *client* model and the joint contract.

---

## 1. The one idea that fixes everything

Every access bug in this app so far came from collapsing **three independent
questions** into one `role` enum:

| Axis | Question it answers | Keyed on | Example |
|---|---|---|---|
| **Relationship** | Who am I *to this review*? | `employeeId` / `managerId` | I own this self-rating; I am this person's reporting manager |
| **Seat** | Which review seat do I hold? | role(s) | HR seat, Accounts seat, Management sign-off |
| **Privilege** | Which admin surface may I open? | role(s) | HR console, granting roles |

These are **orthogonal**. A person can be all three at once: a Commercial Manager
(relationship: rates his reports) who administers HR (privilege) and rates the
Accounts seat (seat). One enum value cannot say that — which is why the app kept
producing wrong answers.

**Rules that follow, and must never be broken:**

1. **Relationship stages are never role-gated.** Self-rating belongs to the
   review's owner and reporting-manager rating to its manager, whatever role
   either holds. A manager does not get *other people's* reviews by being a
   manager; they get them by being *that person's* manager.
2. **Seats are role-gated, never relationship-gated.** The HR seat is held by
   whoever holds the HR role, regardless of who reports to whom.
3. **Privilege is a strict tier above seats.** Holding a seat lets you rate.
   It must not let you hand out seats.
4. **Access is the union of held roles.** Two roles = both sets of rights.
5. **Unknown role ⇒ least privilege.** An unrecognised value resolves to
   `EMPLOYEE`, never to something powerful.

---

## 2. Role catalogue

Six roles. The five functional ones plus a super-admin tier.

| # | Role | Wire value | Holds | Grants |
|---|---|---|---|---|
| 1 | **Management** | `MANAGEMENT` | Sivadasan K, Prashant R. Tamhankar | Management review (stage 3 sign-off/override). Views stages 1–2. Reviews workspace. **No** HR console |
| 2 | **HR admin** | `HR_ADMIN` | Sagar Sasane | HR seat (stage 2). HR console: employees, templates, cycles, reports. **No** management sign-off |
| 3 | **Accounts admin** | `FINANCE` | Accounts staff | Accounts seat (stage 2), incentive payout (stage 4) |
| 4 | **Manager** | `MANAGER` (also `BD_MANAGER`, `WAREHOUSE_MGR`) | Reporting managers | Rates **their own direct reports** (relationship). My Team workspace |
| 5 | **Employee** | `EMPLOYEE` | Everyone | Own self-rating, own history. Default for every unknown value |
| — | **Super admin** | `SUPER_ADMIN` | Swati Kotkar | Everything HR admin has, **plus** granting roles. The only tier that may change access |

Notes:

- **Everyone is also an employee.** Every role self-rates their own KRA. Managers,
  HR admins and the founder all have their own reviews.
- **`ADMIN` and `SUPER_ADMIN` are the same client tier.** Both map to the app's
  super-admin. Use `SUPER_ADMIN` on the wire for clarity.
- **`OPS` / `OPS_EXCELLENCE` / `BD_MANAGER` / `WAREHOUSE_MGR`** exist in the
  backend enum and are understood by the client, but carry no special seat.
  Do **not** repurpose one as "Management" — a real holder would silently
  inherit sign-off authority.

### Capability matrix

| Capability | Employee | Manager | HR admin | Accounts | Management | Super admin |
|---|:--:|:--:|:--:|:--:|:--:|:--:|
| Self-rate own KRA | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Rate own direct reports | — | ✅ | ✅¹ | ✅¹ | ✅¹ | ✅¹ |
| HR seat (stage 2) | — | — | ✅ | — | — | ✅ |
| Accounts seat (stage 2) | — | — | ✅² | ✅ | — | ✅ |
| Management sign-off (stage 3) | — | — | — | — | ✅ | — ³ |
| Mark incentive paid (stage 4) | — | — | ✅ | ✅ | — | ✅ |
| View all employees' reviews | — | — | ✅ | ✅ | ✅ | ✅ |
| Edit employee records | — | — | ✅ | — | — | ✅ |
| **Grant/change roles** | — | — | **—** | — | — | **✅** |

¹ By relationship, not role — only if they *are* that person's reporting manager.
² Deliberate: see §7 decision log.
³ Super admin administers; it does not sign off on reviews. Grant `MANAGEMENT`
  as well if a person must do both.

---

## 3. Review pipeline ownership

Four cycles, seven stages. Deadline = day of the reference month.

| Cycle | Stage | Wire value | Owner | Gate | Due |
|:--:|---|---|---|---|:--:|
| 1 | Self-Rating | `SELF_RATING` | The employee | **Relationship** (`employeeId`) | 10th |
| 2 | Reporting Manager | `REPORTING_MANAGER_RATING` | Their manager | **Relationship** (`managerId`) | 13th |
| 2 | HR | `ACCOUNT_HR_RATING` | HR admin | Role | 13th |
| 2 | Accounts | `FINANCE_RATING` | Accounts admin | Role | 13th |
| 3 | Management Review | `MANAGEMENT_REVIEW` | **Management only** | Role | 15th |
| 4 | Incentive Payout | `INCENTIVE_PAYOUT` | Accounts / HR | Role | 20th |
| — | Completed | `COMPLETED` | — (terminal) | — | — |

The three cycle-2 raters work **in parallel** and are averaged per KRA into one
"Review" score. Cycle 3 either accepts that average or overrides it per KRA; the
override is final and feeds the incentive.

**Read vs write.** A reviewer sees the whole sheet and may edit **only their own
column**. So Management legitimately views stages 1–2 while being able to write
only the Mgmt column — which is what "should only be able to view the self rating
and stage 2 review" asks for. No extra view-permission layer is needed; the
column-level gate already does it.

---

## 4. Workspaces and roster scoping

Four workspaces. **The scoping rule differs by workspace, and mixing them up is
the "My Team shows everyone" bug.**

| Workspace | Route | Offered when | Roster shown |
|---|---|---|---|
| My KRA | `/employee/*` | always | **Self only** |
| My Team | `/manager/*` | user has direct reports | **Direct reports only — relationship-scoped** |
| Reviews | `/reviews/*` | holds a review seat | **Whole org — role-scoped** |
| HR Admin | `/hr/*` | HR admin / super admin | Whole org |

> **The rule: My Team is relationship-scoped. Reviews is role-scoped.**
>
> "My Team" answers *"the people who report to me"*. It must return the same rows
> for an HR admin who manages three people as for a plain manager who manages
> three people. Expanding it by role is always wrong — that is what made Sagar's
> My Team look like an org-wide review list.
>
> Conversely the Reviews workspace *should* be org-wide for HR / Accounts /
> Management: their seats apply to every employee.

**Consequence for eligibility:** My Team must be offered on "do you have
reports?", not "are you senior?". A super admin with nobody reporting to them has
no team; a Commercial Manager who is also an HR admin has one. This needs a
trustworthy `hasReports` signal (§5).

---

## 5. Backend contract

### 5.1 Required changes

**A. Extend the role enum** on `POST/PATCH /employees` and return the same values
from `/auth/login` and `/auth/me`:

```
EMPLOYEE | MANAGER | OPS_EXCELLENCE | OPS | HR | HR_ADMIN | FINANCE
        | BD_MANAGER | WAREHOUSE_MGR
        | MANAGEMENT      ← add
        | SUPER_ADMIN     ← add
```

Today anything else fails:

```json
{ "success": false, "error": { "message": "Validation failed", "code": "VAL_001",
  "details": { "role": ["Invalid option: expected one of \"EMPLOYEE\"|…"] } } }
```

Without `MANAGEMENT`, management sign-off cannot be separated from HR admin.
Without `SUPER_ADMIN`, role-granting cannot be separated from HR admin — and an
HR admin who can edit roles can promote themselves.

**B. Scope `GET /manager/team` by reporting line, not by role.** It must return
only employees whose `managerId` is the caller, for **every** role. It currently
returns 200 for the HR tier ([findings §Manager](BACKEND_RBAC_FINDINGS.md)); if
that response is the whole org, the client cannot correct it.

Also add `managerId` to each member so the client can verify scoping:

```json
{ "id": "…", "employeeCode": "VLPL1463", "name": "…", "managerId": "…", "currentReview": { … } }
```

**C. Always send `hasReports`** on login / `/auth/me`. It defaults to `false`
client-side, so an omitted flag silently hides My Team from real managers.

### 5.2 Optional — true multi-role

Accept and return a `roles` array alongside the scalar `role`:

```json
{ "role": "HR_ADMIN", "roles": ["HR_ADMIN", "FINANCE"] }
```

`role` stays the primary (used for display and roster scoping); `roles` is the
full grant set. The client already parses this and falls back to `{role}` when
absent.

**This is genuinely optional.** With the HR admin ↔ Accounts widening (§7),
nobody currently needs two roles. Add it when someone needs a combination the
seats don't already cover.

### 5.3 Compatibility

Send unknown roles at your peril: the client maps anything unrecognised to
`EMPLOYEE` (least privilege, with a debug warning) rather than crashing. So a new
role rolled out server-side **before** the client knows it looks like "that user
lost all their access", not like an error. Client first, then backend.

---

## 6. Where each decision lives

| Decision | File |
|---|---|
| Role enum, wire parsing, `roles` / `effectiveRoles` / `isSuperAdmin` | `features/auth/data/models/user.dart` |
| Workspace + route predicates (`canAccessHr`, `canReview`, `canAccessManager`, `*Any`) | `core/router/app_router.dart` |
| Which workspaces appear in the switcher | `core/widgets/workspace_switcher.dart` |
| Stage → seat map (`actorRoles`), relationship-stage flags | `features/reviews/data/models/review_stage.dart` |
| "Does this row need my action?" | `features/reviews/data/models/monthly_review_summary.dart` |
| Roster scoping per role (`_loadRoster`), review scope | `features/reviews/presentation/providers/monthly_review_providers.dart` |
| Designation → default role, Access role field | `features/hr/presentation/screens/employee_form_screen.dart` |
| My Team roster (backend-scoped) | `features/manager/presentation/providers/manager_team_providers.dart` |

**Add a role in one place, not nine.** `actorRoles` is the single source of truth
for seats; the predicates above are the single source for workspaces. Anything
that asks "is this user allowed to…" should call one of them rather than
comparing roles inline.

---

## 7. Decision log

| Decision | Why |
|---|---|
| Management ≠ HR admin | HR administers the cycle and rates the HR seat. Letting the same role also sign off means HR approves its own input. Sign-off is the last gate before money moves |
| HR admin also holds the Accounts seat | Sagar must run HR *and* accounting reviews, and a single `role` can't say both. Widening the seat achieved it with no backend change. Revisit if HR and Accounts must be genuinely separate |
| Granting roles is super-admin only | An HR admin who can edit roles can grant themselves any role. Privilege escalation, so it sits a tier above |
| Job title only *defaults* the role | Access and title are separate axes. Deriving role purely from title made `HR_ADMIN` unreachable, and "Founder and CEO" matched no rule and fell through to `EMPLOYEE` — the founder had no review access at all |
| Management titles matched first | Highest-privilege, narrowest seat. A title falling through to `EMPLOYEE` is a silent, hard-to-notice failure |
| Unknown role ⇒ `EMPLOYEE` | Fail closed. A typo or new server role must not grant access |
| Only the first selected role is saved | An unrecognised `roles` field risks 400ing *every* save, including ordinary ones. The form says so inline instead of letting a silent 400 explain it |
| `ADMIN` abandoned as the management role | The backend rejects it outright (`VAL_001`), so gating on it left the stage with **no** eligible actor |

---

## 8. Current state vs target

The client already implements the target state. It is **dormant behind two
compile-time flags** in `core/constants/feature_flags.dart`, both defaulting to
false = today's behaviour, so turning it on is a `--dart-define`, not a code
change. The test suite passes in **both** states.

| # | Item | Today (flags off) | Flags on | Blocked on |
|:--:|---|---|---|---|
| 1 | Management seat | `{management, hrAdmin}` — HR admins share it | `{management}` | `ROLE_TIERS` ← backend `MANAGEMENT` |
| 2 | Designation → Management | Management titles derive `HR_ADMIN` | Derive `MANAGEMENT` | `ROLE_TIERS` |
| 3 | Assignable roles in the form | The nine the server accepts | Plus `MANAGEMENT`, `SUPER_ADMIN` | `ROLE_TIERS` |
| 4 | Who may grant roles | Super admin **or** HR admin | Super admin only | `ROLE_TIERS` |
| 5 | Multi-role | Honoured in memory; only the primary persists | Full `roles[]` sent | `MULTI_ROLE` ← backend `roles[]` |
| 6 | My Team scoping | Backend decides; client cannot narrow it | — | Backend item B (no flag; needs `managerId`) |
| 7 | `hasReports` | Defaults to `false`; unverified | — | Backend item C |
| 8 | Quarterly dashboard badges | Pass the primary role only | — | Nothing. Left alone deliberately: harmless while nobody holds 2 roles, and the quarterly dashboard is explicitly frozen |

Note item 4: role granting is **deliberately** still open to HR admins while the
flag is off. Restricting it to a tier nobody can hold would leave no one able to
assign roles at all — including the assignments that bootstrap the tier itself.

### Rollout order

Each step is safe alone and leaves the app working. See
[BACKEND_CHANGE_REQUEST.md](BACKEND_CHANGE_REQUEST.md) for the full sequence.

1. Backend adds `MANAGEMENT` + `SUPER_ADMIN` to the enum and the auth payload.
2. **Assign them** — Sivadasan + Prashant → `MANAGEMENT`; Swati → `SUPER_ADMIN`.
   Do this *before* step 3, or management review has no eligible actor.
3. Rebuild the client with `--dart-define=ROLE_TIERS=true`.
4. Backend scopes `/manager/team` by reporting line, adds `managerId` +
   `hasReports`.
5. Client switches My Team eligibility to `hasReports` and drops the HR-tier
   bypass.
6. Optional: backend accepts `roles[]`, then rebuild with
   `--dart-define=MULTI_ROLE=true`.

---

## 9. Invariants worth a test

These are the rules that, once broken, are expensive to notice. Current coverage
lives in `test/features/auth/multi_role_access_test.dart`,
`test/features/reviews/review_stage_test.dart`,
`monthly_review_test.dart` and `monthly_review_summary_test.dart`.

1. An unknown wire role resolves to `EMPLOYEE`, never higher.
2. `MANAGEMENT` resolves to the management role — it must not silently demote.
3. Self-rating is actionable **only** by the review's owner, whatever their role.
4. Reporting-manager rating is actionable **only** by that review's manager, and
   fails closed when no manager is mapped.
5. Management review is never actionable by a reporting manager or plain HR.
6. Access is the union of held roles; each seat still refuses roles outside it.
7. `isSuperAdmin` is true for the admin tier only — **not** HR admin.
8. Reviewing does not imply the HR console (`canReview` ≠ `canAccessHr`).
9. Completed/terminal reviews are actionable by nobody.

---

## 10. Quick answers

**"Sagar shouldn't do management review."** Correct, and that's the target. Today
he shares it because `HR_ADMIN` is the only assignable tier above `HR`. One
backend enum value fixes it permanently.

**"Can we just hardcode the two people?"** Possible — gate stage 3 on a user-id
allowlist, the way the relationship stages work. It gives exclusivity with no
backend change, but access stops being data-driven: every joiner or leaver needs
an app release. Use it only as a stopgap.

**"Why is the HR dashboard showing 32% when July was 96%?"** Unrelated to access.
The HR dashboard aggregates a whole quarter and divides by three regardless of
how many months exist, so mid-quarter figures read low. The monthly list shows a
single month. Both are correct for their own period.

**"Who can change roles?"** Only the super admin, from the Access role field on
the employee form. That field is the single control point for all access in the
app — no other screen grants anything.
