# CRITICAL — cross-tenant data leak in all three feed list endpoints

**Confirmed by reading the deployed source. Affects every user, not just the
super admin. Independent of any change made in this session.**

I could not apply the fix myself — writes to `D:\Vistar\vistar_CRM` are denied in
this session. The three edits are below, ready to paste.

---

## The bug

`src/modules/kra/dist/features/feeds/hr-feed/hr-feed.service.js`, `list()`:

```js
const where = {
    month: { reviewCycle: { organizationId: actor.organizationId } },   // line 38  <- the ONLY org predicate
};
if (query.monthId)      where.monthId = query.monthId;
if (query.employeeId)   where.employeeId = query.employeeId;
if (query.reviewCycleId)
    where.month = { reviewCycleId: query.reviewCycleId };               // line 45  <- REASSIGNS it away
```

`where.month` is **reassigned**, not merged. The organisation predicate lives
nowhere else in the query, so supplying `?reviewCycleId=...` removes tenant
scoping completely and the query returns rows from **every organisation**.

### Present in all three feeds, identically

| Endpoint | File | Line |
| --- | --- | --- |
| `GET /feeds/hr` | `feeds/hr-feed/hr-feed.service.js` | 45 |
| `GET /feeds/accounts` | `feeds/accounts-feed/accounts-feed.service.js` | 47 |
| `GET /feeds/ops` | `feeds/ops-feed/ops-feed.service.js` | 120 |

### Why it is critical rather than merely wrong

The three **list** routes carry no role guard at all — only `authenticate`:

```js
hrFeedRouter.use(authenticate);                                    // :12
hrFeedRouter.get('/', validate(ListHrFeedQuerySchema,'query'), …); // :13  <- no requireRoles
hrFeedRouter.put('/',  requireRoles('HR_ADMIN'), …);               // :14  <- guarded
hrFeedRouter.post('/bulk', requireRoles('HR_ADMIN'), …);           // :15  <- guarded
```

The write siblings are role-gated; the reads are not. Same shape in
`accounts-feed.routes.js:13` (writes gated to `FINANCE`/`HR_ADMIN`) and
`ops-feed.routes.js:13` (writes gated to `OPS_EXCELLENCE`/`HR_ADMIN`).

So **any signed-in account — including a plain `EMPLOYEE` — can read every
organisation's HR, Accounts and Ops feed data** with one query parameter. No
elevated role required.

### Reproduction

Sign in as any user, then:

```
GET /api/v1/kra/feeds/hr?reviewCycleId=<a cycle id from another organization>
```

Without the parameter you get your own org. With it you get that cycle's rows
regardless of tenant. The claimed amplifier is the nested employee enrichment
at `hr-feed.service.js:81-84`, `accounts-feed.service.js:64-78` and
`ops-feed.service.js:163-166`, which each do
`prisma.employee.findMany({ where: { id: { in: employeeIds } } })` with no
organisation filter — so the foreign rows are hydrated with names and codes.
**I read the clobber and the route guards directly; I did not separately verify
the enrichment lines — check them while you are in the file.**

---

## The fix — three edits, same shape

Merge the cycle filter into the existing predicate instead of replacing it.

### 1. `feeds/hr-feed/hr-feed.service.js` — replace lines 44-45

```js
        // MERGE, never reassign. `where.month` carries the ONLY organisation
        // predicate on this query (month.reviewCycle.organizationId, set
        // above). Overwriting it with a bare { reviewCycleId } dropped that
        // predicate entirely, so any authenticated user could read EVERY
        // organisation's HR feed rows by supplying ?reviewCycleId=<any id>.
        if (query.reviewCycleId) {
            where.month = {
                reviewCycle: { organizationId: actor.organizationId },
                reviewCycleId: query.reviewCycleId,
            };
        }
```

### 2. `feeds/accounts-feed/accounts-feed.service.js` — replace lines 46-47

Identical block (the surrounding code is the same; the next statement is the
`Promise.all`).

### 3. `feeds/ops-feed/ops-feed.service.js` — replace line 120

Same block. This file writes the three `if`s on single lines, so it is one line
being replaced rather than two.

### Verify after patching

```bash
cd D:\Vistar\vistar_CRM\src\modules\kra\dist\features\feeds
grep -A4 "if (query.reviewCycleId)" hr-feed/hr-feed.service.js \
  accounts-feed/accounts-feed.service.js ops-feed/ops-feed.service.js \
  | grep -c "organizationId: actor.organizationId"
# expect 3
```

Then, against a deployed build, confirm that passing another organisation's
`reviewCycleId` returns **zero** rows rather than that organisation's rows.

---

## Separate decision: should the list routes be role-gated?

Fixing the clobber closes the **cross-tenant** hole, which is the urgent part.
It leaves a narrower question: within one organisation, should any employee be
able to read the HR / Accounts / Ops feeds? The write siblings are gated to
`HR_ADMIN` / `FINANCE` / `OPS_EXCELLENCE`, so the reads being open looks
unintentional.

I did **not** add guards there, because doing so changes who can load those
screens and could break the Flutter client if it calls them as an ordinary
employee. Worth checking against the app before tightening.

---

## Still unverified — do not treat as confirmed

The audit produced claims in four other modules that the adversarial
verification pass never reached (the run was interrupted). I verified **only**
the feeds finding above by reading the source. These remain unproven and each
needs the same treatment before being believed or acted on:

| Module | Claim, in brief |
| --- | --- |
| `kra-assignments` | `PATCH /kra-assignments/:id` accepts a `templateId` from another org; the response then discloses that template's metadata |
| `bulk-setup` | `bulk-setup.service.js:51` / `:70` accept `managerId` / `projectLocationId` from the body unvalidated, inside one transaction over up to 1000 items |
| `monthly-reviews` | `monthly-reviews.service.js:385` hydrates before the `canView` check; `submit-stage` / `mark-paid` error strings leak stage state as an existence oracle |
| `employees` | `projectLocationId` / `defaultTemplateId` accepted via Prisma `connect` without an org check; `employeeCode` is globally `@unique`, giving a cross-tenant existence oracle |

A recurring theme worth noting: several claims are about **write-side reference
validation** — accepting an id that belongs to another organisation. That is the
same class of bug as the clobber, and `employees.service.js` already validates
`managerId`'s organisation, which suggests the check simply was not extended to
the other foreign keys.
