# Backend RBAC findings

**Test target:** `https://vistar-crm.onrender.com/api/v1/kra/`
**Date of last probe:** 2026-06-05
**Probe tool:** [`scripts/probe-rbac.mjs`](../scripts/probe-rbac.mjs) — re-run with `node scripts/probe-rbac.mjs` after every backend change.

This document captures the latest results of probing the live test backend for role-based-access-control enforcement. The Flutter app trusts the server to enforce role on every endpoint — that is the right design, but **it is only safe if the backend is actually comprehensive**. The probe verifies the assumption.

---

## TL;DR

Six HR resource endpoints leak the full organisation's data to any authenticated user. One of them (`/employees`) also returns the `passwordHash` field in its response body.

The `/hr/dashboard*` prefix is correctly gated. Manager and shared endpoints behave correctly.

---

## What was probed

Each test account logged in via `POST /auth/login`, then issued an authenticated `GET` against the listed paths. Verdict:

- ✅ 200 — allowed role; server returned data.
- ✅ 403 — disallowed role; server correctly refused.
- 🔴 200 LEAK — disallowed role; **server returned data that should have been refused**.

Only `manager@vistar.test` / `Vistar@123` was available in the test fleet at the time of the probe — the EMPLOYEE and HR_ADMIN account emails I tried (`employee@`, `hr@`, `hradmin@`, `admin@`, etc.) all returned 401 Invalid credentials. Provision the missing accounts and re-run the probe to fill out the rest of the grid.

---

## Results (MANAGER token)

### HR endpoints — manager should receive 403

| Endpoint | Verdict | Notes |
|---|---|---|
| `GET /employees?page=1&pageSize=5` | 🔴 **200 LEAK** | Returned **all 8 employees** in `org_vistar_test`, including `passwordHash` field. |
| `GET /kra-templates?page=1&pageSize=5` | 🔴 **200 LEAK** | Returned all 4 templates (BD_MANAGER, employee, etc.). |
| `GET /review-cycles?page=1&pageSize=5` | 🔴 **200 LEAK** | Returned the org's review cycle list. |
| `GET /locations?page=1&pageSize=5` | 🔴 **200 LEAK** | Returned the org's project locations. |
| `GET /kra-assignments?page=1&pageSize=5` | 🔴 **200 LEAK** | Returned all KRA assignments across all employees. |
| `GET /bonus-slabs?page=1&pageSize=5` | 🔴 **200 LEAK** | Returned all 4 grade-level bonus slabs (sensitive comp data). |
| `GET /hr/dashboard` | ✅ 403 | Correct. |
| `GET /hr/dashboard/recent-activity?limit=15` | ✅ 403 | Correct. |

### Manager endpoints — manager should receive 200

| Endpoint | Verdict |
|---|---|
| `GET /manager/dashboard` | ✅ 200 |
| `GET /manager/team?page=1&limit=5` | ✅ 200 |

### Shared endpoints — every authenticated user should receive 200

| Endpoint | Verdict |
|---|---|
| `GET /auth/me` | ✅ 200 |
| `GET /employee/profile` | ✅ 200 |

---

## Reproduction

```bash
node scripts/probe-rbac.mjs
```

Or step-by-step with `curl`:

```bash
# 1. Get a manager token (note the nested data.tokenPair.accessToken path)
TOKEN=$(curl -s -X POST https://vistar-crm.onrender.com/api/v1/kra/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"manager@vistar.test","password":"Vistar@123"}' \
  | node -e 'process.stdin.on("data",d=>console.log(JSON.parse(d).data.tokenPair.accessToken))')

# 2. This should return 403 but returns 200 with full data
curl -s -H "Authorization: Bearer $TOKEN" \
  'https://vistar-crm.onrender.com/api/v1/kra/employees?page=1&pageSize=5' \
  | head -c 500

# 3. Confirm the gated path correctly refuses
curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  https://vistar-crm.onrender.com/api/v1/kra/hr/dashboard
# → 403
```

---

## Severity & impact

| Severity | Endpoint | Why |
|---|---|---|
| **Critical** | `GET /employees` | Returns `passwordHash` field. This must NEVER appear in any HTTP response, regardless of role. Even HR_ADMIN should not see it. |
| **High** | `GET /employees`, `/kra-templates`, `/review-cycles`, `/locations`, `/kra-assignments`, `/bonus-slabs` | Any authenticated user (employee, ops, finance, etc.) can read the full HR data set including names, emails, grade-level compensation, and assignment matrix. |

The Flutter app does not surface any UI that drives non-HR users to these endpoints, so the leak is only reachable by an attacker who knows the API paths. That still includes any current employee with a valid login.

---

## Recommended backend fixes

1. **Strip `passwordHash` from every employee serializer** — at the model boundary, not at each call site.
2. **Add the existing HR-role guard middleware to** `/employees`, `/kra-templates`, `/review-cycles`, `/locations`, `/kra-assignments`, `/bonus-slabs`. The middleware is already correctly applied to `/hr/dashboard*` — the same allowlist (HR / HR_ADMIN / ADMIN) should cover the resource paths.
3. **Provision a non-manager test account** (`employee@vistar.test`) so the probe can verify employee → HR is also closed.
4. **Re-run** `node scripts/probe-rbac.mjs` after the fix and update this document. All 🔴 LEAK rows should turn into ✅ 403.

---

## Out of scope

This probe does not exercise:

- Write endpoints (POST/PATCH/DELETE) — they may have separate validation. Test these once the read leaks are closed.
- Cross-organisation access — every test account is in `org_vistar_test`. A multi-tenant probe needs accounts in at least two orgs.
- Token-refresh and 401-handling — covered by the frontend test suite.
