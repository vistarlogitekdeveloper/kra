# Who may rate: the client and server disagree

Two hand-maintained tables decide the same question, and nothing keeps them in
step:

| | file | symbol |
|---|---|---|
| client | `lib/features/reviews/data/models/review_stage.dart` | `ReviewStage.actorRoles` |
| server | `.../kra/dist/features/monthly-reviews/monthly-reviews.service.js` | `ACTOR_ROLES` |

The client's table decides whether a cell opens and whether a button renders.
The server's decides whether the save succeeds. When they disagree the user gets
the worst possible outcome: an editable cell, a typed score, and a `403` on save.

## State as of 2026-09-09

`SELF_RATING` and `REPORTING_MANAGER_RATING` are omitted — the server gates
those on `employee_id` / `manager_id`, so its role lists there are dead code.

| stage | client | server | verdict |
|---|---|---|---|
| `ACCOUNT_HR_RATING` | HR, HR_ADMIN, SUPER_ADMIN | HR_ADMIN, HR | SUPER_ADMIN missing — **fixed by `install_rating_roles.mjs`** |
| `FINANCE_RATING` | FINANCE, HR_ADMIN, SUPER_ADMIN | FINANCE | SUPER_ADMIN **fixed**; HR_ADMIN **open, see below** |
| `MANAGEMENT_REVIEW` | MANAGEMENT, HR_ADMIN¹, SUPER_ADMIN | ADMIN, HR_ADMIN | MANAGEMENT + SUPER_ADMIN missing — **fixed** |
| `INCENTIVE_PAYOUT` | FINANCE, HR_ADMIN, SUPER_ADMIN | FINANCE, HR_ADMIN | SUPER_ADMIN missing — **fixed**; HR **closed 2026-11-17, see below** |

¹ `HR_ADMIN` only while `FeatureFlags.roleTiers` is off, which is the default.

`ADMIN` appears in the server's `MANAGEMENT_REVIEW` list but is not a value of
the Prisma `UserRole` enum, so it can never match. Harmless, but it is not the
admin escape hatch it looks like.

## Why the MANAGEMENT_REVIEW gap mattered so much

The `ADMIN_ONLY` review flow **ends** on `MANAGEMENT_REVIEW`. A `MANAGEMENT`
user was offered "Save & Lock" and refused by the server, so the flow had no
final step at all — which read as "the new flow is broken" long after the
client-side dead-lock was fixed.

## Closed: plain HR on INCENTIVE_PAYOUT

The 2026-09-09 measurement recorded the server as `FINANCE, HR_ADMIN, HR`. It is
now `['FINANCE', 'HR_ADMIN']`, with a comment saying why: *"Not plain HR: the
app presents HR as review-only, and the payout reminders go to FINANCE and
HR_ADMIN alone (queries.payoutRecipients)."* So the server narrowed and the
register went stale.

That left an HR user with a rendered **Mark incentive paid** button and a
`403 Role HR cannot mark payout.` on tap — this class's worst outcome, on the
one action that moves money. Closed by **narrowing the client** to match:
`hr` is out of `incentivePayout.actorRoles`. Widening the server was the wrong
direction here, because the exclusion is a stated product decision backed by
who the payout reminders are addressed to, not an oversight.

## Still open: HR_ADMIN on FINANCE_RATING

The client deliberately gives `HR_ADMIN` the Accounts seat — see the comment on
`ReviewStage.financeRating`: *"the commercial/HR-admin post covers Accounts
rating as well, and a single UserRole can't express 'HR Admin AND Accounts'"*.
The server does not.

So an HR_ADMIN looking at an Accounts-assigned KRA gets an editable cell and a
`403 Role HR_ADMIN cannot rate FINANCE_RATING` on save. This is **pre-existing**
and lives in the STANDARD flow, which is in production, so it was left alone
rather than bundled into a fix for a different bug. Two ways to close it:

* **Widen the server** — add `HR_ADMIN` to `FINANCE_RATING`. Matches the stated
  intent, but grants a live role a rating seat it does not have today.
* **Narrow the client** — drop `hrAdmin` from `financeRating.actorRoles`. Safer,
  but HR admins lose a seat someone may already be relying on in practice.

This needs a product answer, not a code one.

## The real fix for the class

Neither table should exist twice. The durable version is for the server to
publish its table (`GET /reviews/monthly/actor-roles`, or a block on
`/auth/me`) and the client to render from that, so a stage the server refuses
cannot render an open cell. Until then, any edit to one table has to be mirrored
in the other by hand, and this document is the only thing tracking that.
