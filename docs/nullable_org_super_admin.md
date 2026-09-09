# Making the super admin's organization NULL

You asked how. This is the complete answer, in the order it has to happen.

The headline: **steps 1–2 are easy and make the account see NOTHING. Step 3 is
what makes it see everything, and it is ~190 call sites, 65 of them raw SQL.**

---

## Step 1 — Database (2 statements)

```sql
-- allow it
ALTER TABLE kra.employees ALTER COLUMN organization_id DROP NOT NULL;

-- apply it
UPDATE kra.employees SET organization_id = NULL WHERE employee_code = 'VLPL9001';

-- verify
SELECT employee_code, name, role, organization_id
  FROM kra.employees WHERE employee_code = 'VLPL9001';
```

A nullable foreign key is fine alongside `ON DELETE CASCADE`, and the
`@@index([organizationId])` keeps working.

## Step 2 — Prisma schema

`prisma/schema.prisma`, `model Employee`:

```prisma
organizationId String?       @map("organization_id")
organization   Organization? @relation(fields: [organizationId], references: [id], onDelete: Cascade)
```

Both must become optional — the scalar and the relation. Then regenerate the
client (`npx prisma generate`). The `Organization.employees` back-relation needs
no change.

---

## STOP — what happens if you stop here

The account will see an **empty app**, not everything.

Every read looks like `where: { organizationId }`. With the claim null, Prisma
compiles that to `WHERE organization_id IS NULL`, which matches only other
null-org rows — i.e. the super admin itself. So:

- `/employees` → 1 row (itself)
- `/hr/dashboard` → zeros
- `/kra-templates`, `/locations`, `/reviews/monthly` → empty

This is the opposite of the intent, and it is why I pushed back. Null is not
"no filter" — it is "filter for null".

---

## Step 3 — Make NULL mean "no filter"

This is the actual work. Every query site has to stop treating the org as a
required value and start treating null as "global scope".

### The Prisma pattern

```js
// before
return prisma.employee.findMany({ where: { organizationId } });

// after — omit the key entirely when null
return prisma.employee.findMany({
  where: { ...(organizationId ? { organizationId } : {}) },
});
```

And for the ownership checks, which are the isolation boundary:

```js
// before
if (!employee || employee.organizationId !== organizationId) {
  throw new NotFoundError('Employee');
}

// after — a null caller org bypasses the ownership check by design
if (!employee || (organizationId && employee.organizationId !== organizationId)) {
  throw new NotFoundError('Employee');
}
```

### Scope of the change

Measured in `src/modules/kra/dist`:

| Layer | Sites |
| --- | --- |
| Repositories (`*.repository.js`) | **61** |
| Services forwarding it | 18 files |
| Controllers (`req.user.organizationId`) | 64 |
| **Raw SQL (`$queryRaw` / `$executeRaw`)** | **65** |

Per-repository repository counts: monthly-reviews 11, kra-templates 7,
bulk-setup 5, locations 5, review-cycles 5, review-periods 5, templates 5,
kra-assignments 4, employees 3, reviews 3, users 3, bonus-slabs 3, auth 2.

### The raw SQL is the real hazard

65 sites use `$queryRaw` / `$executeRaw`. Those inherit no Prisma `where`
clause, so each needs its own conditional predicate — you cannot spread an
object into a SQL string:

```js
// a parameterised predicate that disappears when the org is null
const orgClause = organizationId ? `AND organization_id = $${n}` : '';
```

Every one of those 65 has to be edited by hand, and each carries two failure
modes:

- **forget the null branch** → the super admin sees nothing from that query
- **forget the filter** → *every* user sees every org's data through it

The second is a silent cross-tenant leak. It will not throw, no test will fail,
and it will not show up until someone notices another company's employees in a
list.

## Step 4 — Writes need an explicit target

`employees.controller.js` passes `req.user.organizationId` into create (64 such
call sites). With it null, a super admin creating an employee produces another
**null-org employee** — a second account with global visibility, created by
accident.

So `CreateEmployeeSchema` and `UpdateEmployeeSchema` must additionally accept
`organizationId` (they currently do not — 0 occurrences in either), honoured
only for `SUPER_ADMIN` and defaulting to `req.user.organizationId` for everyone
else.

## Step 5 — Login path

- `auth.service.issueTokenPair(userId, email, role, organizationId, meta)` signs
  the claim; it must accept and sign null.
- `auth.middleware` must put a null org on `req.user` without rejecting.
- `auth.repository.hasDirectReports(user.id, user.organizationId)` is called on
  every login and takes the org as its second argument — check it tolerates null
  rather than silently returning false (which would drop the manager workspace).

---

## The alternative, for comparison

`POST /organizations/switch` — already written, in
`docs/backend_patch_organizations.js`:

| | Nullable org | Switch route |
| --- | --- | --- |
| Sites to change | ~190 (65 raw SQL) | 1 new route |
| Silent-leak risk | High — one missed filter exposes all tenants to everyone | None; isolation logic untouched |
| Super admin sees | All orgs at once, in one list | One org at a time, any org on demand |
| Ownership checks | Must be weakened everywhere | Unchanged |
| Reversible | Schema migration + 190 edits | Delete one file |

The one genuine advantage of the nullable approach is a **single cross-org
list** — "all 49 users with their organization" in one grid. The switch route
cannot do that; it shows one tenant at a time.

If that combined view is what you actually want, there is a much smaller way to
get it: add **one** SUPER_ADMIN-only endpoint that deliberately queries across
organizations, e.g.

```
GET /organizations/employees   -> every employee + their organization
```

One new query with one intentional un-scoped read, gated on the role, instead of
weakening 190 sites. That gets you the cross-org view AND keeps every existing
isolation check exactly as it is. I would do this.
