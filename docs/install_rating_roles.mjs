/**
 * Lets MANAGEMENT and SUPER_ADMIN actually rate.
 *
 *     node D:\Vistar\krafrontend\docs\install_rating_roles.mjs --dry
 *     node D:\Vistar\krafrontend\docs\install_rating_roles.mjs
 *
 * Idempotent; backs the file up as <name>.bak before writing. All-or-nothing:
 * if any anchor fails to match, nothing is written.
 *
 * ── THE BUG ─────────────────────────────────────────────────────────────────
 *
 * Two things decide who may rate a stage, and neither knew about MANAGEMENT or
 * SUPER_ADMIN:
 *
 *   1. ACTOR_ROLES.MANAGEMENT_REVIEW = ['ADMIN', 'HR_ADMIN'].
 *      MANAGEMENT — the role the stage is NAMED after, the founder/CEO tier
 *      that exclusively owns the sign-off — is simply absent. And 'ADMIN' is
 *      not a value of the Prisma kra."UserRole" enum at all, so it can never
 *      match anything: HR_ADMIN is the only role that can sign off today.
 *
 *   2. Every enforcement site compares `user.role` DIRECTLY against that list.
 *      `middleware/rbac.middleware.js` already defines the role hierarchy —
 *      IMPLIED_ROLES.SUPER_ADMIN holds every seat beneath it, and requireRoles
 *      honours it on every route — but this service never consults it. So a
 *      SUPER_ADMIN passes the route guard, reaches the service, and is refused
 *      by a flat includes().
 *
 * The result, for a MANAGEMENT user on an ADMIN_ONLY organization:
 *
 *     POST /save-scores       403  Role MANAGEMENT cannot rate MANAGEMENT_REVIEW.
 *     POST /lock-management   403  Role MANAGEMENT cannot lock the management review.
 *     POST /unlock-management 403  Role MANAGEMENT cannot reopen the management review.
 *
 * The ADMIN_ONLY flow ENDS on MANAGEMENT_REVIEW, so this removed the flow's
 * final step entirely — which is why it still looked dead after the client-side
 * dead-lock was fixed. HR and FINANCE are in the table and always worked.
 *
 * ── WHAT CHANGES ────────────────────────────────────────────────────────────
 *
 *   1. MANAGEMENT is added to ACTOR_ROLES.MANAGEMENT_REVIEW — a genuinely
 *      missing seat. Nothing else implies MANAGEMENT, so it has to be named.
 *
 *   2. A single `canActOnStage(user, stage)` helper replaces the five flat
 *      includes() checks. It resolves the caller's roles through
 *      rolesHeldBy() from rbac.middleware.js — the ONE hierarchy already in
 *      the codebase — so SUPER_ADMIN inherits every rating seat automatically,
 *      and keeps inheriting them as stages are added.
 *
 * SUPER_ADMIN is deliberately NOT written into any ACTOR_ROLES list. Restating
 * a role list in a second place is exactly the defect being fixed here; a fresh
 * copy would drift from rbac.middleware.js the first time either changed.
 *
 * The five sites: assertCanAct (submit-stage), saveScores (edit-in-place — the
 * path the quarterly sheet actually uses for every rating), markPaid,
 * lockManagement, unlockManagement.
 *
 * ── WHAT DELIBERATELY DOES *NOT* CHANGE ─────────────────────────────────────
 *
 *   * SELF_RATING and REPORTING_MANAGER_RATING are RELATIONSHIP-gated on
 *     employee_id / manager_id, and both call sites return or throw in those
 *     branches BEFORE any role list is consulted. So this grants a super admin
 *     nothing there — correctly. Nobody should be able to enter an employee's
 *     own self-assessment, or a reporting-manager rating they don't own.
 *
 *   * HR_ADMIN is NOT added to FINANCE_RATING, even though the CLIENT's table
 *     has it. That would widen authority inside the STANDARD flow, which is in
 *     production. Real divergence, separate decision — see
 *     docs/RATING_ROLE_DIVERGENCE.md.
 *
 *   * No route guards change. Per-review gating has to live in the service (a
 *     route-level role cannot express "the reporting manager of THIS review").
 *
 * ── AFTER RUNNING ───────────────────────────────────────────────────────────
 *
 * A super admin whose organization_id is NULL still 404s on every review until
 * they switch into an organization: every entry point compares
 * header.organization_id against the JWT's organizationId claim, and null
 * matches nothing. Switch org first, then rate.
 */
import fs from 'fs';

const KRA = 'D:/Vistar/vistar_CRM/src/modules/kra/dist';
const RBAC = `${KRA}/middleware/rbac.middleware.js`;
const DRY = process.argv.includes('--dry');

// `--target=<path>` patches a COPY instead of the deployed service, so the
// result can be syntax-checked (`node --check`) before the real file is
// touched. A patch script you can rehearse beats one you can only trust.
const targetArg = process.argv.find((a) => a.startsWith('--target='));
const SVC = targetArg
  ? targetArg.slice('--target='.length)
  : `${KRA}/features/monthly-reviews/monthly-reviews.service.js`;

