# Backend RBAC findings

**Test target:** `https://vistar-crm.onrender.com/api/v1/kra/`
**Date of last probe:** 2026-06-06
**Probe tool:** [`scripts/probe-rbac.mjs`](../scripts/probe-rbac.mjs) — re-run with `node scripts/probe-rbac.mjs` after every backend change.

This document captures the latest results of probing the live test backend for role-based-access-control enforcement. The Flutter app trusts the server to enforce role on every endpoint — that is the right design, but **it is only safe if the backend is actually comprehensive**. The probe verifies the assumption.

---

## TL;DR

Six HR resource endpoints leak the full organisation's data to **any authenticated user, including an Employee role**. One of them (`/employees`) also returns the `passwordHash` field in its response body.

The `/hr/dashboard*` prefix is correctly gated. Manager endpoints correctly refuse Employee tokens.

---

## How verdicts are encoded

- ✅ 200 — allowed role; server returned data.
- ✅ 403 — disallowed role; server correctly refused.
- 🔴 200 LEAK — disallowed role; **server returned data that should have been refused**.

---

## Results (EMPLOYEE + MANAGER + HR_ADMIN tokens)

### HR endpoints — Employee + Manager should both receive 403

| Endpoint | EMPLOYEE | MANAGER | HR_ADMIN | Notes |
|---|---|---|---|---|
| `GET /employees?page=1&pageSize=5` | 🔴 **200 LEAK** | 🔴 **200 LEAK** | ✅ 200 | Returned all employees with `passwordHash` field exposed. |
| `GET /kra-templates?page=1&pageSize=5` | 🔴 **200 LEAK** | 🔴 **200 LEAK** | ✅ 200 | Full template list, all roles. |
| `GET /review-cycles?page=1&pageSize=5` | 🔴 **200 LEAK** | 🔴 **200 LEAK** | ✅ 200 | Org's cycle list. |
| `GET /locations?page=1&pageSize=5` | 🔴 **200 LEAK** | 🔴 **200 LEAK** | ✅ 200 | Project locations. |
| `GET /kra-assignments?page=1&pageSize=5` | 🔴 **200 LEAK** | 🔴 **200 LEAK** | ✅ 200 | Org's KRA assignment matrix. |
| `GET /bonus-slabs?page=1&pageSize=5` | 🔴 **200 LEAK** | 🔴 **200 LEAK** | ✅ 200 | Grade-level comp data (sensitive). |
| `GET /hr/dashboard` | ✅ 403 | ✅ 403 | ✅ 200 | Correctly gated. |
| `GET /hr/dashboard/recent-activity?limit=15` | ✅ 403 | ✅ 403 | ✅ 200 | Correctly gated. |

### Manager endpoints — Employee should receive 403

| Endpoint | EMPLOYEE | MANAGER | HR_ADMIN |
|---|---|---|---|
| `GET /manager/dashboard` | ✅ 403 | ✅ 200 | ✅ 200 |
| `GET /manager/team?page=1&limit=5` | ✅ 403 | ✅ 200 | ✅ 200 |

### Shared endpoints — every authenticated user should reach

| Endpoint | EMPLOYEE | MANAGER | HR_ADMIN |
|---|---|---|---|
| `GET /auth/me` | ✅ 200 | ✅ 200 | ✅ 200 |
| `GET /employee/profile` | ✅ 200 | ✅ 200 | ✅ 200 |

---

## Reproduction

```bash
node scripts/probe-rbac.mjs
```

The script auto-discovers test accounts from a candidate list — see [`scripts/probe-rbac.mjs`](../scripts/probe-rbac.mjs) for which emails it tries.

---

## Severity & impact

| Severity | Endpoint | Why |
|---|---|---|
| **Critical** | `GET /employees` | Returns `passwordHash` field. This must NEVER appear in any HTTP response, regardless of role. Even HR_ADMIN should not see it. |
| **Critical** | `GET /employees`, `/kra-templates`, `/review-cycles`, `/locations`, `/kra-assignments`, `/bonus-slabs` | A regular **Employee** can read the full HR data set — all employees' contact info + names + emails, all KRA templates including others' roles, all bonus slabs (grade-level comp). |

The Flutter app does not surface any UI that drives non-HR users to these endpoints, so the leak is only reachable by an attacker who knows the API paths. That still includes any employee with a valid login.

---

## Recommended backend fixes

1. **Strip `passwordHash` from every employee serializer** — at the model boundary, not at each call site.
2. **Add the existing HR-role guard middleware to** `/employees`, `/kra-templates`, `/review-cycles`, `/locations`, `/kra-assignments`, `/bonus-slabs`. The middleware is already correctly applied to `/hr/dashboard*` — the same allowlist (HR / HR_ADMIN / ADMIN) should cover the resource paths.
3. **Re-run** `node scripts/probe-rbac.mjs` after the fix and update this document. All 🔴 LEAK rows should turn into ✅ 403 (in the EMPLOYEE and MANAGER columns).

---

## Out of scope

This probe does not exercise:

- Write endpoints (POST/PATCH/DELETE) — they may have separate validation. Test these once the read leaks are closed.
- Cross-organisation access — every test account is in `org_vistar_test`. A multi-tenant probe needs accounts in at least two orgs.
- Token-refresh and 401-handling — covered by the frontend test suite.