const EDITS = [
  {
    marker: 'const rbac_middleware_1 = require("../../middleware/rbac.middleware");',
    find: 'const monthly_reviews_repository_1 = require("./monthly-reviews.repository");',
    replace: [
      'const monthly_reviews_repository_1 = require("./monthly-reviews.repository");',
      '// The role hierarchy (IMPLIED_ROLES / rolesHeldBy) — so per-stage gating in',
      '// this service honours the same implications as every route guard.',
      'const rbac_middleware_1 = require("../../middleware/rbac.middleware");',
    ].join('\n'),
  },
  {
    marker: 'function canActOnStage(user, stage)',
    find: [
      'const ACTOR_ROLES = {',
      "    SELF_RATING: ['EMPLOYEE', 'OPS_EXCELLENCE', 'OPS'],",
      "    REPORTING_MANAGER_RATING: ['MANAGER', 'BD_MANAGER', 'WAREHOUSE_MGR'],",
      "    ACCOUNT_HR_RATING: ['HR_ADMIN', 'HR'],",
      "    FINANCE_RATING: ['FINANCE'],",
      "    MANAGEMENT_REVIEW: ['ADMIN', 'HR_ADMIN'],",
      "    INCENTIVE_PAYOUT: ['FINANCE', 'HR_ADMIN', 'HR'],",
      '    COMPLETED: [],',
      '};',
    ].join('\n'),
    replace: [
      'const ACTOR_ROLES = {',
      '    // Relationship-gated on the server (employee_id / manager_id). Both call',
      '    // sites return or throw in those branches BEFORE reaching a role list, so',
      '    // these two entries are unreachable fallbacks. Adding an admin role here',
      '    // grants nothing — and entering someone else\'s self-assessment is not a',
      '    // thing that should be possible.',
      "    SELF_RATING: ['EMPLOYEE', 'OPS_EXCELLENCE', 'OPS'],",
      "    REPORTING_MANAGER_RATING: ['MANAGER', 'BD_MANAGER', 'WAREHOUSE_MGR'],",
      "    ACCOUNT_HR_RATING: ['HR_ADMIN', 'HR'],",
      "    FINANCE_RATING: ['FINANCE'],",
      '    // MANAGEMENT holds the sign-off it is named after. It was missing, so the',
      '    // ADMIN_ONLY flow — which ENDS on this stage — 403\'d on its final step',
      '    // even though the client offered the button. \'ADMIN\' is kept for',
      '    // compatibility but is dead: it is not a value of the kra."UserRole" enum.',
      "    MANAGEMENT_REVIEW: ['ADMIN', 'HR_ADMIN', 'MANAGEMENT'],",
      "    INCENTIVE_PAYOUT: ['FINANCE', 'HR_ADMIN', 'HR'],",
      '    COMPLETED: [],',
      '};',
      '// SUPER_ADMIN appears in NONE of the lists above, on purpose. The role',
      '// hierarchy already exists once, in middleware/rbac.middleware.js, where',
      '// IMPLIED_ROLES.SUPER_ADMIN holds every seat beneath it and requireRoles',
      '// honours it on every route. This service used to compare user.role directly',
      '// against ACTOR_ROLES, bypassing that hierarchy entirely: a super admin',
      '// cleared the route guard and was then refused by the service. Copying',
      "// 'SUPER_ADMIN' into five lists would fix today and drift tomorrow;",
      '// resolving through rolesHeldBy() cannot.',
      'function canActOnStage(user, stage) {',
      '    const allowed = ACTOR_ROLES[stage] || [];',
      '    const held = (0, rbac_middleware_1.rolesHeldBy)(user.role);',
      '    return allowed.some((r) => held.includes(r));',
      '}',
    ].join('\n'),
  },
  {
    marker: 'if (!canActOnStage(user, stage)) {',
    find: [
      '    const allowed = ACTOR_ROLES[stage] || [];',
      '    if (!allowed.includes(user.role)) {',
      '        throw new http_errors_1.ForbiddenError(`Role ${user.role} cannot act on ${stage}.`);',
      '    }',
      '}',
    ].join('\n'),
    replace: [
      '    if (!canActOnStage(user, stage)) {',
      '        throw new http_errors_1.ForbiddenError(`Role ${user.role} cannot act on ${stage}.`);',
      '    }',
      '}',
    ].join('\n'),
  },
  {
    marker: "if (!canActOnStage(user, 'INCENTIVE_PAYOUT')) {",
    find: '        if (!ACTOR_ROLES.INCENTIVE_PAYOUT.includes(user.role)) {',
    replace: "        if (!canActOnStage(user, 'INCENTIVE_PAYOUT')) {",
  },
  {
    marker: "if (!canActOnStage(user, 'MANAGEMENT_REVIEW'))\n            throw new http_errors_1.ForbiddenError(`Role ${user.role} cannot lock",
    find: [
      '        if (!ACTOR_ROLES.MANAGEMENT_REVIEW.includes(user.role))',
      '            throw new http_errors_1.ForbiddenError(`Role ${user.role} cannot lock the management review.`);',
    ].join('\n'),
    replace: [
      "        if (!canActOnStage(user, 'MANAGEMENT_REVIEW'))",
      '            throw new http_errors_1.ForbiddenError(`Role ${user.role} cannot lock the management review.`);',
    ].join('\n'),
  },
  {
    marker: "if (!canActOnStage(user, 'MANAGEMENT_REVIEW'))\n            throw new http_errors_1.ForbiddenError(`Role ${user.role} cannot reopen",
    find: [
      '        if (!ACTOR_ROLES.MANAGEMENT_REVIEW.includes(user.role))',
      '            throw new http_errors_1.ForbiddenError(`Role ${user.role} cannot reopen the management review.`);',
    ].join('\n'),
    replace: [
      "        if (!canActOnStage(user, 'MANAGEMENT_REVIEW'))",
      '            throw new http_errors_1.ForbiddenError(`Role ${user.role} cannot reopen the management review.`);',
    ].join('\n'),
  },
  {
    marker: '            if (!canActOnStage(user, stage))',
    find: [
      '            const allowed = ACTOR_ROLES[stage] || [];',
      '            if (!allowed.includes(user.role))',
      '                throw new http_errors_1.ForbiddenError(`Role ${user.role} cannot rate ${stage}.`);',
    ].join('\n'),
    replace: [
      '            if (!canActOnStage(user, stage))',
      '                throw new http_errors_1.ForbiddenError(`Role ${user.role} cannot rate ${stage}.`);',
    ].join('\n'),
  },
];

// ── Preflight: the hierarchy this patch leans on must actually be there ──────
if (!fs.existsSync(SVC)) {
  console.error(`FAIL  not found: ${SVC}`);
  process.exit(1);
}
if (!fs.existsSync(RBAC)) {
  console.error(`FAIL  not found: ${RBAC}`);
  process.exit(1);
}
const rbacSrc = fs.readFileSync(RBAC, 'utf8');
if (!rbacSrc.includes('IMPLIED_ROLES') || !/exports\.rolesHeldBy\s*=/.test(rbacSrc)) {
  console.error('FAIL  rbac.middleware.js does not export rolesHeldBy/IMPLIED_ROLES.');
  console.error('      This patch resolves SUPER_ADMIN through that hierarchy, so it');
  console.error('      must exist first. Apply the rbac hierarchy patch, then re-run.');
  process.exit(1);
}
console.log('  PRE    rbac.middleware.js exports rolesHeldBy — hierarchy available');

let applied = 0;
let skipped = 0;
let failed = 0;
let src = fs.readFileSync(SVC, 'utf8');
const eol = src.includes('\r\n') ? '\r\n' : '\n';
const N = (t) => t.split('\n').join(eol);
const name = SVC.split('/').pop();

for (const e of EDITS) {
  const label = e.marker.split('\n')[0].trim().slice(0, 56);

  if (src.includes(N(e.marker))) {
    console.log(`  SKIP   ${label} — already present`);
    skipped++;
    continue;
  }

  const find = N(e.find);
  const hits = src.split(find).length - 1;
  if (hits !== 1) {
    console.error(`  FAIL   ${label} — anchor matched ${hits} times, expected 1`);
    failed++;
    continue;
  }

  src = src.replace(find, N(e.replace));
  console.log(`  ${DRY ? 'WOULD ' : 'OK    '} ${label}`);
  applied++;
}

// All-or-nothing. A half-patched service could define canActOnStage while some
// call sites still use the flat includes(), which is harder to reason about
// than either end state.
if (failed > 0) {
  console.error('');
  console.error(`FAILED — ${failed} anchor(s) did not match. NOTHING was written.`);
  console.error('The file has probably been edited by hand or by an older version of');
  console.error(`this script. Diff it against ${name}.bak if one exists.`);
  process.exit(1);
}

console.log('');
if (DRY) {
  console.log(`dry run: ${applied} would apply, ${skipped} already done`);
  process.exit(0);
}

if (applied > 0) {
  fs.copyFileSync(SVC, `${SVC}.bak`);
  fs.writeFileSync(SVC, src, 'utf8');
  console.log(`applied=${applied} skipped=${skipped} -> ${name}`);
  console.log('');
  console.log('Next: restart / redeploy the API.');
  console.log('');
  console.log('Verify — as a MANAGEMENT user on an ADMIN_ONLY organization:');
  console.log('  open the quarterly sheet for the employee, press "Save & Lock"');
  console.log('  expect 200, not 403 "Role MANAGEMENT cannot lock ..."');
  console.log('Verify — as SUPER_ADMIN, AFTER switching into that organization:');
  console.log('  enter an HR score; expect 200, not 403 and not 404');
  console.log('');
  console.log(`  restore: copy ${name}.bak ${name}`);
} else {
  console.log(`nothing to do (applied=0 skipped=${skipped}) — already patched`);
}
